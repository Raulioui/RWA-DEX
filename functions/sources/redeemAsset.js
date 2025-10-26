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
  const account_id = args[1]
  const assetAmount = args[2]

  const amount = await sellAsset()

  return Functions.encodeUint256(amount)

  async function sellAsset() {

    const assetAmountInEth = Number(assetAmount) / 1e18;

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
  
    const usdAmountToMint = assetAmountInEth * assetPriceUsd

    const alpacaRequestBuyAsset = Functions.makeHttpRequest({
      method: 'POST',
      url: `https://broker-api.sandbox.alpaca.markets/v1/trading/accounts/${account_id}/orders`,
      headers: {
        accept: 'application/json', 
        'content-type': 'application/json',
        authorization: 'Basic ' + btoa(`${secrets.alpacaTradingKey}:${secrets.alpacaTradingSecret}`)
      },
      data: {
        side: 'sell',
        type: 'market',
        time_in_force: 'day',
        commission_type: 'notional',
        symbol: asset,
        qty: assetAmountInEth
      }
    })
  
    const response = await alpacaRequestBuyAsset

    if (!response || response.status !== 200) {
      return 0
    } else {
      return usdAmountToMint * 1e18
    }    
  }
}

const result = await main()
return result