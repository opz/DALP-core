# DALP Smart Contracts

[![Actions Status](https://github.com/opz/DALP-core/workflows/CI/badge.svg)](https://github.com/opz/DALP-core/actions)

## Install Dependencies

`npm install`

## Compile Contracts

`npx buidler compile`

## Run Tests

`npx buidler test`

## Using DALP smart contracts

To use DALP smart contracts in a project, follow these steps:

```
git clone git@github.com:opz/DALP-core.git
cd DALP-core
npm install
npx buidler compile
npm link
cd <project_directory>
npm link dalp-core
```

You can now import the smart contract artifacts in your project:
```
import DALPManager from "dalp-core/artifacts/DALPManager.json";
import { DALPManagerAddress } from "dalp-core/artifacts/kovan.json";

const dalpManager = new web3.eth.Contract(DALPManager.abi, DALPManagerAddress);
```

## Contributors

Thanks to the following people who have contributed to this project:

* [@michaelcohen716](https://github.com/michaelcohen716) 💻
* [@opz](https://github.com/opz) 💻
