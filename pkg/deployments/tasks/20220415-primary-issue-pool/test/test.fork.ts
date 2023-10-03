import hre from 'hardhat';
import { expect } from 'chai';
import { Contract, BigNumber } from 'ethers';
import { WeightedPoolEncoder, SwapKind } from '@balancer-labs/balancer-js';
import * as expectEvent from '@balancer-labs/v2-helpers/src/test/expectEvent';
import { bn, fp } from '@balancer-labs/v2-helpers/src/numbers';
import { expectEqualWithError } from '@balancer-labs/v2-helpers/src/test/relativeError';
import { describeForkTest } from '../../../src/forkTests';
// import PrimaryPool from '@balancer-labs/v2-helpers/src/models/pools/primary-issue/PrimaryIssuePool';
import Task, { TaskMode } from '../../../src/task';
import { getForkedNetwork } from '../../../src/test';
import { getSigner, impersonate, impersonateWhale } from '../../../src/signers';
import { MaxUint256 } from '@ethersproject/constants';
// import { MaxUint256 } from '@balancer-labs/v2-helpers/src/constants';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';

describeForkTest('PrimaryPoolFactory', 'mainnet', 8586768, function () {
    let owner: SignerWithAddress, whale: SignerWithAddress;
    let factory: Contract, vault: Contract, authorizer: Contract, usdc: Contract, vcusd: Contract, usdt: Contract, pool: Contract;
    // let pool: PrimaryPool;
    let task: Task;

    const VCUSD = '0xa6aa25115f23F3ADc4471133bbDC401b613DbF65';
    const USDC = '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48';
    const USDT = '0xdac17f958d2ee523a2206206994597c13d831ec7';

    const tokens = [USDC, VCUSD];
    const swapFeePercentage = fp(0.01);
    const initialBalanceVCUSD = fp(1e18); //18 digits
    const initialBalanceUSDC = fp(1e6).div(1e12); // 6 digits
    const initialBalances = [initialBalanceVCUSD, initialBalanceUSDC];

    const minimumPrice = fp(8);
    const minimumOrderSize = fp(1);
    const maxSecurityOffered = fp(5);
    const issueCutoffTime = BigNumber.from("1672444800");
    const offeringDocs = "0xB45165ED3CD437B9FFAD02A2AAD22A4DDC69162470E2622982889CE5826F6E3D";

    before('run task', async () => {
        task = new Task('20220415-primary-issue-pool', TaskMode.TEST, getForkedNetwork(hre));
        await task.run({ force: true });
        factory = await task.deployedInstance('PrimaryIssuePoolFactory');
    });

    before('load signers', async () => {
        owner = await getSigner();
        whale = await impersonateWhale(fp(100));
    });

    before('setup contracts', async () => {
        vault = await new Task('20210418-vault', TaskMode.READ_ONLY, getForkedNetwork(hre)).deployedInstance('Vault');
        authorizer = await new Task('20210418-authorizer', TaskMode.READ_ONLY, getForkedNetwork(hre)).deployedInstance(
            'Authorizer'
        );

        vcusd = await task.instanceAt('IERC20', VCUSD);
        usdc = await task.instanceAt('IERC20', USDC);
        usdt = await task.instanceAt('IERC20', USDT);
    });

    describe('create and swap', () => {
        let pool: Contract;
        let poolId: string;

        it('deploy a primary issue pool', async () => {
            const tx = await factory.create({ name: 'Verified Pool Token', symbol: 'VPT', security: usdc.address, currency: vcusd.address, minimumPrice: minimumPrice, minimumOrderSize: minimumOrderSize, maxAmountsIn: maxSecurityOffered, swapFeePercentage: swapFeePercentage, cutOffTime: issueCutoffTime, offeringDocs: offeringDocs });
            const event = await expectEvent.inReceipt(await tx.wait(), 'PoolCreated');

            pool = await task.instanceAt('PrimaryIssuePool', event.args.pool);
            expect(await factory.isPoolFromFactory(pool.address)).to.be.true;

            poolId = await pool.getPoolId();
            const [registeredAddress] = await vault.getPool(poolId);
            expect(registeredAddress).to.equal(pool.address);
        });

        it('initialize the pool', async () => {
            await vcusd.connect(whale).approve(vault.address, MaxUint256);
            await usdc.connect(whale).approve(vault.address, MaxUint256);

            const userData = WeightedPoolEncoder.joinInit(initialBalances);
            await vault.connect(whale).joinPool(poolId, whale.address, owner.address, {
                assets: tokens,
                maxAmountsIn: initialBalances,
                fromInternalBalance: false,
                userData,
            });

            const { balances } = await vault.getPoolTokens(poolId);
            expect(balances).to.deep.equal(initialBalances);
        });

        it('swap in the pool', async () => {
            const amount = fp(500);
            await vcusd.connect(whale).transfer(owner.address, amount);
            await vcusd.connect(owner).approve(vault.address, amount);

            await vault
                .connect(owner)
                .swap(
                    { kind: SwapKind.GivenIn, poolId, assetIn: VCUSD, assetOut: USDC, amount, userData: '0x' },
                    { sender: owner.address, recipient: owner.address, fromInternalBalance: false, toInternalBalance: false },
                    0,
                    MaxUint256
                );

            // Assert pool swap
            const expectedUSDC = amount.div(1e12);
            expectEqualWithError(await vcusd.balanceOf(owner.address), 0, 0.0001);
            expectEqualWithError(await usdc.balanceOf(owner.address), expectedUSDC, 0.1);
        });
    });

    // swaping securityIn token
    describe('swapSecurityIn', function () {
        it('swap security tokens for currency tokens', async function () {
            await TokenSwap(pool, owner, 'Security', 'Currency');
        });
    });

    // swaping securityOut token
    describe('_swapSecurityOut', function () {
        it('should swap security tokens out for currency tokens', async function () {
            await TokenSwap(pool, owner, 'Currency', 'Security');
        });
    });

    // swapping swapCurrencyIn token
    describe('_swapCurrencyIn', function () {
        it('should swap currency tokens in for security tokens', async function () {
            await TokenSwap(pool, owner, 'Currency', 'Security');
        });
    });

    // swapping swapCurrencyOut token
    describe('_swapCurrencyOut', function () {
        it('should swap currency tokens out for security tokens', async function () {
            await TokenSwap(pool, owner, 'Security', 'Currency');
        });
    });

    const TokenSwap = async (pool: Contract, owner: SignerWithAddress, fromToken: string, toToken: string) => {
        // amount of tokens to swap
        const amountTokens = 100;

        // Get initial balances of tokens for the owner
        const initialFromBalance = await pool.balanceOfTokens(owner.address, fromToken);
        const initialToBalance = await pool.balanceOfTokens(owner.address, toToken);

        // Approve the contract to spend tokens from the owner's account
        await pool.connect(owner).approveTokens(amountTokens, fromToken);

        // Execute the swap
        const result = await pool.connect(owner).swapTokensIn(amountTokens, fromToken, toToken);

        // Get updated balances after the swap
        const updatedFromBalance = await pool.balanceOfTokens(owner.address, fromToken);
        const updatedToBalance = await pool.balanceOfTokens(owner.address, toToken);

        //  assertions to check the result of the swap
        expect(updatedFromBalance).to.equal(initialFromBalance.sub(amountTokens)); // Tokens were deducted from the 'from' balance
        expect(updatedToBalance).to.be.greaterThan(initialToBalance); // Tokens were received in the 'to' balance

        //  assertions to check the result of the swap
        expect(updatedFromBalance).to.equal(initialFromBalance.sub(amountTokens)); // Tokens were deducted from the 'from' balance
        expect(updatedToBalance).to.be.greaterThan(initialToBalance);
    };
});
