const SLEEP_TIME = 5000 // 5 seconds

async function main() {
  /*const asset = args[0]
  const usdAmount = args[1]
  const account_id = args[2]*/
  const asset = "AAPL"
  const usdAmount = "100000000"
  const account_id = "b95b5a58-78b5-428a-bce0-9d1b74ab6029"

  const usdAmountFloat = Number(usdAmount) / 1e6
  const auth = 'Basic ' + btoa(`${secrets.alpacatradingkey}:${secrets.alpacatradingsecret}`)

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

  const [response] = await Promise.all([
    alpacaRequestBuyAsset,
  ])



      if (response?.status !== 200) {
        return Functions.encodeUint256(0)
    }

    const filled = await waitForOrderToFill(response.data.id, account_id, auth)

    if (!filled) {
      const cancelStatus = await cancelOrder(account_id, auth)
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

    console.log(responseRequest)
    
    const filled_qty = parseFloat(responseRequest.data.filled_qty)
    return Functions.encodeUint256(filled_qty * 1e18)
}

// returns int: responseStatus
async function cancelOrder(account_id, auth) {
  const alpacaCancelRequest = Functions.makeHttpRequest({
    method: 'DELETE',
    url: `https://broker-api.sandbox.alpaca.markets/v1/trading/accounts/${account_id}/orders`,
    headers: {
      'accept': 'application/json',
      authorization: auth
    }
  })

  const [response] = await Promise.all([
    alpacaCancelRequest,
  ])

  const responseStatus = response.status
  return responseStatus
}

// @returns bool
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
    if (response.data.filled_qty > 0 ) {
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