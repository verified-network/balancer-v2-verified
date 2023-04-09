// Implementation of pool for margin traded security tokens
// (c) Kallol Borah, 2022
//"SPDX-License-Identifier: BUSL1.1"

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "./interfaces/ITrade.sol";
import "./interfaces/IMarginOrder.sol";
import "./interfaces/IMarginTradingPoolFactory.sol";
import "./utilities/StringUtils.sol";
import "./Orderbook.sol";

import "@balancer-labs/v2-pool-utils/contracts/BasePool.sol";

import "@balancer-labs/v2-solidity-utils/contracts/math/FixedPoint.sol";
import "@balancer-labs/v2-solidity-utils/contracts/helpers/ERC20Helpers.sol";
import "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/SafeERC20.sol";

import "@balancer-labs/v2-interfaces/contracts/vault/IGeneralPool.sol";
import "@balancer-labs/v2-interfaces/contracts/pool-margin/MarginPoolUserData.sol";
import "@balancer-labs/v2-interfaces/contracts/solidity-utils/helpers/BalancerErrors.sol";

contract MarginTradingPool is BasePool, IGeneralPool {
    using MarginPoolUserData for bytes;
    using SafeERC20 for IERC20;
    using FixedPoint for uint256;
    using StringUtils for string;

    Orderbook public _orderbook;
    
    address private immutable _security;
    address private immutable _currency;

    uint256 private constant _TOTAL_TOKENS = 3; //Security token, Currency token (ie, paired token), Balancer pool token

    uint256 private constant _INITIAL_BPT_SUPPLY = 2**(112) - 1;
    uint256 private constant _DEFAULT_MINIMUM_BPT = 1e6;

    uint256 private immutable _scalingFactorSecurity;
    uint256 private immutable _scalingFactorCurrency;

    uint256 private immutable _margin;
    uint256 private immutable _collateral;
    uint256 private immutable _minOrderSize;
    uint256 private immutable _swapFee;

    uint256 private immutable _bptIndex;
    uint256 private immutable _securityIndex;
    uint256 private immutable _currencyIndex;

    address payable immutable private _balancerManager;
    IVault _vault;
    
    event TradeReport(
        address indexed security,
        bytes32 orderRef,
        address party,
        address counterparty,
        bytes32 orderType,
        uint256 price,
        address currency,
        uint256 amount,
        uint256 executionDate
    );

    event Offer(address indexed security, uint256 minOrderSize, address currency, uint256 margin, uint256 collateral, address orderBook, address issueManager);  

    event OrderBook(address creator, address tokenIn, address tokenOut, uint256 amountOffered, uint256 priceOffered, uint256 stoplossPrice, uint256 timestamp, bytes32 orderRef);
    
    constructor(
        IVault vault,
        IMarginTradingPoolFactory.FactoryPoolParams memory factoryPoolParams,
        uint256 pauseWindowDuration,
        uint256 bufferPeriodDuration,
        address owner
    )
        BasePool(
            vault,
            IVault.PoolSpecialization.GENERAL,
            factoryPoolParams.name,
            factoryPoolParams.symbol,
            _sortTokens(IERC20(factoryPoolParams.security), IERC20(factoryPoolParams.currency), IERC20(this)),
            new address[](_TOTAL_TOKENS),
            factoryPoolParams.tradeFeePercentage,
            pauseWindowDuration,
            bufferPeriodDuration,
            owner
        )
    {
        // set tokens
        _security = factoryPoolParams.security;
        _currency = factoryPoolParams.currency;

        _vault = vault;

        // Set token indexes
        (uint256 securityIndex, uint256 currencyIndex, uint256 bptIndex) = _getSortedTokenIndexes(
            IERC20(factoryPoolParams.security),
            IERC20(factoryPoolParams.currency),
            IERC20(this)
        );
        _bptIndex = bptIndex;
        _securityIndex = securityIndex;
        _currencyIndex = currencyIndex;

        // set scaling factors
        _scalingFactorSecurity = _computeScalingFactor(IERC20(factoryPoolParams.security));
        _scalingFactorCurrency = _computeScalingFactor(IERC20(factoryPoolParams.currency));

        _margin = factoryPoolParams.margin;
        _collateral = factoryPoolParams.collateral;
        _minOrderSize = factoryPoolParams.minOrderSize;

        //swap fee
        _swapFee = factoryPoolParams.tradeFeePercentage;

        _balancerManager = payable(owner);

        _orderbook = new Orderbook(payable(owner), factoryPoolParams.security, factoryPoolParams.currency, address(this));

        emit Offer(factoryPoolParams.security, factoryPoolParams.minOrderSize, factoryPoolParams.currency, factoryPoolParams.margin, factoryPoolParams.collateral, address(_orderbook), owner);
    }

    function getSecurity() external view returns (address) {
        return _security;
    }

    function getCurrency() external view returns (address) {
        return _currency;
    }

    function getMinOrderSize() external view returns (uint256) {
        return _minOrderSize;
    }

    function onSwap(
        SwapRequest memory request,
        uint256[] memory balances,
        uint256 indexIn,
        uint256 indexOut
    ) public override onlyVault(request.poolId) whenNotPaused returns (uint256) {
        require (request.kind == IVault.SwapKind.GIVEN_IN || request.kind == IVault.SwapKind.GIVEN_OUT, "Invalid swap");
        require(request.tokenOut == IERC20(_currency) ||
                request.tokenOut == IERC20(_security) ||
                request.tokenOut == IERC20(this) ||
                request.tokenIn == IERC20(_currency) ||
                request.tokenIn == IERC20(_security) ||
                request.tokenIn == IERC20(this), "Invalid swapped tokens");

        uint256[] memory scalingFactors = _scalingFactors();
        _upscaleArray(balances, scalingFactors);
        
        IMarginOrder.Params memory params;
        bytes32 otype;
        uint256 tp;
        bytes32 ref;
        uint256 amount;        

        if (request.kind == IVault.SwapKind.GIVEN_IN) 
            request.amount = _upscale(request.amount, scalingFactors[indexIn]);
        else if (request.kind == IVault.SwapKind.GIVEN_OUT)
            request.amount = _upscale(request.amount, scalingFactors[indexOut]);

        if(request.tokenIn==IERC20(_currency) && request.kind==IVault.SwapKind.GIVEN_IN)
            require(balances[_currencyIndex]>=request.amount, "Insufficient currency balance");
        else if(request.tokenIn==IERC20(_security) && request.kind==IVault.SwapKind.GIVEN_IN)
            require(balances[_securityIndex]>=request.amount, "Insufficient security balance");
        else if(request.tokenIn==IERC20(this) && request.kind==IVault.SwapKind.GIVEN_IN)
            require(balances[_bptIndex]>=request.amount, "Insufficient pool token balance");

        if(request.userData.length!=0){
            (otype, tp) = abi.decode(request.userData, (bytes32, uint256));
            ref = "Limit";    
            if(otype == ""){          
                ITrade.trade memory tradeToReport = _orderbook.getTrade(request.from, tp);
                
                //if the call is to claim margin or collateral, trade report will be empty
                if(tradeToReport.partyAddress==address(0x0) && request.tokenOut==IERC20(_currency) 
                    && request.tokenIn==IERC20(this) && request.kind==IVault.SwapKind.GIVEN_IN){
                    return _downscaleDown(request.amount, scalingFactors[indexOut]);        
                }
                else{
                    //else, the call is to claim currency or traded security amount  
                    ref = _orderbook.getOrder(tradeToReport.partyAddress == request.from 
                                                ? tradeToReport.partyRef : tradeToReport.counterpartyRef)
                                                .tokenIn==_security ? bytes32("security") : bytes32("currency");                
                    
                    if(request.tokenOut==IERC20(_security) && request.kind==IVault.SwapKind.GIVEN_IN){
                        amount = tradeToReport.securityTraded;
                        require(tradeToReport.currencyTraded==request.amount, "Insufficient pool tokens swapped in for security");
                    }
                    else if(request.tokenOut==IERC20(_currency) && request.kind==IVault.SwapKind.GIVEN_IN){
                        amount = tradeToReport.currencyTraded;
                        require(tradeToReport.securityTraded==request.amount, "Insufficient pool tokens swapped in for currency");
                    }
                    else
                        _revert(Errors.UNHANDLED_BY_SECONDARY_POOL);

                    bytes32 orderType;
                    if (request.tokenOut == IERC20(_currency) && request.tokenIn == IERC20(this)) {
                        orderType = "Sell";
                    } 
                    else if (request.tokenOut == IERC20(_security) && request.tokenIn == IERC20(this)) {
                        orderType = "Buy";
                    }
                    else
                        _revert(Errors.UNHANDLED_BY_SECONDARY_POOL);

                    emit TradeReport(
                        _security,
                        ref,
                        ref==bytes32("security") ? _orderbook.getOrder(tradeToReport.partyRef).party : _orderbook.getOrder(tradeToReport.counterpartyRef).party,
                        ref==bytes32("currency") ? _orderbook.getOrder(tradeToReport.partyRef).party : _orderbook.getOrder(tradeToReport.counterpartyRef).party,
                        orderType,
                        tradeToReport.currencyTraded.divDown(tradeToReport.securityTraded),                    
                        _currency,
                        amount,
                        tradeToReport.dt
                    );
                    tradeToReport.securityTraded = _downscaleDown(tradeToReport.securityTraded, _scalingFactorSecurity);
                    tradeToReport.currencyTraded = _downscaleDown(tradeToReport.currencyTraded, _scalingFactorCurrency);
                    _orderbook.removeTrade(request.from, tp);
                    // The amount given is for token out, the amount calculated is for token in
                    return _downscaleDown(amount, scalingFactors[indexOut]);
                }
            }
            else if(otype == keccak256(abi.encodePacked("Limit")) && tp!=0){ 
                //in a limit order, price is specified by the user
                params = IMarginOrder.Params({
                    trade: IMarginOrder.OrderType.Limit,
                    price: tp 
                });                    
            }
            else if(otype == keccak256(abi.encodePacked("Market")) && tp!=0){
                //market orders carry the last settled price from the Dapp 
                params = IMarginOrder.Params({
                    trade: IMarginOrder.OrderType.Market,
                    price: tp
                });
            }
            else if(otype.length == 32 && tp == 0){
                //cancel order with otype having order ref [hash value]
                if ((request.tokenOut == IERC20(_security) || request.tokenOut == IERC20(_currency)) 
                        && request.tokenIn == IERC20(this) && request.kind==IVault.SwapKind.GIVEN_IN) {
                    amount = _orderbook.cancelOrder(otype);
                    require(amount==request.amount, "Insufficient pool tokens swapped in");
                    emit OrderBook(request.from, address(request.tokenIn), address(request.tokenOut), request.amount, tp, amount, block.timestamp, otype);
                    // The amount given is for token out, the amount calculated is for token in
                    return _downscaleDown(amount, scalingFactors[indexOut]);
                } 
                else
                    _revert(Errors.UNHANDLED_BY_SECONDARY_POOL);
            }
            else if(otype.length == 32 && tp != 0){
                //leave aside request amount to cover margin and collateral claims if currency is paid in to buy a security 
                if(request.tokenIn == IERC20(_currency))
                    request.amount = FixedPoint.sub(request.amount, FixedPoint.mulDown(request.amount, FixedPoint.add(_margin, _collateral)));
                //edit order with otype having order ref [hash value]
                if (request.tokenIn == IERC20(this) && request.kind==IVault.SwapKind.GIVEN_IN) {
                    //calculate stop loss price (amount) with constraints of margin and collateral obligation
                    amount = FixedPoint.sub(tp, FixedPoint.mulDown(tp, FixedPoint.add(_margin, _collateral)));
                    emit OrderBook(request.from, address(request.tokenIn), address(request.tokenOut), request.amount, tp, amount, block.timestamp, otype);
                    //calculate the actual request amount
                    if(request.tokenIn == IERC20(_currency))
                        request.amount = FixedPoint.add(request.amount, FixedPoint.sub(1e18, FixedPoint.add(_margin, _collateral)));
                    //request amount (security, currency) is less than original amount, so some BPT is returned to the pool
                    amount = _orderbook.editOrder(otype);
                    amount = Math.sub(amount, request.amount);                    
                    //security or currency tokens are paid out for bpt to be paid in
                    return _downscaleDown(amount, scalingFactors[indexOut]);
                } 
                else if (request.tokenOut == IERC20(this) && request.kind==IVault.SwapKind.GIVEN_IN) {
                    //calculate stop loss price (amount) with constraints of margin and collateral obligation
                    amount = FixedPoint.sub(tp, FixedPoint.mulDown(tp, FixedPoint.add(_margin, _collateral)));
                    emit OrderBook(request.from, address(request.tokenIn), address(request.tokenOut), request.amount, tp, amount, block.timestamp, otype);
                    //calculate the actual request amount
                    if(request.tokenIn == IERC20(_currency))
                        request.amount = FixedPoint.add(request.amount, FixedPoint.sub(1e18, FixedPoint.add(_margin, _collateral)));
                    //request amount (security, currency) is more than original amount, so additional BPT is paid out from the pool
                    amount = _orderbook.editOrder(otype);
                    amount = Math.sub(request.amount, amount);
                    require(balances[_bptIndex] >= amount, "INSUFFICIENT_INTERNAL_BALANCE");                    
                    // bpt tokens equivalent to amount requested adjusted to existing amount are exiting the Pool, so we round down.
                    return _downscaleDown(amount, scalingFactors[indexOut]);  
                }
                else
                    _revert(Errors.UNHANDLED_BY_SECONDARY_POOL);
            }
            else
                _revert(Errors.UNHANDLED_BY_SECONDARY_POOL);
        }else
             _revert(Errors.UNHANDLED_BY_SECONDARY_POOL);

        require(request.amount >= _minOrderSize, "Order below minimum size");        

        // requested tokens can either be security or cash but token out always need to be bpt 
        if ((request.tokenIn == IERC20(_security) || request.tokenIn == IERC20(_currency)) 
            && request.tokenOut == IERC20(this) && request.kind == IVault.SwapKind.GIVEN_IN) {
            if(balances[_bptIndex] > request.amount){
                balances[_bptIndex] = Math.sub(balances[_bptIndex], request.amount);
                //calculate stop loss price (amount) with constraints of margin and collateral obligation
                amount = FixedPoint.sub(params.price, FixedPoint.mulDown(params.price, FixedPoint.add(_margin, _collateral)));
                //leave aside request amount to cover margin and collateral claims if currency is paid in to buy a security 
                if(request.tokenIn == IERC20(_currency))
                    request.amount = FixedPoint.sub(request.amount, FixedPoint.mulDown(request.amount, FixedPoint.add(_margin, _collateral)));
                //register order in orderbook
                ref = _orderbook.newOrder(request, params);
            }       
            else
                _revert(Errors.INSUFFICIENT_INTERNAL_BALANCE);
        } 
        else {
            _revert(Errors.UNHANDLED_BY_SECONDARY_POOL);
        }
            
        emit OrderBook(request.from, address(request.tokenIn), address(request.tokenOut), request.amount, params.price, amount, block.timestamp, ref);
        
        // adding back request amount to send back correct amount of bpt
        if(request.tokenIn == IERC20(_currency))
            request.amount = FixedPoint.add(request.amount, FixedPoint.sub(1e18, FixedPoint.add(_margin, _collateral)));
        // bpt tokens equivalent to amount requested are exiting the Pool, so we round down.
        return _downscaleDown(request.amount, scalingFactors[indexOut]);
    }
    
    function _onInitializePool(
        bytes32,
        address sender,
        address recipient,
        uint256[] memory,
        bytes memory userData
    ) internal view override whenNotPaused returns (uint256, uint256[] memory) {
        //on initialization, pool simply premints max BPT supply possible
        address balancerManager = _balancerManager;
        _require(sender == balancerManager, Errors.INVALID_INITIALIZATION);
        _require(recipient == payable(balancerManager), Errors.INVALID_INITIALIZATION);

        uint256[] memory amountsIn = userData.joinKind();
        amountsIn[_currencyIndex] = _upscale(amountsIn[_currencyIndex], _scalingFactorCurrency);
        uint256 bptAmountOut = _INITIAL_BPT_SUPPLY;
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
        //joins are not supported as this pool supports an order book only
        _revert(Errors.UNHANDLED_BY_SECONDARY_POOL);
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
    ) internal pure override returns (uint256 bptAmountIn, uint256[] memory amountsOut) {
        MarginPoolUserData.ExitKind kind = userData.exitKind();
        if (kind != MarginPoolUserData.ExitKind.EXACT_BPT_IN_FOR_TOKENS_OUT) {
            //usually exit pool reverts
            _revert(Errors.UNHANDLED_BY_SECONDARY_POOL);
        } else {
            (bptAmountIn, amountsOut) = _exit(balances, userData);
        }
    }

    function _exit(uint256[] memory balances, bytes memory userData)
        private
        pure
        returns (uint256, uint256[] memory)
    {   
        uint256 bptAmountIn = userData.exactBptInForTokensOut();
        uint256[] memory amountsOut = new uint256[](balances.length);
        for (uint256 i = 0; i < balances.length; i++) {
                amountsOut[i] = balances[i];
        }

        return (bptAmountIn, amountsOut);
    }

    function _getMaxTokens() internal pure override returns (uint256) {
        return _TOTAL_TOKENS;
    }

    function _getTotalTokens() internal view virtual override returns (uint256) {
        return _TOTAL_TOKENS;
    }

    function _scalingFactor(IERC20 token) internal view virtual override returns (uint256) {
        if (token == IERC20(_security)){
            return _scalingFactorSecurity;
        }
        else if(token == IERC20(_currency)){
            return _scalingFactorCurrency;
        }
        else if(token == this){
            return FixedPoint.ONE;
        }
         else {
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
