import '@nomiclabs/hardhat-ethers';
import '@nomiclabs/hardhat-waffle';

import { hardhatBaseConfig } from '@balancer-labs/v2-common';
import { name } from './package.json';

import { task } from 'hardhat/config';
import { TASK_COMPILE } from 'hardhat/builtin-tasks/task-names';
import overrideQueryFunctions from '@balancer-labs/v2-helpers/plugins/overrideQueryFunctions';
import { default as gasReporter } from 'hardhat-gas-reporter';

task(TASK_COMPILE).setAction(overrideQueryFunctions);

export default {
  solidity: {
    compilers: hardhatBaseConfig.compilers,
    overrides: { ...hardhatBaseConfig.overrides(name) },
  },
  gasReporter: {
    enabled: true,
    currency: 'USD',
    coinmarketcap: '91114b84-bec7-4d68-8cbf-c52a834105f9',
    gasPrice: 1000000000, // 1 gwei
    showTimeSpent: true,
    showMethodSig: true,
    excludeContracts: [], // add contract names to exclude from gas reporting
  },
  networks: {
    hardhat: {
      gasPrice: 1000000000, // 1 gwei
    },
  },
  plugins: [
    gasReporter,
  ],
};
