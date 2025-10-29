if (
  secrets.alpacaBrokerKey == "" ||
  secrets.alpacaBrokerSecret === "" ||
  secrets.alpacaTradingKey === "" ||
  secrets.alpacaTradingSecret === ""
) {
  throw Error("need alpaca keys")
}

async function main() {
  const asset =  "TSLA"
  const usdAmount = "100000000"
  const account_id = "19fc7732-a110-4446-b57a-7625fef30c4a"

  const amount = await buyAsset()
  return Functions.encodeUint256(Math.floor(amount))

  async function buyAsset() {
    const usdAmountFloat = parseFloat(usdAmount) / 1e6;

    // Create auth header using secrets
    const auth = 'Basic ' + btoa(`${secrets.alpacaTradingKey}:${secrets.alpacaTradingSecret}`)

    // Place the order
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
      }
    })

    const response = await alpacaRequestBuyAsset

    if (!response || response.status !== 200 || !response.data?.id) {
      console.log("Order failed:", response?.error || "Unknown error")
      return 0
    }

    const orderId = response.data.id
    console.log("Order placed:", orderId)

    // Poll for order status (max 5 attempts)
    for (let i = 0; i < 5; i++) {
      const statusRequest = Functions.makeHttpRequest({
        method: 'GET',
        url: `https://broker-api.sandbox.alpaca.markets/v1/trading/accounts/${account_id}/orders/${orderId}`,
        headers: {
          accept: 'application/json',
          authorization: auth
        }
      })

      const res = await statusRequest
      console.log(res)
      
      if (!res || res.status !== 200 || !res.data) {
        console.log("Status check failed")
        continue
      }

      console.log("Order status:", res.data.status, "Filled qty:", res.data.filled_qty)

      // Check if order is filled
      if (res.data.filled_qty && parseFloat(res.data.filled_qty) > 0) {
        const amountMinted = parseFloat(res.data.filled_qty) * 1e18;
        return amountMinted
      }

      // If order is completed but not filled, return 0
      if (res.data.status === 'canceled' || res.data.status === 'expired' || res.data.status === 'rejected') {
        console.log("Order not filled, status:", res.data.status)
        return 0
      }

      // Wait a bit before next check (if not last iteration)
      if (i < 4) {
        await new Promise(resolve => setTimeout(resolve, 1000))
      }
    }

    console.log("Order timeout - returning 0")
    return 0
  }
}

const result = await main()
return result