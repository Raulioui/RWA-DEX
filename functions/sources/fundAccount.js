if (
  secrets.alpacaBrokerKey == "" ||
  secrets.alpacaBrokerSecret === "" ||
  secrets.alpacaKey === "" ||
  secrets.alpacaSecret === ""
) {
  throw Error(
    "need alpaca keys"
  )
}

// Buy order for 1 IBTA in alpaca
const fundRequest = Functions.makeHttpRequest({
  url: `https://broker-api.sandbox.alpaca.markets/v1/accounts/${accountId}/transfers`,
  method: 'POST',
  headers: {
    accept: 'application/json', 
    'content-type': 'application/json',
    'Authorization': 'Basic ' + btoa(`${secrets.alpacaBrokerKey}:${secrets.alpacaBrokerSecret}`)
  },
  body: JSON.stringify({
    transfer_type: 'ach',
    direction: 'INCOMING',
    timing: 'immediate',
    amount: amount,
    relationship_id: ach
  })
})

const alpacaBalanceRequest = Functions.makeHttpRequest({
  url: "https://paper-api.alpaca.markets/v2/account",
  headers: {
    accept: 'application/json',
    'APCA-API-KEY-ID': secrets.alpacaKey,
    'APCA-API-SECRET-KEY': secrets.alpacaSecret
  }
})

const [response, alpacaBalance] = await Promise.all([fundRequest, alpacaBalanceRequest])

const portfolioBalance = alpacaBalance.data.portfolio_value
console.log(`Alpaca Portfolio Balance: $${portfolioBalance}`)

return Functions.encodeUint256(Math.round((portfolioBalance * 1000000000000000000) + (amount * 1000000000000000000)))