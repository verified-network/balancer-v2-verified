import { Contract } from 'ethers';
import { deploy } from '@balancer-labs/v2-helpers/src/contract';
import { fp } from '@balancer-labs/v2-helpers/src/numbers';

import { RawMarginPoolDeployment, MarginPoolDeployment } from './types';

import Vault from '../../vault/Vault';
import Token from '../../tokens/Token';
import MarginPool from './MarginTradingPool';
import VaultDeployer from '../../vault/VaultDeployer';
import TypesConverter from '../../types/TypesConverter';

const NAME = 'Verified Liquidity Token';
const SYMBOL = 'VITTA';

export default {
  async deploy(params: RawMarginPoolDeployment, mockedVault: boolean): Promise<MarginPool> {
    const vaultParams = TypesConverter.toRawVaultDeployment(params);
    vaultParams.mocked = mockedVault;
    const vault = params.vault ?? (await VaultDeployer.deploy(vaultParams));

    const deployment = TypesConverter.toMarginPoolDeployment(params);

    const pool = await this._deployStandalone(deployment, vault);

    const { owner, 
            securityToken, 
            currencyToken, 
            securityType,
            cficode,
            minOrderSize,
            margin,
            collateral, 
            tradeFeePercentage 
          } = deployment;

    const poolId = await pool.getPoolId();
    const name = await pool.name();
    const symbol = await pool.symbol();
    const decimals = await pool.decimals();
    const bptToken = new Token(name, symbol, decimals, pool);

    return new MarginPool(
      pool,
      poolId,
      vault,
      securityToken,
      currencyToken,
      bptToken,
      securityType,
      cficode,
      minOrderSize,
      margin,
      collateral, 
      tradeFeePercentage, 
      owner
    );
  },

  async _deployStandalone(params: MarginPoolDeployment, vault: Vault): Promise<Contract> {
    const {
      securityToken,
      currencyToken,
      securityType,
      cficode,
      minOrderSize,
      margin,
      collateral, 
      tradeFeePercentage, 
      pauseWindowDuration,
      bufferPeriodDuration,
      from
    } = params;

    const owner = TypesConverter.toAddress(params.owner);

    let FactoryPoolParams ={
      name: NAME,
      symbol: SYMBOL,
      security: securityToken.address,
      currency: currencyToken.address,
      securityType: securityType,
      cficode: cficode,
      minOrderSize: minOrderSize,
      margin: margin,
      collateral: collateral,
      tradeFeePercentage: tradeFeePercentage
  }

    return deploy('pool-margin-trading/MarginTradingPool', {
      args: [
        vault.address,
        FactoryPoolParams,
        pauseWindowDuration,
        bufferPeriodDuration,
        owner
      ],
      from,
    });
  },
};
