const fs = require("fs")
const { Location, ReturnType, CodeLanguage } = require("@chainlink/functions-toolkit")

// Configure the request by setting the fields below
const requestConfigTsla = {
  // String containing the source code to be executed
  source: fs.readFileSync("./functions/sources/mintTsla.js").toString(),
  //source: fs.readFileSync("./API-request-example.js").toString(),
  // Location of source code (only Inline is currently supported)
  codeLocation: Location.Inline,
  // Optional. Secrets can be accessed within the source code with `secrets.varName` (ie: secrets.apiKey). The secrets object can only contain string values.
  secrets: {
    alpacaKey: process.env.ALPACA_KEY ?? "",
    alpacaSecret: process.env.ALPACA_SECRET ?? "" ,
    alpacaBrokerKey: process.env.ALPACA_BROKER_KEY ?? "",
    alpacaBrokerSecret: process.env.ALPACA_BROKER_SECRET ?? ""
  },
  // Optional if secrets are expected in the sourceLocation of secrets (only Remote or DONHosted is supported)
  secretsLocation: Location.DONHosted,
  // Args (string only array) can be accessed within the source code with `args[index]` (ie: args[0]).
  args: [],
  // Code language (only JavaScript is currently supported)
  codeLanguage: CodeLanguage.JavaScript,
  // Expected type of the returned value
  expectedReturnType: ReturnType.uint256,
}

// Configure the request by setting the fields below
/*const requestConfigIbta = {
  // String containing the source code to be executed
  source: fs.readFileSync("./functions/sources/mintIbta.js").toString(),
  //source: fs.readFileSync("./API-request-example.js").toString(),
  // Location of source code (only Inline is currently supported)
  codeLocation: Location.Inline,
  // Optional. Secrets can be accessed within the source code with `secrets.varName` (ie: secrets.apiKey). The secrets object can only contain string values.
  secrets: {
    alpacaKey: process.env.ALPACA_KEY ?? "",
    alpacaSecret: process.env.ALPACA_SECRET ?? "" ,
    alpacaBrokerKey: process.env.ALPACA_BROKER_KEY ?? "",
    alpacaBrokerSecret: process.env.ALPACA_BROKER_SECRET ?? ""
  },
  // Optional if secrets are expected in the sourceLocation of secrets (only Remote or DONHosted is supported)
  secretsLocation: Location.DONHosted,
  // Args (string only array) can be accessed within the source code with `args[index]` (ie: args[0]).
  args: [],
  // Code language (only JavaScript is currently supported)
  codeLanguage: CodeLanguage.JavaScript,
  // Expected type of the returned value
  expectedReturnType: ReturnType.uint256,
}*/

module.exports = requestConfigTsla
