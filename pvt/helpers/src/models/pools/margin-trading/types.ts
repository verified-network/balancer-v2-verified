import { BigNumber, BytesLike, ContractReceipt } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';

import { Account, NAry } from '../../types/types';
import { BigNumberish } from '../../../numbers';

import Vault from '../../vault/Vault';
import Token from '../../tokens/Token';
import { SwapKind } from '@balancer-labs/balancer-js';

export type RawMarginPoolDeployment = {
  securityToken: Token;
  currencyToken: Token;
  securityType: BytesLike;
  cficode: BytesLike;
  minOrderSize : BigNumberish;
  margin : BigNumberish;
  collateral: BigNumberish;
  tradeFeePercentage: BigNumberish;
  pauseWindowDuration?: BigNumberish;
  bufferPeriodDuration?: BigNumberish;
  owner?: SignerWithAddress;
  admin?: SignerWithAddress;
  from?: SignerWithAddress;
  vault?: Vault;
};

export type MarginPoolDeployment = {
  securityToken: Token;
  currencyToken: Token;
  securityType: BytesLike;
  cficode: BytesLike;
  minOrderSize : BigNumberish;
  margin : BigNumberish;
  collateral: BigNumberish;
  tradeFeePercentage: BigNumberish;
  pauseWindowDuration: BigNumberish;
  bufferPeriodDuration: BigNumberish;
  owner?: SignerWithAddress;
  admin?: SignerWithAddress;
  from?: SignerWithAddress;
};

export type SwapMarginPool = {
  in: number;
  out: number;
  amount: BigNumberish;
  balances: BigNumberish[];
  recipient?: Account;
  from?: SignerWithAddress;
  lastChangeBlock?: BigNumberish;
  data?: string;
  eventHash?: string;
};

export type JoinExitMarginPool = {
  recipient?: Account;
  currentBalances?: BigNumberish[];
  lastChangeBlock?: BigNumberish;
  protocolFeePercentage?: BigNumberish;
  data?: string;
  from?: SignerWithAddress;
};

export type InitPrimaryPool = {
  initialBalances: NAry<BigNumberish>;
  from?: SignerWithAddress;
  recipient?: Account;
  protocolFeePercentage?: BigNumberish;
};

export type JoinResult = {
  amountsIn: BigNumber[];
  dueProtocolFeeAmounts: BigNumber[];
  receipt: ContractReceipt;
};

export type ExitResult = {
  amountsOut: BigNumber[];
  dueProtocolFeeAmounts: BigNumber[];
  receipt: ContractReceipt;
};

export type ExitGivenOutPrimaryPool = {
  amountsOut?: NAry<BigNumberish>;
  bptAmountIn: BigNumberish;
  recipient?: Account;
  from?: SignerWithAddress;
  lastChangeBlock?: BigNumberish;
  currentBalances?: BigNumberish[];
  protocolFeePercentage?: BigNumberish;
};

export type LimitOrderMarginPool = {
  in: number;
  out: number;
  kind: SwapKind;
  amount: BigNumberish;
  from?: SignerWithAddress;
  data?: string;
};