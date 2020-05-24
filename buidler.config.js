require("dotenv").config();

usePlugin("solidity-coverage");
usePlugin("@nomiclabs/buidler-waffle");

function getEnv(env) {
  let value = process.env[env];

  if (typeof value == "undefined") {
    value = "";
    console.error(`WARNING: ${env} environment variable has not been set`);
  }

  return value;
}

const mainnetEndpoint = getEnv("MAINNET_ENDPOINT");
const mainnetMnemonic = getEnv("MAINNET_MNEMONIC");

const kovanEndpoint = getEnv("KOVAN_ENDPOINT");
const kovanMnemonic = getEnv("KOVAN_MNEMONIC");

module.exports = {
  networks: {
    mainnet: {
      url: mainnetEndpoint,
      chainId: 1,
      accounts: {
        mnemonic: mainnetMnemonic
      }
    },
    kovan: {
      url: kovanEndpoint,
      chainId: 42,
      accounts: {
        mnemonic: kovanMnemonic
      }
    }
  },
  solc: {
    version: "0.6.6",
    optimizer: {
      enabled: true,
      runs: 999999
    }
  }
};
