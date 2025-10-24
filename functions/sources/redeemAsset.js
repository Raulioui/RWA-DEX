if (
  secrets.alpacaBrokerKey == "" ||
  secrets.alpacaBrokerSecret === ""
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
        'APCA-API-KEY-ID': 'AKDP0IZ5RKE7POWX2BVU',
        'APCA-API-SECRET-KEY': 'WOH0tKFtvv9KXguY7OiyJnLVmFv3uYtdvwgCrwW2'
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
        authorization: 'Basic ' + btoa(`CK1V32HHFVQJ6XEM691F:DfEViqPT2V5JGccBfZZWZ3AgHysSA3adfemgyPr1`)
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
    console.log(response)

    if (!response || response.status !== 200) {
      return 0
    } else {
      return usdAmountToMint * 1e18
    }    
  }
}

const result = await main()
return result