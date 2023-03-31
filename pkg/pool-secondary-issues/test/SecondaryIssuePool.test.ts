import { ethers } from 'hardhat';
import { expect } from 'chai';
import { BigNumber, Bytes } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';

import { bn, fp, scaleDown, scaleUp } from '@balancer-labs/v2-helpers/src/numbers';
import { MAX_UINT112, ZERO_BYTES32 } from '@balancer-labs/v2-helpers/src/constants';
import { sharedBeforeEach } from '@balancer-labs/v2-common/sharedBeforeEach';
import { PoolSpecialization, SwapKind } from '@balancer-labs/balancer-js';
import { RawSecondaryPoolDeployment } from '@balancer-labs/v2-helpers/src/models/pools/secondary-issue/types';

import Token from '@balancer-labs/v2-helpers/src/models/tokens/Token';
import TokenList from '@balancer-labs/v2-helpers/src/models/tokens/TokenList';
import SecondaryPool from '@balancer-labs/v2-helpers/src/models/pools/secondary-issue/SecondaryIssuePool';
import { keccak256 } from "@ethersproject/keccak256";
import { toUtf8Bytes } from "@ethersproject/strings";
import Decimal from 'decimal.js';

describe('SecondaryPool', function () {
  let pool: SecondaryPool, tokens: TokenList, securityToken: Token, currencyToken: Token;
  let   trader: SignerWithAddress,
        lp: SignerWithAddress,
        admin: SignerWithAddress,
        owner: SignerWithAddress,
        other: SignerWithAddress;
  let tokenUSDC: Token;

  const usdcAmount =(amount: Number)=>{
    return ethers.utils.parseUnits(amount.toString(), 6);
  }
  const maxCurrencyOffered = fp(5);
  const maxSecurityOffered = fp(5);
  const TOTAL_TOKENS = 3;
  const SCALING_FACTOR = fp(1);
  const _DEFAULT_MINIMUM_BPT = 1e6;
  const POOL_SWAP_FEE_PERCENTAGE = fp(0.01);

  const abiCoder = new ethers.utils.AbiCoder();

  const EXPECTED_RELATIVE_ERROR = 1e-14;

  before('setup', async () => {
    [, lp, trader, admin, owner, other] = await ethers.getSigners();
  });
  
  sharedBeforeEach('deploy tokens', async () => {
    tokenUSDC = await Token.create({name: "USD coin", symbol: 'USDC', decimals: 6 });
    tokens = await TokenList.create(['DAI', 'CDAI'], {sorted: true});
    await tokens.mint({ to: [owner, lp, trader], amount: fp(500) });
    await tokenUSDC.mint(owner,usdcAmount(500));
    await tokenUSDC.mint(lp,usdcAmount(500));
    await tokenUSDC.mint(trader,usdcAmount(500));

    securityToken = tokens.DAI;
    currencyToken = tokenUSDC;
  });
   
  async function deployPool(params: RawSecondaryPoolDeployment, mockedVault = true): Promise<any> {
    params = Object.assign({}, { swapFeePercentage: POOL_SWAP_FEE_PERCENTAGE, owner, admin }, params);
    pool = await SecondaryPool.create(params, mockedVault);
    return pool;
  }
  const mulDown = (a: BigNumber, b: BigNumber)=>{
    return scaleDown(a.mul(b), SCALING_FACTOR);
  }

  const divDown = (a: BigNumber, b: BigNumber)=>{
    const aInflated = scaleUp(a, SCALING_FACTOR);
    return aInflated.div(b);
  }
  
  describe('creation', () => {
    context('when the creation succeeds', () => {

      sharedBeforeEach('deploy pool', async () => {
        await deployPool({ securityToken, currencyToken }, false);
      });

      it('sets the vault', async () => {
        expect(await pool.getVault()).to.equal(pool.vault.address);
      });

      it('uses general specialization', async () => {
        const { address, specialization } = await pool.getRegisteredInfo();
        expect(address).to.equal(pool.address);
        expect(specialization).to.equal(PoolSpecialization.GeneralPool);
      });

      it('registers tokens in the vault', async () => {
        const { tokens, balances } = await pool.getTokens();
        expect(tokens).to.have.members(pool.tokens.addresses);
        //expect(balances).to.be.zeros;
      });

      it('sets the asset managers', async () => {
        const tokens = [securityToken, currencyToken];
        await tokens.map(async (token) => {
          const { assetManager } = await pool.getTokenInfo(token);
          //expect(assetManager).to.be.zeroAddress;
        });
      });

      it('sets swap fee', async () => {
        expect(await pool.getSwapFeePercentage()).to.equal(POOL_SWAP_FEE_PERCENTAGE);
      });

      it('sets the name', async () => {
        expect(await pool.name()).to.equal('Verified Liquidity Token');
      });

      it('sets the symbol', async () => {
        expect(await pool.symbol()).to.equal('VITTA');
      });

      it('sets the decimals', async () => {
        expect(await pool.decimals()).to.equal(18);
      });

    });

    context('when the creation fails', () => {
      it('reverts if there are repeated tokens', async () => {
        await expect(deployPool({ securityToken, currencyToken: securityToken }, false)).to.be.revertedWith('UNSORTED_ARRAY');
      });

    });
  });

  describe('initialization', () => {
    let maxAmountsIn: BigNumber[];
    let previousBalances: BigNumber[];

    sharedBeforeEach('deploy pool', async () => {
      await deployPool({securityToken, currencyToken }, false);
      await tokens.approve({ from: owner, to: pool.vault.address, amount: fp(500) });
      await tokenUSDC.approve(pool.vault.address,  usdcAmount(500), {from: owner});

      previousBalances = await pool.getBalances();

      maxAmountsIn = new Array(tokens.length);
      maxAmountsIn[pool.securityIndex] = maxSecurityOffered; 
      maxAmountsIn[pool.currencyIndex] = usdcAmount(5);
      maxAmountsIn[pool.bptIndex] = MAX_UINT112.sub(_DEFAULT_MINIMUM_BPT);
      await pool.init({ from: owner, recipient: owner.address, initialBalances: maxAmountsIn });
    });

    it('adds bpt to the owner', async () => {
      const currentBalances = await pool.getBalances();
      expect(currentBalances[pool.bptIndex]).to.be.equal(MAX_UINT112.sub(_DEFAULT_MINIMUM_BPT));
      expect(currentBalances[pool.securityIndex]).to.be.equal(maxSecurityOffered);
      expect(currentBalances[pool.currencyIndex]).to.be.equal(usdcAmount(5));

      expect(await pool.totalSupply()).to.be.equal(MAX_UINT112);
    });

    it('cannot be initialized twice', async () => {
      await expect(
        pool.init({ 
          from: owner, 
          recipient: owner.address, 
          initialBalances: maxAmountsIn 
        })).to.be.revertedWith('UNHANDLED_BY_SECONDARY_POOL');
    }); 
  });

  describe('swaps', () => {
    let currentBalances: BigNumber[];
    let params: {};
    let secondary_pool: any;
    let ob: any;

    sharedBeforeEach('deploy and initialize pool', async () => {

      secondary_pool = await deployPool({ securityToken, currencyToken }, true);

      await setBalances(pool, { securityBalance: fp(5000), currencyBalance: usdcAmount(5000), bptBalance: MAX_UINT112.sub(_DEFAULT_MINIMUM_BPT) });
      
      const poolId = await pool.getPoolId();
      currentBalances = (await pool.vault.getPoolTokens(poolId)).balances;
      ob = await pool.orderbook(); 
      params = {
        fee: POOL_SWAP_FEE_PERCENTAGE,
      };
    });

    const setBalances = async (
      pool: SecondaryPool,
      balances: { securityBalance?: BigNumber; currencyBalance?: BigNumber; bptBalance?: BigNumber }
    ) => {

      const updateBalances = Array.from({ length: TOTAL_TOKENS }, (_, i) =>
        i == pool.securityIndex
          ? balances.securityBalance ?? bn(0)
          : i == pool.currencyIndex
          ? balances.currencyBalance ?? bn(0)
          : i == pool.bptIndex
          ? balances.bptBalance ?? bn(0)
          : bn(0)
      );
      const poolId = await pool.getPoolId();
      await pool.vault.updateBalances(poolId, updateBalances);
    };

  const getAmount = (orderDetails: any, tradeInfo: any) => {
    return orderDetails.tokenIn == securityToken.address ? tradeInfo.securityTraded : tradeInfo.currencyTraded;
  }

  context('Placing Market Order', () => {
    let sell_qty: BigNumber;
    let buy_qty: BigNumber;
    let sell_price: BigNumber;
    let buy_price: BigNumber;

    sharedBeforeEach('initialize values ', async () => {
      sell_qty = fp(20); // sell qty
      buy_qty = fp(500); // buy qty
      buy_price = fp(40); // Buying price
      sell_price=fp(55);
    });

    it('Sell Limit SWAP In Security Order > Buy Market SWAP OUT Security Order', async () => {
      sell_qty = fp(40);
      buy_qty = fp(10);
      const counterPartyAmountExpected = usdcAmount(10*20);
      const partyAmountExpected = usdcAmount(10*20); //buyQty*sellPrice

      const sell_order = await pool.swapGivenIn({
        in: pool.securityIndex,
        out: pool.bptIndex,
        amount: sell_qty,
        from: lp,
        balances: currentBalances,
        data : abiCoder.encode(["bytes32", "uint"], [ethers.utils.formatBytes32String('Limit'), sell_price]),
      })
      expect(sell_order[0].toString()).to.be.equals(sell_qty.toString());

      const buy_order = await pool.swapGivenIn({
        in: pool.currencyIndex,
        out: pool.bptIndex,
        amount: usdcAmount(200),
        from: trader,
        balances: currentBalances,
        data: abiCoder.encode([], []), // MarketOrder Buy@market price
      });
    });
  });

  context('Placing Limit Order', () => {
    let sell_qty: BigNumber;
    let buy_qty: BigNumber;
    let sell_price: BigNumber;

    sharedBeforeEach('initialize values ', async () => {
      sell_qty = fp(20); //qty
      buy_qty = fp(500); //qty
      sell_price = fp(20); // Selling price
    });

    it('Sell Limit SWAP In Security Order > Buy Limit SWAP Out Security Order', async () => {
      sell_qty = fp(400);
      const counterPartyAmountExpected = usdcAmount(10*20); //cash amount
      const partyAmountExpected = fp(10); //security

      const sell_order = await pool.swapGivenIn({
        in: pool.securityIndex,
        out: pool.bptIndex,
        amount: sell_qty,
        from: lp,
        balances: currentBalances,
        data : abiCoder.encode(["bytes32", "uint"], [ethers.utils.formatBytes32String('Limit'), sell_price]),
      })
      // expect(sell_order[0].toString()).to.be.equals(sell_qty.toString());

      const buy_order =  await pool.swapGivenIn({
        in: pool.currencyIndex,
        out: pool.bptIndex,
        amount: usdcAmount(200),
        from: trader,
        balances: currentBalances,
        data : abiCoder.encode(["bytes32", "uint"], [ethers.utils.formatBytes32String('Limit'), fp(30)]),
      });
      // expect(buy_order[0].toString()).to.be.equals(fp(200).toString()); 

      // const counterPartyTrades = await ob.getTrades({from: lp});
      // const partyTrades = await ob.getTrades({from: trader});

      // const cpTradesInfo = await ob.getTrade({from: lp, tradeId: Number(counterPartyTrades[0]) });
      // const pTradesInfo = await ob.getTrade({from: trader, tradeId: Number(partyTrades[0]) });
  
      // await callSwapEvent(cpTradesInfo,pTradesInfo,counterPartyAmountExpected,partyAmountExpected);
    });   
  });

});

  describe('joins and exits', () => {
    let maxAmountsIn : BigNumber[];
    sharedBeforeEach('deploy pool', async () => {
      await deployPool({ securityToken, currencyToken }, false);

      await tokens.approve({ from: owner, to: pool.vault.address, amount: fp(500) });
      await tokenUSDC.approve(pool.vault.address,  usdcAmount(500), {from: owner});

        maxAmountsIn = new Array(tokens.length);
        maxAmountsIn[pool.securityIndex] = maxSecurityOffered; 
        maxAmountsIn[pool.currencyIndex] = usdcAmount(5);
        maxAmountsIn[pool.bptIndex] = fp(0);

        await pool.init({ from: owner, recipient: owner.address, initialBalances: maxAmountsIn });
    });

    it('regular joins should revert', async () => {
      const { tokens: allTokens } = await pool.getTokens();

      const tx = pool.vault.joinPool({
        poolAddress: pool.address,
        poolId: await pool.getPoolId(),
        recipient: lp.address,
        tokens: allTokens,
        data: '0x',
      });

      await expect(tx).to.be.revertedWith('UNHANDLED_BY_SECONDARY_POOL');
    });
    
    context('when paused for emergency proportional exit', () => {
      it('gives back tokens', async () => {
          const previousBalances = await pool.getBalances();
          const prevSecurityBalance = await securityToken.balanceOf(owner);
          const prevCurrencyBalance = await currencyToken.balanceOf(owner);

          const bptAmountIn = 0;
          await pool.exitGivenOut({
            from: owner, 
            recipient: owner.address, 
            amountsOut: previousBalances, 
            bptAmountIn: bptAmountIn
          });
     
          const afterExitOwnerBalance = await pool.balanceOf(owner);
          const currentBalances = await pool.getBalances();
          const afterExitSecurityBalance = await securityToken.balanceOf(owner);
          const afterExitCurrencyBalance = await currencyToken.balanceOf(owner);

          expect(currentBalances[pool.bptIndex]).to.be.equal(0);
          expect(currentBalances[pool.securityIndex]).to.be.equal(0);
          expect(currentBalances[pool.currencyIndex]).to.be.equal(0);

          expect(afterExitSecurityBalance).to.be.equal(prevSecurityBalance.add(previousBalances[pool.securityIndex]));
          expect(afterExitCurrencyBalance).to.be.equal(prevCurrencyBalance.add(previousBalances[pool.currencyIndex]));

          expect(afterExitOwnerBalance).to.be.equal(MAX_UINT112.sub(_DEFAULT_MINIMUM_BPT));
        }); 
    });

  });
});