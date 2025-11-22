async function main() {  
  const asset = args[0]
  const usdAmount = args[1]
  const account_id = args[2]

  try {
    const amount = await buyAsset()
    return Functions.encodeUint256(Math.floor(amount))
  } catch (error) {
    console.error("Critical error:", error.message)
    return Functions.encodeUint256(0)
  }

  async function buyAsset() {
    const usdAmountFloat = Number(usdAmount) / 1e6
    const auth = 'Basic ' + btoa(`${secrets.alpacatradingkey}:${secrets.alpacatradingsecret}`)

    // STEP 1: Check for recent existing orders (last 30 seconds)
    // This prevents duplicate orders on Chainlink retries
    const recentOrdersRequest = Functions.makeHttpRequest({
      method: 'GET',
      url: `https://broker-api.sandbox.alpaca.markets/v1/trading/accounts/${account_id}/orders?status=all&limit=20`,
      headers: {
        accept: 'application/json',
        authorization: auth
      },
      timeout: 5000
    })

    const recentOrdersResponse = await recentOrdersRequest
    
    if (recentOrdersResponse?.data && Array.isArray(recentOrdersResponse.data)) {
      // Look for orders placed in the last 30 seconds for this asset
      const now = Date.now()
      const thirtySecondsAgo = now - 30000
      
      for (const order of recentOrdersResponse.data) {
        if (order.symbol !== asset) continue
        
        const orderTime = new Date(order.created_at).getTime()
        if (orderTime < thirtySecondsAgo) continue
        
        // Check if amounts match (within 1% tolerance)
        const orderNotional = parseFloat(order.notional || 0)
        const difference = Math.abs(orderNotional - usdAmountFloat)
        const tolerance = usdAmountFloat * 0.01 // 1% tolerance
        
        if (difference <= tolerance) {
          console.log("Found recent matching order:", order.id, "Status:", order.status)
          
          // If already filled, return the result
          if (order.filled_qty && parseFloat(order.filled_qty) > 0) {
            const filledQty = parseFloat(order.filled_qty) * 1e18
            console.log("Order already filled:", filledQty)
            return filledQty
          }
          
          // If pending/new, wait for it to fill
          if (order.status === 'new' || order.status === 'pending_new' || order.status === 'accepted') {
            console.log("Waiting for existing order to fill...")
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
              
              if (checkResponse?.data?.filled_qty && parseFloat(checkResponse.data.filled_qty) > 0) {
                const filledQty = parseFloat(checkResponse.data.filled_qty) * 1e18
                console.log("Existing order filled:", filledQty)
                return filledQty
              }
              
              if (checkResponse?.data?.status === 'filled') {
                const filledQty = parseFloat(checkResponse.data.filled_qty || 0) * 1e18
                return filledQty
              }
            }
            
            // If we timeout on existing order, return 0 to trigger refund
            console.log("Timeout waiting for existing order")
            return 0
          }
        }
      }
    }

    // STEP 2: No recent matching order found, create new order
    console.log("No recent matching order - placing new order")
    
    const alpacaRequestBuyAsset = Functions.makeHttpRequest({
      method: 'POST',
      url: `https://broker-api.sandbox.alpaca.markets/v1/trading/accounts/${account_id}/orders`,
      headers: {
        accept: 'application/json',
        'content-type': 'application/json',
        authorization: auth
      },
      data: {
        side: 'buy',
        type: 'market',
        time_in_force: 'day',
        commission_type: 'notional',
        symbol: asset,
        notional: usdAmountFloat.toString()
      },
      timeout: 5000
    })

    const response = await alpacaRequestBuyAsset

    if (!response || response.status !== 200 || !response.data?.id) {
      console.error("Order placement failed:", response?.error || response?.status || "Unknown")
      return 0
    }

    const orderId = response.data.id
    console.log("New order placed:", orderId)

    // STEP 3: Poll for order completion (reduced to 3 attempts)
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

      console.log(`Check ${i+1}: Status=${res.data.status}, Filled=${res.data.filled_qty}`)

      // Check if filled
      if (res.data.filled_qty && parseFloat(res.data.filled_qty) > 0) {
        const amountMinted = parseFloat(res.data.filled_qty) * 1e18
        console.log("Order filled successfully:", amountMinted)
        return amountMinted
      }

      // Handle terminal states
      if (res.data.status === 'filled') {
        const amountMinted = parseFloat(res.data.filled_qty || 0) * 1e18
        return amountMinted
      }

      if (res.data.status === 'canceled' || res.data.status === 'expired' || res.data.status === 'rejected') {
        console.log("Order failed with status:", res.data.status)
        return 0
      }
    }

    // If we timeout, return 0 (will trigger refund in smart contract)
    console.log("Polling timeout - order may still be pending")
    return 0
  }
}

const result = await main()
return result