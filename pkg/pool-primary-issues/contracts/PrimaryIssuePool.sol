// Implementation of pool for new issues of security tokens that allows price discovery
// (c) Kallol Borah, 2022
//"SPDX-License-Identifier: BUSL1.1"

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "@balancer-labs/v2-pool-utils/contracts/BasePool.sol";

import "@balancer-labs/v2-interfaces/contracts/pool-primary/IPrimaryPool.sol";

import "@balancer-labs/v2-solidity-utils/contracts/math/Math.sol";
import "@balancer-labs/v2-solidity-utils/contracts/math/FixedPoint.sol";
import "@balancer-labs/v2-solidity-utils/contracts/helpers/ERC20Helpers.sol";
import "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/SafeERC20.sol";

import "@balancer-labs/v2-interfaces/contracts/vault/IGeneralPool.sol";
import "@balancer-labs/v2-interfaces/contracts/pool-primary/PrimaryPoolUserData.sol";
import "@balancer-labs/v2-interfaces/contracts/solidity-utils/helpers/BalancerErrors.sol";

import "./utils/BokkyPooBahsDateTimeLibrary.sol";

import "./interfaces/IMarketMaker.sol";
import "./interfaces/IPrimaryIssuePoolFactory.sol";

contract PrimaryIssuePool is IPrimaryPool, BasePool, IGeneralPool {

    using PrimaryPoolUserData for bytes;
    using BokkyPooBahsDateTimeLibrary for uint256;
    using FixedPoint for uint256;
    using SafeERC20 for IERC20;

    IERC20 private immutable _security;
    IERC20 private immutable _currency;

    uint256 private constant _TOTAL_TOKENS = 3; //Security token, Currency token (ie, paired token), Balancer pool token

    uint256 private constant _INITIAL_BPT_SUPPLY = 2**(112) - 1; //setting to max BPT allowed in Vault

    uint256 private immutable _scalingFactorSecurity;
    uint256 private immutable _scalingFactorCurrency;

    uint256 private immutable _minPrice;
    uint256 private immutable _minOrderSize;
    uint256 private immutable _swapFee;

    uint256 private immutable _MAX_TOKEN_BALANCE;
    uint256 private immutable _cutoffTime;
    uint256 private immutable _startTime;
    string private _offeringDocs;

    uint256 private immutable _securityIndex;
    uint256 private immutable _currencyIndex;
    uint256 private immutable _bptIndex;

    address private immutable _balancerManager;

    struct Params {
        uint256 fee;
        uint256 minPrice;
        uint256 minOrderSize;
    }

    event OpenIssue(address indexed security, uint256 minimumOrderSize, uint256 minimumPrice, address currency, uint256 securityOffered, uint256 cutoffTime, string offeringDocs, address issueManager);
    event Subscription(address indexed assetIn, address assetOut, uint256 subscription, address investor, uint256 price, uint256 executionDate);

    constructor(
        IVault vault,
        IPrimaryIssuePoolFactory.FactoryPoolParams memory factoryPoolParams,
        uint256 pauseWindowDuration,
        uint256 bufferPeriodDuration,
        address owner
    )
        BasePool(
            vault,
            IVault.PoolSpecialization.GENERAL,
            factoryPoolParams.name,
            factoryPoolParams.symbol,
            _sortTokens(IERC20(factoryPoolParams.security), IERC20(factoryPoolParams.currency), this),
            new address[](_TOTAL_TOKENS),
            factoryPoolParams.swapFeePercentage,
            pauseWindowDuration,
            bufferPeriodDuration,
            owner
        )
    {
        // set tokens
        _security = IERC20(factoryPoolParams.security);
        _currency = IERC20(factoryPoolParams.currency);

        // Set token indexes
        (uint256 securityIndex, uint256 currencyIndex, uint256 bptIndex) = _getSortedTokenIndexes(
            IERC20(factoryPoolParams.security),
            IERC20(factoryPoolParams.currency),
            this
        );
        _securityIndex = securityIndex;
        _currencyIndex = currencyIndex;
        _bptIndex = bptIndex;

        // set scaling factors
        _scalingFactorSecurity = _computeScalingFactor(IERC20(factoryPoolParams.security));
        _scalingFactorCurrency = _computeScalingFactor(IERC20(factoryPoolParams.currency));

        // set price bounds
        _minPrice = factoryPoolParams.minimumPrice;
        _minOrderSize = factoryPoolParams.minimumOrderSize;

        //swap fee
        _swapFee = factoryPoolParams.swapFeePercentage;

        // set max total balance of securities
        _MAX_TOKEN_BALANCE = factoryPoolParams.maxAmountsIn;

        // set issue time bounds
        _cutoffTime = factoryPoolParams.cutOffTime;
        _startTime = block.timestamp;

        //ipfs address of offering docs
        _offeringDocs = factoryPoolParams.offeringDocs;

        //set owner
        _balancerManager = owner;     

        emit OpenIssue(factoryPoolParams.security, 
                        factoryPoolParams.minimumOrderSize, 
                        factoryPoolParams.minimumPrice,
                        factoryPoolParams.currency, 
                        factoryPoolParams.maxAmountsIn, 
                        factoryPoolParams.cutOffTime, 
                        factoryPoolParams.offeringDocs,
                        owner);
    }

    function getFee() external view returns(uint256){
        return _swapFee;
    }

    function getSecurity() external view override returns (IERC20) {
        return _security;
    }

    function getCurrency() external view override returns (IERC20) {
        return _currency;
    }

    function getMinimumPrice() external view override returns(uint256) {
        return _minPrice;
    }

    function getMinimumOrderSize() external view override returns(uint256) {
        return _minOrderSize;
    }

    function getSecurityOffered() external view override returns(uint256) {
        return _MAX_TOKEN_BALANCE;
    }

    function getIssueCutoffTime() external view override returns(uint256) {
        return _cutoffTime;
    }

    function getSecurityIndex() external view override returns (uint256) {
        return _securityIndex;
    }

    function getCurrencyIndex() external view override returns (uint256) {
        return _currencyIndex;
    }

    function getBptIndex() public view override returns (uint256) {
        return _bptIndex;
    }

    function getOfferingDocuments() public view returns(string memory){
        return _offeringDocs;
    }

    function onSwap(
        SwapRequest memory request,
        uint256[] memory balances,
        uint256 indexIn,
        uint256 indexOut
    ) public override onlyVault(request.poolId) whenNotPaused returns (uint256) {
        // ensure that swap request is not beyond issue's cut off time
        require(BokkyPooBahsDateTimeLibrary.addSeconds(_startTime, _cutoffTime) >= block.timestamp, "TimeLimit Over");
        
        uint256[] memory scalingFactors = _scalingFactors();
         _upscaleArray(balances, scalingFactors);
        Params memory params = Params({ fee: getSwapFeePercentage(), minPrice: _minPrice, minOrderSize: _minOrderSize/*, iIn: indexIn, iOut: indexOut*/ });

        if (request.kind == IVault.SwapKind.GIVEN_IN) {
            request.amount = _upscale(request.amount, scalingFactors[indexIn]);
            uint256 amountOut = _onSwapIn(request, balances, params);
            return _downscaleDown(amountOut, scalingFactors[indexOut]);
        } else if (request.kind == IVault.SwapKind.GIVEN_OUT) {
            request.amount = _upscale(request.amount, scalingFactors[indexOut]);
            uint256 amountIn = _onSwapOut(request, balances, params);
            return _downscaleUp(amountIn, scalingFactors[indexIn]);
        }
    }

    function _onSwapIn(
        SwapRequest memory request,
        uint256[] memory balances,
        Params memory params
    ) internal returns (uint256) {
        
        if (request.tokenIn == _security) {
            return _swapSecurityIn(request, balances, params);
        } else if (request.tokenIn == _currency) {
            return _swapCurrencyIn(request, balances, params);
        } else {
            _revert(Errors.INVALID_TOKEN);
        }
    }

    function _swapSecurityIn(
        SwapRequest memory request,
        uint256[] memory balances,
        Params memory params
    ) internal returns (uint256) {
        _require(request.tokenOut == _currency, Errors.INVALID_TOKEN);
        require(balances[_securityIndex]>0, "Issue sold out");
        require(request.amount >= params.minOrderSize, "Order size violation");
        
        // returning currency for current price of security paid in,
        // but only if new price of security do not go out of price band
        uint256 postPaidSecurityBalance = Math.add(balances[_securityIndex], request.amount);
        uint256 tokenOutAmt = (postPaidSecurityBalance.divDown(balances[_securityIndex])).mulDown(request.amount.mulDown(params.minPrice));

        require (tokenOutAmt.divDown(request.amount) >= params.minPrice, "Price out of bound");
        require (balances[_currencyIndex] >= tokenOutAmt, "Insufficient currency balance");
        IMarketMaker(_balancerManager).subscribe(getPoolId(), address(_security), address(_currency), tokenOutAmt, request.from, request.amount, false);
        emit Subscription(address(_security), address(_currency), tokenOutAmt, request.from, tokenOutAmt.divDown(request.amount), block.timestamp);
        return tokenOutAmt;        
    }

    function _swapCurrencyIn(
        SwapRequest memory request,
        uint256[] memory balances,
        Params memory params
    ) internal returns (uint256) {
        _require(request.tokenOut == _security, Errors.INVALID_TOKEN);

        // returning security for currency paid in at current price of security,
        // but only if new price of security do not go out of price band
        uint256 postPaidCurrencyBalance = Math.add(balances[_currencyIndex], request.amount);
        uint256 tokenOutAmt = (request.amount.divDown(params.minPrice)).divDown(postPaidCurrencyBalance.divDown(balances[_currencyIndex]));
        
        require(tokenOutAmt >= params.minOrderSize, "Order size violation");
        require(request.amount.divDown(tokenOutAmt) >= params.minPrice, "Price out of bound");
        require(balances[_securityIndex] >= tokenOutAmt, "Insufficient security balance");
        IMarketMaker(_balancerManager).subscribe(getPoolId(), address(_security), address(_currency), request.amount, request.from, tokenOutAmt, true);
        emit Subscription(address(_currency), address(_security), request.amount, request.from, request.amount.divDown(tokenOutAmt), block.timestamp);
        return tokenOutAmt;
    }

    function _onSwapOut(
        SwapRequest memory request,
        uint256[] memory balances,
        Params memory params
    ) internal returns (uint256) {
        //BPT is only held by the pool manager transferred to it during pool initialization, so no BPT swap is supported
        if (request.tokenOut == _security) {
            return _swapSecurityOut(request, balances, params);
        } else if (request.tokenOut == _currency) {
            return _swapCurrencyOut(request, balances, params);
        } else {
            _revert(Errors.INVALID_TOKEN);
        }
    }

    function _swapSecurityOut(
        SwapRequest memory request,
        uint256[] memory balances,
        Params memory params
    ) internal returns (uint256) {
        _require(request.tokenIn == _currency, Errors.INVALID_TOKEN);
        require(request.amount < balances[_securityIndex], "Insufficient balance");
        require(request.amount >= params.minOrderSize, "Order size violation");

        //returning currency to be paid in for paid out security
        uint256 postPaidSecurityBalance = Math.sub(balances[_securityIndex], request.amount);
        uint256 tokenInAmt = (balances[_securityIndex].divDown(postPaidSecurityBalance)).mulDown(request.amount.mulDown(params.minPrice));

        require (tokenInAmt.divDown(request.amount) >= params.minPrice, "Price out of bound");
        IMarketMaker(_balancerManager).subscribe(getPoolId(), address(_security), address(_currency), tokenInAmt, request.from, request.amount, true);
        emit Subscription(address(_currency), address(_security), tokenInAmt, request.from, tokenInAmt.divDown(request.amount), block.timestamp);
        return tokenInAmt;
    }

    function _swapCurrencyOut(
        SwapRequest memory request,
        uint256[] memory balances,
        Params memory params
    ) internal returns (uint256) {
        _require(request.tokenIn == _security, Errors.INVALID_TOKEN);
        require(balances[_securityIndex]>0, "Issue sold out"); // Why this condition ?
        require(request.amount < balances[_currencyIndex], "Insufficient balance");

        //returning security to be paid in for currency paid out
        uint256 postPaidCurrencyBalance = Math.sub(balances[_currencyIndex], request.amount);
        uint256 tokenInAmt = (request.amount.divDown(params.minPrice)).divDown(balances[_currencyIndex].divDown(postPaidCurrencyBalance));

        require(tokenInAmt >= params.minOrderSize, "Order size violation");
        require(request.amount.divDown(tokenInAmt) >= params.minPrice, "Price out of bound");
        IMarketMaker(_balancerManager).subscribe(getPoolId(), address(_security), address(_currency), request.amount, request.from, tokenInAmt, false);
        emit Subscription(address(_security), address(_currency), request.amount, request.from, request.amount.divDown(tokenInAmt), block.timestamp);
        return tokenInAmt;
    }

    function _onInitializePool(
        bytes32,
        address sender,
        address recipient,
        uint256[] memory,
        bytes memory userData
    ) internal view override whenNotPaused returns (uint256, uint256[] memory) {
        //the primary issue pool is initialized by the balancer manager contract
        address balancerManager = _balancerManager;
        _require(sender == balancerManager, Errors.INVALID_INITIALIZATION);
        _require(recipient == payable(balancerManager), Errors.INVALID_INITIALIZATION);
        
        uint256 bptAmountOut = _INITIAL_BPT_SUPPLY;
        uint256[] memory amountsIn = userData.joinKind();
        amountsIn[_currencyIndex] = _upscale(amountsIn[_currencyIndex], _scalingFactorCurrency);
        return (bptAmountOut, amountsIn);
    }
    
    function _onJoinPool(
        bytes32,
        address,
        address,
        uint256[] memory,
        uint256,
        uint256,
        uint256[] memory,
        bytes memory
    ) internal pure override returns (uint256, uint256[] memory) {
        _revert(Errors.UNHANDLED_BY_PRIMARY_POOL);
    }

    function _onExitPool(
        bytes32,
        address,
        address,
        uint256[] memory balances,
        uint256,
        uint256,
        uint256[] memory,
        bytes memory userData
    ) internal view override returns (uint256 bptAmountIn, uint256[] memory amountsOut) {
        PrimaryPoolUserData.ExitKind kind = userData.exitKind();
        if (kind != PrimaryPoolUserData.ExitKind.EXACT_BPT_IN_FOR_TOKENS_OUT) {
            //usually exit pool reverts
            _revert(Errors.UNHANDLED_BY_PRIMARY_POOL);
        } else {
            (bptAmountIn, amountsOut) = _exit(balances, userData);
        }
    }

    function _exit(uint256[] memory balances, bytes memory userData)
        private
        view
        returns (uint256, uint256[] memory)
    {   
        // This proportional exit function is only enabled if the contract is paused, to provide users a way to
        // retrieve their tokens in case of an emergency.
        uint256 bptAmountIn = userData.exactBptInForTokensOut();
        uint256[] memory amountsOut = new uint256[](balances.length);
        for (uint256 i = 0; i < balances.length; i++) {
            // BPT is skipped as those tokens are not the LPs, but rather the preminted and undistributed amount.
            if (i != _bptIndex) {
                amountsOut[i] = balances[i];
            }
        }

        return (bptAmountIn, amountsOut);
    }

    //inherited from Basepool
    function _getMaxTokens() internal pure override returns (uint256) {
        return _TOTAL_TOKENS;
    }

    //also inherited from Basepool, why does the Basepool have two getters that return the same thing ? 
    function _getTotalTokens() internal view virtual override returns (uint256) {
        return _TOTAL_TOKENS;
    }

    function _scalingFactor(IERC20 token) internal view virtual override returns (uint256) {
        if (token == _security){
            return _scalingFactorSecurity;
        }
        else if(token == _currency) {
            return _scalingFactorCurrency;
        } else {
            _revert(Errors.INVALID_TOKEN);
        }
    }

    function _scalingFactors() internal view virtual override returns (uint256[] memory) {
        uint256 numTokens = _getMaxTokens();
        uint256[] memory scalingFactors = new uint256[](numTokens);
        for(uint256 i = 0; i < numTokens; i++) {
            if(i==_securityIndex){
                scalingFactors[i] = _scalingFactorSecurity;
            }
            else if(i==_currencyIndex){
                scalingFactors[i] = _scalingFactorCurrency;
            }
            else if(i==_bptIndex){
                scalingFactors[i] = FixedPoint.ONE;
            }
        }
        return scalingFactors;
    }
}
