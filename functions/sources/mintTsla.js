if (
    secrets.alpacaKey == "" ||
    secrets.alpacaSecret === ""
) {
    throw Error(
        "need alpaca keys"
    )
}

// // What does this script do? 
// // 1. Funds the user account
// // 2. Buys TSLA

async function main() {

    /*//////////////////////////////////////////////////////////////
                           FUNDING ACCOUNT
    //////////////////////////////////////////////////////////////*/

    const getAccountACH = await fetch(`https://broker-api.sandbox.alpaca.markets/v1/accounts/28fb7992-bf35-48e4-98b6-ce0aa36c2dae/ach_relationships`, {
        method: 'GET',
        headers: { 
            'Authorization': 'Basic ' + btoa(`${secrets.alpacaBrokerKey}:${secrets.alpacaBrokerSecret}`),
            'accept': 'application/json'
        },
      });
  
    const [response] = await Promise.all([
        getAccountACH,
    ])

    const res = await response.json()
    if(res.status !== 200) {
      await fundAccount(100, "28fb7992-bf35-48e4-98b6-ce0aa36c2dae", res[0].id)

      const fundingSuccess = await waitForFundingCompletion("28fb7992-bf35-48e4-98b6-ce0aa36c2dae", res[0].id);

      if (!fundingSuccess) {
          console.error(`Funding failed or not completed. Aborting.`);
          return;
      }
    }
    // amount, accountId, ach

    /*//////////////////////////////////////////////////////////////
                            BUYING TSLA  
    //////////////////////////////////////////////////////////////*/
    console.log("Buying tsla")
    //await buyTsla()
}


// returns int: responseStatus
async function buyTsla() {
  const alpacaCancelRequest = Functions.makeHttpRequest({
    method: 'POST',
    url: `https://paper-api.alpaca.markets/v2/orders`,
    headers: {
      'accept': 'application/json',
      'APCA-API-KEY-ID': secrets.alpacaKey,
      'APCA-API-SECRET-KEY': secrets.alpacaSecret,
    },
    data: {
      side: 'buy',
      type: 'market', 
      time_in_force: 'day',
      symbol: 'TSLA',
      qty: '1'
    }
  })

  const [response] = await Promise.all([
    alpacaCancelRequest,
  ])

  console.log(response)
}

const result = await main()
//console.log(result)
return Functions.encodeUint256(Math.round(1000000000000000000))