const SLEEP_TIME = 5000 // 5 seconds

async function main() {
  const asset = args[0]
  const assetAmount = args[1]
  const account_id = args[2]

  const assetAmountFloat = Number(assetAmount) / 1e18
  const auth = 'Basic ' + btoa(`${secrets.alpacatradingkey}:${secrets.alpacatradingsecret}`)

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
      symbol: asset,
      qty: assetAmountFloat.toString()
    }
  })

  const [response] = await Promise.all([
    alpacaRequestSellAsset,
  ])

  if (response?.status !== 200) {
    return Functions.encodeUint256(0)
  }

  const filled = await waitForOrderToFill(response.data.id, account_id, auth)

  if (!filled) {
    const cancelStatus = await cancelOrder(response.data.id, account_id, auth)
    if (cancelStatus !== 200) {
      return Functions.encodeUint256(0)
    }
    return Functions.encodeUint256(0)
  }

  const request = Functions.makeHttpRequest({
    method: 'GET',
    url: `https://broker-api.sandbox.alpaca.markets/v1/trading/accounts/${account_id}/orders/${response.data.id}`,
    headers: {
      'accept': 'application/json',
      authorization: auth
    }
  })

  const [responseRequest] = await Promise.all([
    request,
  ])

  if(responseRequest?.status !== 200){
    return Functions.encodeUint256(0)
  }
    
  const filled_qty = parseFloat(responseRequest.data.filled_qty)

  return Functions.encodeUint256(filled_qty * 1e6)
}

async function cancelOrder(id, account_id, auth) {
  const alpacaCancelRequest = Functions.makeHttpRequest({
    method: 'DELETE',
    url: `https://broker-api.sandbox.alpaca.markets/v1/trading/accounts/${account_id}/orders/${id}`,
    headers: {
      'accept': 'application/json',
      authorization: auth
    }
  })

  const [response] = await Promise.all([
    alpacaCancelRequest,
  ])

  return response.status
}

async function waitForOrderToFill(id, account_id, auth) {
  let numberOfSleeps = 0
  const capNumberOfSleeps = 10
  let filled = false

  while (numberOfSleeps < capNumberOfSleeps) {
    const alpacaOrderStatusRequest = Functions.makeHttpRequest({
      method: 'GET',
      url: `https://broker-api.sandbox.alpaca.markets/v1/trading/accounts/${account_id}/orders/${id}`,
      headers: {
        'accept': 'application/json',
        authorization: auth
      }
    })

    const [response] = await Promise.all([
      alpacaOrderStatusRequest,
    ])

    if (response.status !== 200) {
      return false
    }

    if (response.data.filled_qty > 0) {
      filled = true
      break
    }
    numberOfSleeps++
    await sleep(SLEEP_TIME)
  }
  return filled
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms))
}

const result = await main()
return result