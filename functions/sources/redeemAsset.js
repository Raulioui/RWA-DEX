async function main() {
  const asset = args[0]
  const account_id = args[1]
  const assetAmount = args[2]

  try {
    const amount = await sellAsset()
    return Functions.encodeUint256(Math.floor(amount))
  } catch (error) {
    console.error("Critical error:", error.message)
    return Functions.encodeUint256(0)
  }

  async function sellAsset() {
    const assetAmountInEth = Number(assetAmount) / 1e18
    const auth = 'Basic ' + btoa(`${secrets.alpacaTradingKey}:${secrets.alpacaTradingSecret}`)

    // STEP 1: Get current asset price
    const getAssetPrice = Functions.makeHttpRequest({
      method: 'GET',
      url: `https://data.alpaca.markets/v2/stocks/bars/latest?symbols=${asset}`,
      headers: {
        accept: 'application/json',
        'APCA-API-KEY-ID': secrets.alpacaBrokerKey,
        'APCA-API-SECRET-KEY': secrets.alpacaBrokerSecret
      },
      timeout: 5000
    })

    const priceResponse = await getAssetPrice

    if (!priceResponse || priceResponse.status !== 200 || !priceResponse.data?.bars?.[asset]) {
      console.error("Failed to get asset price")
      return 0
    }

    const assetPriceUsd = priceResponse.data.bars[asset].c
    const usdAmountExpected = assetAmountInEth * assetPriceUsd

    console.log(`Selling ${assetAmountInEth} ${asset} at $${assetPriceUsd} = $${usdAmountExpected}`)

    // STEP 2: Check for recent existing SELL orders (last 30 seconds)
    // This prevents duplicate orders on Chainlink retries
    const recentOrdersRequest = Functions.makeHttpRequest({
      method: 'GET',
      url: `https://broker-api.sandbox.alpaca.markets/v1/trading/accounts/${account_id}/orders?status=all&limit=20&side=sell`,
      headers: {
        accept: 'application/json',
        authorization: auth
      },
      timeout: 5000
    })

    const recentOrdersResponse = await recentOrdersRequest
    
    if (recentOrdersResponse?.data && Array.isArray(recentOrdersResponse.data)) {
      const now = Date.now()
      const thirtySecondsAgo = now - 30000
      
      for (const order of recentOrdersResponse.data) {
        // Only check sell orders for this asset
        if (order.symbol !== asset || order.side !== 'sell') continue
        
        const orderTime = new Date(order.created_at).getTime()
        if (orderTime < thirtySecondsAgo) continue
        
        // Check if amounts match (within 1% tolerance)
        const orderNotional = parseFloat(order.notional || 0)
        const difference = Math.abs(orderNotional - usdAmountExpected)
        const tolerance = usdAmountExpected * 0.01 // 1% tolerance
        
        if (difference <= tolerance) {
          console.log("Found recent matching sell order:", order.id, "Status:", order.status)
          
          // If already filled, return the result
          if (order.filled_avg_price && parseFloat(order.filled_avg_price) > 0) {
            const filledQty = parseFloat(order.filled_qty || 0)
            const filledPrice = parseFloat(order.filled_avg_price)
            const usdReceived = filledQty * filledPrice
            const usdReceivedInWei = Math.floor(usdReceived * 1e6) // USDT has 6 decimals
            console.log("Order already filled. USD received:", usdReceived)
            return usdReceivedInWei
          }
          
          // If pending/new, wait for it to fill
          if (order.status === 'new' || order.status === 'pending_new' || order.status === 'accepted' || order.status === 'partially_filled') {
            console.log("Waiting for existing sell order to fill...")
            const existingOrderId = order.id
            
            // Poll this existing order instead of creating new one
            for (let i = 0; i < 3; i++) {
              await new Promise(resolve => setTimeout(resolve, 2000))
              
              const checkRequest = Functions.makeHttpRequest({
                method: 'GET',
                url: `https://broker-api.sandbox.alpaca.markets/v1/trading/accounts/${account_id}/orders/${existingOrderId}`,
                headers: {
                  accept: 'application/json',
                  authorization: auth
                },
                timeout: 5000
              })
              
              const checkResponse = await checkRequest
              
              if (checkResponse?.data?.filled_avg_price && parseFloat(checkResponse.data.filled_avg_price) > 0) {
                const filledQty = parseFloat(checkResponse.data.filled_qty || 0)
                const filledPrice = parseFloat(checkResponse.data.filled_avg_price)
                const usdReceived = filledQty * filledPrice
                const usdReceivedInWei = Math.floor(usdReceived * 1e6)
                console.log("Existing order filled. USD received:", usdReceived)
                return usdReceivedInWei
              }
              
              if (checkResponse?.data?.status === 'filled') {
                const filledQty = parseFloat(checkResponse.data.filled_qty || 0)
                const filledPrice = parseFloat(checkResponse.data.filled_avg_price || assetPriceUsd)
                const usdReceived = filledQty * filledPrice
                const usdReceivedInWei = Math.floor(usdReceived * 1e6)
                return usdReceivedInWei
              }
              
              if (checkResponse?.data?.status === 'canceled' || checkResponse?.data?.status === 'expired' || checkResponse?.data?.status === 'rejected') {
                console.log("Existing order failed:", checkResponse.data.status)
                return 0
              }
            }
            
            // If we timeout on existing order, return 0 to trigger refund
            console.log("Timeout waiting for existing sell order")
            return 0
          }
        }
      }
    }

    // STEP 3: No recent matching order found, create new sell order
    console.log("No recent matching sell order - placing new order")
    
    const alpacaRequestSellAsset = Functions.makeHttpRequest({
      method: 'POST',
      url: `https://broker-api.sandbox.alpaca.markets/v1/trading/accounts/${account_id}/orders`,
      headers: {
        accept: 'application/json', 
        'content-type': 'application/json',
        authorization: auth
      },
      data: {
        side: 'sell',
        type: 'market',
        time_in_force: 'day',
        commission_type: 'notional',
        symbol: asset,
        notional: usdAmountExpected.toString()
      },
      timeout: 5000
    })
  
    const response = await alpacaRequestSellAsset

    if (!response || response.status !== 200 || !response.data?.id) {
      console.error("Sell order placement failed:", response?.error || response?.status || "Unknown")
      return 0
    }

    const orderId = response.data.id
    console.log("New sell order placed:", orderId)

    // STEP 4: Poll for order completion (3 attempts with 2 second intervals)
    for (let i = 0; i < 3; i++) {
      await new Promise(resolve => setTimeout(resolve, 2000))
      
      const statusRequest = Functions.makeHttpRequest({
        method: 'GET',
        url: `https://broker-api.sandbox.alpaca.markets/v1/trading/accounts/${account_id}/orders/${orderId}`,
        headers: {
          accept: 'application/json',
          authorization: auth
        },
        timeout: 5000
      })

      const res = await statusRequest
      
      if (!res || res.status !== 200 || !res.data) {
        console.log(`Status check ${i+1} failed`)
        continue
      }

      console.log(`Check ${i+1}: Status=${res.data.status}, Filled=${res.data.filled_qty}, Avg Price=${res.data.filled_avg_price}`)

      // Check if order is filled and calculate actual USD received
      if (res.data.filled_avg_price && parseFloat(res.data.filled_avg_price) > 0) {
        const filledQty = parseFloat(res.data.filled_qty || 0)
        const filledPrice = parseFloat(res.data.filled_avg_price)
        const usdReceived = filledQty * filledPrice
        const usdReceivedInWei = Math.floor(usdReceived * 1e6) // USDT has 6 decimals
        console.log(`Order filled! Qty: ${filledQty}, Price: ${filledPrice}, USD: ${usdReceived}`)
        return usdReceivedInWei
      }

      // Handle filled status
      if (res.data.status === 'filled') {
        const filledQty = parseFloat(res.data.filled_qty || 0)
        const filledPrice = parseFloat(res.data.filled_avg_price || assetPriceUsd)
        const usdReceived = filledQty * filledPrice
        const usdReceivedInWei = Math.floor(usdReceived * 1e6)
        return usdReceivedInWei
      }

      // Handle terminal failure states
      if (res.data.status === 'canceled' || res.data.status === 'expired' || res.data.status === 'rejected') {
        console.log("Sell order failed with status:", res.data.status)
        return 0
      }
    }

    // If we timeout, return 0 (will trigger refund in smart contract)
    console.log("Polling timeout - sell order may still be pending")
    return 0
  }
}

const result = await main()
return result