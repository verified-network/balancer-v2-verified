import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { defaultAbiCoder } from '@ethersproject/abi';
import { BigNumber, BytesLike, Contract, ContractTransaction } from 'ethers';

import { SwapKind, WeightedPoolEncoder } from '@balancer-labs/balancer-js';
import { actionId } from '../../misc/actions';
import { BigNumberish } from '@balancer-labs/v2-helpers/src/numbers';
import { ZERO_ADDRESS } from '@balancer-labs/v2-helpers/src/constants';
import * as expectEvent from '@balancer-labs/v2-helpers/src/test/expectEvent';

import { GeneralSwap } from '../../vault/types';
import { Account, TxParams } from '../../types/types';
import { 
  SwapMarginPool, 
  RawMarginPoolDeployment,
  JoinExitMarginPool, 
  InitPrimaryPool, 
  JoinResult,
  ExitGivenOutPrimaryPool,
  ExitResult,  
  LimitOrderMarginPool,
} from './types';

import Vault from '../../vault/Vault';
import Token from '../../tokens/Token';
import TokenList from '../../tokens/TokenList';
import TypesConverter from '../../types/TypesConverter';
import MarginPoolDeployer from './MarginTradingPoolDeployer';
import { deployedAt } from '../../../contract';
import BasePool from '../base/BasePool';
import Orderbook from './orderbook/Orderbook';

export default class MarginPool extends BasePool{
  instance: Contract;
  poolId: string;
  securityToken: Token;
  currencyToken: Token;
  bptToken: Token;
  securityType: BytesLike;
  cficode: BytesLike;
  minOrderSize : BigNumberish;
  margin : BigNumberish;
  collateral: BigNumberish;
  tradeFeePercentage?: BigNumberish;
  vault: Vault;
  owner?: SignerWithAddress;

  static async create(params: RawMarginPoolDeployment, mockedVault: boolean): Promise<MarginPool> {
    return MarginPoolDeployer.deploy(params, mockedVault);
  }

  static async deployedAt(address: Account): Promise<MarginPool> {
    const instance = await deployedAt('pool-margin-trading/MarginTradingPool', TypesConverter.toAddress(address));
    const [poolId, vault, securityToken, currencyToken, securityType, cficode, minOrderSize, margin, collateral, tradeFeePercentage, owner] = await Promise.all([
      instance.getPoolId(),
      instance.getVault(),
      instance.getSecurity(),
      instance.getCurrency(),
      instance.getSecurityType(),
      instance.getCfiCode(),
      instance.getMinOrderSize(),
      instance.getMargin(),
      instance.getCollateral(),
      instance.getTradeFeePercentage(),
      instance.getOwner()
    ]);
    return new MarginPool(
      instance,
      poolId,
      vault,
      await Token.deployedAt(securityToken),
      await Token.deployedAt(currencyToken),
      await Token.deployedAt(instance.address),
      securityType,
      cficode,
      minOrderSize,
      margin,
      collateral,
      tradeFeePercentage,
      owner
    );
  }

  constructor(
    instance: Contract,
    poolId: string,
    vault: Vault,
    securityToken: Token,
    currencyToken: Token,
    bptToken: Token,
    securityType: BytesLike,
    cfiCode: BytesLike,
    minOrderSize: BigNumberish,
    margin: BigNumberish,
    collateral: BigNumberish,
    tradeFeePercentage: BigNumberish,
    owner?: SignerWithAddress
  ) {
    super(instance, poolId, vault, new TokenList([securityToken, currencyToken, bptToken]).sort(), tradeFeePercentage, owner);
    this.instance = instance;
    this.poolId = poolId;
    this.vault = vault;
    this.securityToken = securityToken;
    this.currencyToken = currencyToken;
    this.bptToken = bptToken;
    this.securityType = securityType;
    this.cficode = cfiCode;
    this.minOrderSize = minOrderSize;
    this.margin = margin;
    this.collateral = collateral;
    this.tradeFeePercentage = tradeFeePercentage;
    this.owner = owner;
  }

  get address(): string {
    return this.instance.address;
  }

  get getMarginTokens(): TokenList {
    return new TokenList([this.securityToken, this.currencyToken, this.bptToken]).sort();
  }

  get securityIndex(): number {
    return this.getTokenIndex(this.securityToken);
  }

  get currencyIndex(): number {
    return this.getTokenIndex(this.currencyToken);
  }

  get bptIndex(): number {
    return this.getTokenIndex(this.bptToken);
  }

  get tokenIndexes(): { securityIndex: number; currencyIndex: number, bptIndex: number } {
    const securityIndex = this.securityIndex;
    const currencyIndex = this.currencyIndex;
    const bptIndex = this.bptIndex;
    return { securityIndex, currencyIndex, bptIndex };
  }

  getTokenIndex(token: Token): number {
    const addresses = this.tokens.addresses;
    return addresses[0] == token.address ? 0 : addresses[1] == token.address ? 1 : 2;
  }

  async name(): Promise<string> {
    return this.instance.name();
  }

  async symbol(): Promise<string> {
    return this.instance.symbol();
  }

  async totalSupply(): Promise<BigNumber> {
    return this.instance.totalSupply();
  }

  async getMinOrderSize(): Promise<BigNumber> {
    return this.instance.getMinOrderSize();
  }

  async getMargin(): Promise<BigNumber> {
    return this.instance.getMargin();
  }

  async getCollateral(): Promise<BigNumber> {
    return this.instance.getCollateral();
  }

  async getSecurityType(): Promise<BytesLike> {
    return this.instance.getSecurityType();
  }

  async getCfiCode(): Promise<BytesLike>{
    return this.instance.getCfiCode();
  }

  async balanceOf(account: Account): Promise<BigNumber> {
    return this.instance.balanceOf(TypesConverter.toAddress(account));
  }

  async getVault(): Promise<string> {
    return this.instance.getVault();
  }

  async getRegisteredInfo(): Promise<{ address: string; specialization: BigNumber }> {
    return this.vault.getPool(this.poolId);
  }

  async getPoolId(): Promise<string> {
    return this.instance.getPoolId();
  }

  async getFee(): Promise<BigNumber> {
    return this.instance.getFee();
  }

  async getScalingFactors(): Promise<BigNumber[]> {
    return this.instance.getScalingFactors();
  }

  async getScalingFactor(token: Token): Promise<BigNumber> {
    return this.instance.getScalingFactor(token.address);
  }

  async getTokens(): Promise<{ tokens: string[]; balances: BigNumber[]; lastChangeBlock: BigNumber }> {
    return this.vault.getPoolTokens(this.poolId);
  }

  async getBalances(): Promise<BigNumber[]> {
    const { balances } = await this.getTokens();
    return balances;
  }

  async getTokenInfo(
    token: Token
  ): Promise<{ cash: BigNumber; managed: BigNumber; lastChangeBlock: BigNumber; assetManager: string }> {
    return this.vault.getPoolTokenInfo(this.poolId, token);
  }

  async setTradeFeePercentage(tradeFeePercentage: BigNumber, txParams: TxParams = {}): Promise<ContractTransaction> {
    const sender = txParams.from || this.owner;
    const pool = sender ? this.instance.connect(sender) : this.instance;
    return pool.setTradeFeePercentage(tradeFeePercentage);
  }

  async init(params: InitPrimaryPool): Promise<JoinResult> {
    return this.join(this._buildInitParams(params));
  }

  async exitGivenOut(params: ExitGivenOutPrimaryPool): Promise<ExitResult> {
    return this.exit(this._buildExitGivenOutParams(params));
  }

  async swapGivenIn(params: SwapMarginPool): Promise<any> {
    return this.swap(this._buildSwapParams(SwapKind.GivenIn, params), params.eventHash!);
  }

  async swapGivenOut(params: SwapMarginPool): Promise<any> {
    return this.swap(this._buildSwapParams(SwapKind.GivenOut, params), params.eventHash!);
  }

  async placeLimitOrder(params: LimitOrderMarginPool): Promise<any> {
    const sender = params.from || this.owner;
    const pool = sender ? this.instance.connect(sender) : this.instance;
    const tx = await pool.onLimit(
                            params.kind, 
                            this.poolId, 
                            params.amount, 
                            params.data, 
                            params.in, 
                            params.out
                          );
    const receipt = await (await tx).wait();
    console.log("GAS USED",receipt.gasUsed.toString());
  }

  async swap(params: GeneralSwap, eventEncoded: string): Promise<any> {
    const tx = await this.vault.generalSwap(params);
    const receipt = await (await tx).wait();
    console.log("GAS USED",receipt.gasUsed.toString());
    const { amount } = expectEvent.inReceipt(receipt, 'Swap').args;
    return [amount];
  }

  private _buildSwapParams(kind: number, params: SwapMarginPool): GeneralSwap {
    return {
      kind,
      poolAddress: this.address,
      poolId: this.poolId,
      from: params.from,
      to: params.recipient ?? ZERO_ADDRESS,
      tokenIn: params.in < this.tokens.length ? this.tokens.get(params.in)?.address ?? ZERO_ADDRESS : ZERO_ADDRESS,
      tokenOut: params.out < this.tokens.length ? this.tokens.get(params.out)?.address ?? ZERO_ADDRESS : ZERO_ADDRESS,
      lastChangeBlock: params.lastChangeBlock ?? 0,
      data: params.data ?? '0x',
      amount: params.amount,
      balances: params.balances,
      indexIn: params.in,
      indexOut: params.out,
    };
  }

  private _buildInitParams(params: InitPrimaryPool): JoinExitMarginPool {
    const { initialBalances: balances } = params;
    const amountsIn = Array.isArray(balances) ? balances : Array(this.tokens.length).fill(balances);

    return {
      from: params.from,
      recipient: params.recipient,
      protocolFeePercentage: params.protocolFeePercentage,
      data: WeightedPoolEncoder.joinInit(amountsIn),
    };
  }

  private _buildExitGivenOutParams(params: ExitGivenOutPrimaryPool): JoinExitMarginPool {
    const { amountsOut: amounts } = params;
    const amountsOut = Array.isArray(amounts) ? amounts : Array(this.tokens.length).fill(amounts);
    return {
      from: params.from,
      recipient: params.recipient,
      lastChangeBlock: params.lastChangeBlock,
      currentBalances: params.currentBalances,
      protocolFeePercentage: params.protocolFeePercentage,
      data: WeightedPoolEncoder.exitExactBPTInForTokensOut(params.bptAmountIn),
    };
  }

  async pause(): Promise<void> {
    const action = await actionId(this.instance, 'pause');
    const unpauseAction = await actionId(this.instance, 'unpause');
    await this.vault.grantPermissionsGlobally([action, unpauseAction]);
    await this.instance.pause();
  }

  async join(params: JoinExitMarginPool): Promise<JoinResult> {
    const currentBalances = params.currentBalances || (await this.getBalances());
    const to = params.recipient ? TypesConverter.toAddress(params.recipient) : params.from?.address ?? ZERO_ADDRESS;

    const tx = this.vault.joinPool({
      poolAddress: this.address,
      poolId: this.poolId,
      recipient: to,
      currentBalances,
      tokens: this.tokens.addresses,
      lastChangeBlock: params.lastChangeBlock ?? 0,
      protocolFeePercentage: params.protocolFeePercentage ?? 0,
      data: params.data ?? '0x',
      from: params.from,
    });

    const receipt = await (await tx).wait();
    const { deltas, protocolFees } = expectEvent.inReceipt(receipt, 'PoolBalanceChanged').args;
    return { amountsIn: deltas, dueProtocolFeeAmounts: protocolFees, receipt };
  }

  async exit(params: JoinExitMarginPool): Promise<ExitResult> {
    const currentBalances = params.currentBalances || (await this.getBalances());
    const to = params.recipient ? TypesConverter.toAddress(params.recipient) : params.from?.address ?? ZERO_ADDRESS;

    const tx = await this.vault.exitPool({
      poolAddress: this.address,
      poolId: this.poolId,
      recipient: to,
      currentBalances,
      tokens: this.tokens.addresses,
      lastChangeBlock: params.lastChangeBlock ?? 0,
      protocolFeePercentage: params.protocolFeePercentage ?? 0,
      data: params.data ?? '0x',
      from: params.from,
    });

    const receipt = await (await tx).wait();
    const { deltas, protocolFees } = expectEvent.inReceipt(receipt, 'PoolBalanceChanged').args;
    return { amountsOut: deltas.map((x: BigNumber) => x.mul(-1)), dueProtocolFeeAmounts: protocolFees, receipt };
  }
}
