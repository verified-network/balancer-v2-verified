import hre from 'hardhat';
import { ethers } from 'ethers';
import { expect } from 'chai';
import { Contract, BigNumber } from 'ethers';
import { WeightedPoolEncoder, SwapKind } from '@balancer-labs/balancer-js';
import * as expectEvent from '@balancer-labs/v2-helpers/src/test/expectEvent';
import { bn, fp } from '@balancer-labs/v2-helpers/src/numbers';
import { expectEqualWithError } from '@balancer-labs/v2-helpers/src/test/relativeError';
import { describeForkTest } from '../../../src/forkTests';
import Task, { TaskMode } from '../../../src/task';
import { getForkedNetwork } from '../../../src/test';
import { getSigner, impersonate, impersonateWhale } from '../../../src/signers';
import { MAX_UINT256 } from '@balancer-labs/v2-helpers/src/constants';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';

describeForkTest('PrimaryPoolFactory', 'mainnet', 8586768, function () {
    let owner: SignerWithAddress, whale: SignerWithAddress;
    let factory: Contract, vault: Contract, authorizer: Contract, usdc: Contract, vcusd: Contract, usdt: Contract;

    let task: Task;

    const USDC = '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48';
    const VCUSD = '0xa6aa25115f23F3ADc4471133bbDC401b613DbF65';
    const USDT = '0xdac17f958d2ee523a2206206994597c13d831ec7';

    const tokens = [USDC, VCUSD];
    const swapFeePercentage = fp(0.01);
    const initialBalanceUSDC = fp(1e6).div(1e12); // 6 digits
    const initialBalanceVCUSD = fp(1e18); //18 digits

    const initialBalances = [, initialBalanceUSDC, initialBalanceVCUSD];

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

        ``

        usdc = await task.instanceAt('IERC20', USDC);
        vcusd = await task.instanceAt('IERC20', VCUSD);
        usdt = await task.instanceAt('IERC20', USDT);

        await usdc.connect(whale).approve(vault.address, MAX_UINT256);
        await vcusd.connect(whale).approve(vault.address, MAX_UINT256);
        await usdt.connect(whale).approve(vault.address, MAX_UINT256);


    });

    describe('create and swap', () => {
        let pool: Contract;
        let poolId: string;

        it('deploy a primary issue pool', async () => {
            try {
                const tx = await factory.create({
                    name: 'Verified Pool Token', symbol: 'VPT', security: usdc.address, currency: vcusd.address, minimumPrice: minimumPrice, minimumOrderSize: minimumOrderSize, maxAmountsIn: maxSecurityOffered, swapFeePercentage: swapFeePercentage, cutOffTime: issueCutoffTime, offeringDocs: offeringDocs, initialBalances: initialBalances,
                });
                console.log(await tx.wait());
                const event = await expectEvent.inReceipt(await tx.wait(), 'PoolCreated');

                const pool = await task.instanceAt('PrimaryIssuePool', event.args.pool);
                expect(await factory.isPoolFromFactory(pool.address)).to.be.true;

                poolId = await pool.getPoolId();
                const [registeredAddress] = await vault.getPool(poolId);
                expect(registeredAddress).to.equal(pool.address);
            } catch (error: any) {
                console.error('Error deploying primary issue pool:', error.message);
                throw error;
            }
        });



        it('Initialize the pool', async () => {
            await usdc.connect(whale).approve(vault.address, MAX_UINT256);
            await usdc.connect(whale).approve(vault.address, MAX_UINT256);



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
            try {
                const amount = fp(500);


                // const balance = await vcusd.balanceOf(owner.address);
                // console.log("Owner's VCUSD balance: ", balance.toString());

                // if (balance.lt(amount)) {
                //     throw new Error('Insufficient VCUSD balance for the swap');
                // }

                // if ((await vcusd.balanceOf(owner.address)).lt(amount)) {
                //     throw new Error('Insufficient VCUSD balance for the swap');
                // }


                await usdc.connect(whale).transfer(owner.address, amount);
                await usdc.connect(owner).approve(vault.address, amount);

                await vault
                    .connect(owner)
                    .swap(
                        { kind: SwapKind.GivenIn, poolId, assetIn: usdc, assetOut: usdc, amount, userData: '0x' },
                        { sender: owner.address, recipient: owner.address, fromInternalBalance: false, toInternalBalance: false },
                        0,
                        MAX_UINT256
                    );

                //  owner's VCUSD balance
                // console.log("Owner's VCUSD balance: ", (await vcusd.balanceOf(owner.address)).toString());

                // Assert pool swap
                const expectedUSDC = amount.div(1e12);
                expectEqualWithError(await usdc.balanceOf(owner.address), 0, 0.0001);
                expectEqualWithError(await usdc.balanceOf(owner.address), expectedUSDC, 0.1);
            } catch (error) {
                console.error('An error occurred:', error);
                throw error; // 
            }
        });

        it('check owner balance', async () => {
            try {
                const ownerAddress = owner.address;

                const provider = new ethers.providers.JsonRpcProvider();
                const ownerBalance = await provider.getBalance(ownerAddress);
                console.log("Owner's ETH balance: ", ownerBalance.toString());
            } catch (error) {
                console.error('An error occurred while checking owner balance:', error);
                throw error;
            }
        });
    });


    // it('should allow swapping tokens with fees distributed to the pool', async () => {
    //     const amount = fp(500);
    //     const feePercentage = fp(0.01); // 1% fee
    //     const initialPoolTokenBalance = await pool.balanceOf(owner.address);

    //     // Transfer tokens to the owner's address
    //     await vcusd.connect(whale).transfer(owner.address, amount);
    //     await vcusd.connect(owner).approve(vault.address, amount);

    //     // Execute a swap with fees
    //     await vault
    //         .connect(owner)
    //         .swap(
    //             { kind: SwapKind.GivenIn, poolId, assetIn: VCUSD, assetOut: USDC, amount, userData: '0x' },
    //             { sender: owner.address, recipient: owner.address, fromInternalBalance: false, toInternalBalance: false },
    //             0,
    //             MAX_UINT256
    //         );

    //     // Calculate the expected fee amount
    //     const expectedFee = amount.mul(feePercentage);

    //     // Check the updated balances
    //     const finalPoolTokenBalance = await pool.balanceOf(owner.address);
    //     const finalUSDCBalance = await usdc.balanceOf(owner.address);

    //     // The pool token balance should have increased by the fee amount
    //     expect(finalPoolTokenBalance).to.equal(initialPoolTokenBalance.add(expectedFee));

    //     // The USDC balance should have decreased by the swapped amount
    //     expectEqualWithError(await vcusd.balanceOf(owner.address), 0, 0.0001);
    //     expectEqualWithError(await usdc.balanceOf(owner.address), expectedFee, 0.1);
    // });



    //     describe('should swapSecurityIn', function () {
    //         it('swap security tokens for currency tokens', async function () {
    //             await TokenSwap(pool, owner, 'Security', 'Currency');
    //         });
    //     });

    //     describe('swapSecurityOut', function () {
    //         it('should swap security tokens out for currency tokens', async function () {
    //             await TokenSwap(pool, owner, 'Currency', 'Security');
    //         });
    //     });

    //     describe('swapCurrencyIn', function () {
    //         it('should swap currency tokens in for security tokens', async function () {
    //             await TokenSwap(pool, owner, 'Currency', 'Security');
    //         });
    //     });

    //     describe('swapCurrencyOut', function () {
    //         it('should swap currency tokens out for security tokens', async function () {
    //             await TokenSwap(pool, owner, 'Security', 'Currency');
    //         });
    //     });

    //     const TokenSwap = async (pool: Contract, owner: SignerWithAddress, fromToken: string, toToken: string) => {
    //         // amount of tokens to swap
    //         const amountTokens = 100;

    //         // Get initial balances of tokens for the owner
    //         const initialFromBalance = await pool.balanceOf(owner.address, fromToken);
    //         const initialToBalance = await pool.balanceOf(owner.address, toToken);

    //         // Approve the contract to spend tokens from the owner's account
    //         await pool.connect(owner).approveTokens(amountTokens, fromToken);

    //         // Execute the swap
    //         const result = await pool.connect(owner).swapTokensIn(amountTokens, fromToken, toToken);

    //         // Get updated balances after the swap
    //         const updatedFromBalance = await pool.balanceOf(owner.address, fromToken);
    //         const updatedToBalance = await pool.balanceOf(owner.address, toToken);

    //         // Assertions to check the result of the swap
    //         expect(updatedFromBalance).to.equal(initialFromBalance.sub(amountTokens)); // Tokens were deducted from the 'from' balance
    //         expect(updatedToBalance).to.be.greaterThan(initialToBalance); // Tokens were received in the 'to' balance

    //         // Assertions to check the result of the swap
    //         expect(updatedFromBalance).to.equal(initialFromBalance.sub(amountTokens)); // Tokens were deducted from the 'from' balance
    //         expect(updatedToBalance).to.be.greaterThan(initialToBalance);
    //     };
});
