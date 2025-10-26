if (
  secrets.alpacaBrokerKey == "" ||
  secrets.alpacaBrokerSecret === "" ||
  secrets.alpacaTradingKey === "" ||
  secrets.alpacaTradingSecret === ""
) {
  throw Error(
    "need alpaca keys"
  )
}


async function main() {

  const asset = args[0]
  const usdAmount = args[1]
  const account_id = args[2]

  const amount = await buyAsset()

  return Functions.encodeUint256(amount)

  async function buyAsset() {

    const getAssetPrice = Functions.makeHttpRequest({
      method: 'GET',
      url: `https://data.alpaca.markets/v2/stocks/bars/latest?symbols=${asset}`,
      headers: {
        accept: 'application/json',
        'APCA-API-KEY-ID': secrets.alpacaBrokerKey,
        'APCA-API-SECRET-KEY': secrets.alpacaBrokerSecret
      }
    })

    const res = await getAssetPrice;
    const assetPriceUsd = res.data.bars[asset].c;

    const usdAmountFloat = parseFloat(usdAmount) / 1e6;

    const assetsToBuy = usdAmountFloat / assetPriceUsd;
    console.log(assetsToBuy)
    
    const alpacaRequestBuyAsset = Functions.makeHttpRequest({
      method: 'POST',
      url: `https://broker-api.sandbox.alpaca.markets/v1/trading/accounts/${account_id}/orders`,
      headers: {
        accept: 'application/json', 
        'content-type': 'application/json',
        authorization: 'Basic ' + btoa(`${secrets.alpacaTradingKey}:${secrets.alpacaTradingSecret}`)
      },
      data: {
        side: 'buy',
        type: 'market',
        time_in_force: 'day',
        symbol: asset,
        notional: assetsToBuy.toFixed(2) 
      }
    })
  
    const response = await alpacaRequestBuyAsset

    if (!response || response.status !== 200 || !response.data?.id) {
      console.log("Order failed:", response)
      return 0
    } else {
      console.log("Order successful:", response.data)
      return assetsToBuy * 1e18
    }    
  }
}

const result = await main()
return result