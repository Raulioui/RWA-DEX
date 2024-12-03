/*if (
  secrets.alpacaKey == "" ||
  secrets.alpacaSecret === ""
) {
  throw Error(
    "need alpaca keys"
  )
}

// Buy order for 1 IBTA in alpaca
const ibtaMintRequest = Functions.makeHttpRequest({
  url: "https://paper-api.alpaca.markets/v2/orders",
  method: 'POST',
  headers: {
    accept: 'application/json', 
    'content-type': 'application/json',
    'APCA-API-KEY-ID': secrets.alpacaKey,
    'APCA-API-SECRET-KEY': secrets.alpacaSecret
  },
  data: {
    side: "buy", // Type of order (buy or sell)
    type: "market", // Type of order (market or limit)
    time_in_force: "day", // Time in force (day, gtc, opg, cls, ioc, fok) 
    symbol: "IBTA", // symbol to identify the asset to trade
    qty: 1, // Number of shares to trade
  },
})

const alpacaBalanceRequest = Functions.makeHttpRequest({
  url: "https://paper-api.alpaca.markets/v2/account",
  headers: {
    accept: 'application/json',
    'APCA-API-KEY-ID': secrets.alpacaKey,
    'APCA-API-SECRET-KEY': secrets.alpacaSecret
  }
})

const [response, alpacaBalance] = await Promise.all([ibtaMintRequest, alpacaBalanceRequest])

const portfolioBalance = alpacaBalance.data.portfolio_value
console.log(`Alpaca Portfolio Balance: $${portfolioBalance}`)

return Functions.encodeUint256(Math.round(portfolioBalance * 1000000000000000000))*/