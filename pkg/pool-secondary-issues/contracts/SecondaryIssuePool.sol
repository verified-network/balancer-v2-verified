// Implementation of pool for secondary issues of security tokens that support multiple order types
// (c) Kallol Borah, 2022
//"SPDX-License-Identifier: BUSL1.1"

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "./interfaces/IOrder.sol";
import "./interfaces/ITrade.sol";
import "./interfaces/ISettlor.sol";
import "./utilities/StringUtils.sol";
import "./Orderbook.sol";

import "@balancer-labs/v2-pool-utils/contracts/BasePool.sol";

import "@balancer-labs/v2-solidity-utils/contracts/helpers/ERC20Helpers.sol";

import "@balancer-labs/v2-interfaces/contracts/vault/IGeneralPool.sol";
import "@balancer-labs/v2-interfaces/contracts/solidity-utils/helpers/BalancerErrors.sol";

contract SecondaryIssuePool is BasePool, IGeneralPool {
    using StringUtils for *;

    Orderbook public orderbook;
    
    address private _security;
    address private _currency;

    uint256 private constant _TOTAL_TOKENS = 3; //Security token, Currency token (ie, paired token), Balancer pool token

    uint256 private constant _INITIAL_BPT_SUPPLY = 2**(112) - 1;

    uint256 private _MAX_TOKEN_BALANCE;

    uint256 private immutable _bptIndex;
    uint256 private immutable _securityIndex;
    uint256 private immutable _currencyIndex;

    address payable private _balancerManager;
    
    //order matching related    
    uint256 private _bestUnfilledBid;
    uint256 private _bestUnfilledOffer;

    event TradeReport(
        address indexed security,
        address party,
        address counterparty,
        uint256 price,
        uint256 askprice,
        address currency,
        uint256 amount,
        bytes32 status,
        uint256 executionDate
    );

    event BestAvailableTrades(uint256 bestUnfilledBid, uint256 bestUnfilledOffer);

    event Offer(address indexed security, uint256 secondaryOffer);    

    constructor(
        IVault vault,
        string memory name,
        string memory symbol,
        address security,
        address currency,
        uint256 maxSecurityOffered,
        uint256 tradeFeePercentage,
        uint256 pauseWindowDuration,
        uint256 bufferPeriodDuration,
        address owner
    )
        BasePool(
            vault,
            IVault.PoolSpecialization.GENERAL,
            name,
            symbol,
            _sortTokens(IERC20(security), IERC20(currency), IERC20(this)),
            new address[](_TOTAL_TOKENS),
            tradeFeePercentage,
            pauseWindowDuration,
            bufferPeriodDuration,
            owner
        )
    {
        // set tokens
        _security = security;
        _currency = currency;

        // Set token indexes
        (uint256 securityIndex, uint256 currencyIndex, uint256 bptIndex) = _getSortedTokenIndexes(
            IERC20(security),
            IERC20(currency),
            IERC20(this)
        );
        _bptIndex = bptIndex;
        _securityIndex = securityIndex;
        _currencyIndex = currencyIndex;

        // set max total balance of securities
        _MAX_TOKEN_BALANCE = maxSecurityOffered;

        _balancerManager = payable(owner);

        orderbook = new Orderbook(_balancerManager, _security, _currency);
    }

    function getSecurity() external view returns (address) {
        return _security;
    }

    function getCurrency() external view returns (address) {
        return _currency;
    }

    function getSecurityOffered() external view returns (uint256) {
        return _MAX_TOKEN_BALANCE;
    }

    function initialize() external {
        bytes32 poolId = getPoolId();
        IVault vault = getVault();
        (IERC20[] memory tokens, , ) = vault.getPoolTokens(poolId);

        uint256[] memory _maxAmountsIn = new uint256[](_TOTAL_TOKENS);
        _maxAmountsIn[_bptIndex] = _INITIAL_BPT_SUPPLY;

        IVault.JoinPoolRequest memory request = IVault.JoinPoolRequest({
            assets: _asIAsset(tokens),
            maxAmountsIn: _maxAmountsIn,
            userData: "",
            fromInternalBalance: false
        });
        vault.joinPool(getPoolId(), address(this), address(this), request);
        emit Offer(_security, _MAX_TOKEN_BALANCE);
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
                request.tokenIn == IERC20(_currency) ||
                request.tokenIn == IERC20(_security), "Invalid swapped tokens");
        
        uint256[] memory scalingFactors = _scalingFactors();
        IOrder.Params memory params;
        (_bestUnfilledBid, _bestUnfilledOffer) = orderbook.getBestTrade();

        if(request.userData.length!=0){
            if(request.amount==0){
                if(request.kind == IVault.SwapKind.GIVEN_IN){
                    if (request.tokenIn == IERC20(_security) || request.tokenIn == IERC20(_currency)) {
                        emit BestAvailableTrades(_bestUnfilledBid, _bestUnfilledOffer);
                        ITrade.trade memory tradeToReport = orderbook.getTrade(request.from, string(request.userData).stringToUint());
                        ISettlor(_balancerManager).requestSettlement(tradeToReport, orderbook);
                        uint256 amount = keccak256(abi.encodePacked(tradeToReport.partyTokenIn))==keccak256(abi.encodePacked("security")) ? tradeToReport.partyInAmount : tradeToReport.counterpartyInAmount;
                        emit TradeReport(
                            tradeToReport.security,
                            keccak256(abi.encodePacked(tradeToReport.partyTokenIn))==keccak256(abi.encodePacked("security")) ? tradeToReport.party : tradeToReport.counterparty,
                            keccak256(abi.encodePacked(tradeToReport.partyTokenIn))==keccak256(abi.encodePacked("currency")) ? tradeToReport.party : tradeToReport.counterparty,
                            Math.div(keccak256(abi.encodePacked(tradeToReport.partyTokenIn))==keccak256(abi.encodePacked("currency")) ? tradeToReport.partyInAmount : tradeToReport.counterpartyInAmount, amount, false),
                            tradeToReport.price,
                            tradeToReport.currency,
                            amount,
                            "Pending",
                            tradeToReport.dt
                        );
                        return _downscaleDown(amount, scalingFactors[indexOut]);
                    }
                }
                else if(request.kind == IVault.SwapKind.GIVEN_OUT) {
                    if (request.tokenOut == IERC20(_security) || request.tokenOut == IERC20(_currency)) {
                        emit BestAvailableTrades(_bestUnfilledBid, _bestUnfilledOffer);
                        ITrade.trade memory tradeToReport = orderbook.getTrade(request.from, string(request.userData).stringToUint());
                        ISettlor(_balancerManager).requestSettlement(tradeToReport, orderbook);
                        uint256 amount = keccak256(abi.encodePacked(tradeToReport.partyTokenIn))==keccak256(abi.encodePacked("security")) ? tradeToReport.partyInAmount : tradeToReport.counterpartyInAmount;
                        emit TradeReport(
                            tradeToReport.security,
                            keccak256(abi.encodePacked(tradeToReport.partyTokenIn))==keccak256(abi.encodePacked("security")) ? tradeToReport.party : tradeToReport.counterparty,
                            keccak256(abi.encodePacked(tradeToReport.partyTokenIn))==keccak256(abi.encodePacked("currency")) ? tradeToReport.party : tradeToReport.counterparty,
                            Math.div(keccak256(abi.encodePacked(tradeToReport.partyTokenIn))==keccak256(abi.encodePacked("currency")) ? tradeToReport.partyInAmount : tradeToReport.counterpartyInAmount, amount, false),
                            tradeToReport.price,
                            tradeToReport.currency,
                            amount,
                            "Pending",
                            tradeToReport.dt
                        );
                        return _downscaleDown(amount, scalingFactors[indexIn]);
                    }
                }
            }
            else{
                uint256 tradeType_length = string(request.userData).substring(0,1).stringToUint();
                bytes32 otype = string(request.userData).substring(1, tradeType_length + 1).stringToBytes32();
                if(otype!="" && tradeType_length!=0){ //we have removed market order from this place, any order where price is indicated is a limit or stop loss order
                    params = IOrder.Params({
                        trade: otype=="Limit" ? IOrder.OrderType.Limit : IOrder.OrderType.Stop,
                        price: string(request.userData).substring(tradeType_length, request.userData.length).stringToUint()
                    });
                }
            }                  
        }else{ //by default, any order without price specified is a market order
            if (request.tokenIn == IERC20(_currency) || request.tokenOut == IERC20(_security)){
                //it is a buy (bid), so need the best offer by a counter party
                params = IOrder.Params({
                    trade: IOrder.OrderType.Market,
                    price: _bestUnfilledOffer
                });
            }
            else {
                //it is a sell (offer), so need the best bid by a counter party
                params = IOrder.Params({
                    trade: IOrder.OrderType.Market,
                    price: _bestUnfilledBid
                });
            }
        }

        if (request.kind == IVault.SwapKind.GIVEN_IN) 
            request.amount = _upscale(request.amount, scalingFactors[indexIn]);
        else if (request.kind == IVault.SwapKind.GIVEN_OUT)
            request.amount = _upscale(request.amount, scalingFactors[indexOut]);

        if (request.tokenOut == IERC20(_currency) || request.tokenIn == IERC20(_security)) {
            orderbook.newOrder(request, params, IOrder.Order.Sell, balances, _currencyIndex, _securityIndex);
        } 
        else if (request.tokenOut == IERC20(_security) || request.tokenIn == IERC20(_currency)) {
            orderbook.newOrder(request, params, IOrder.Order.Buy, balances, _currencyIndex, _securityIndex);
        }
    }

    function _onInitializePool(
        bytes32,
        address sender,
        address recipient,
        uint256[] memory,
        bytes memory
    ) internal view override whenNotPaused returns (uint256, uint256[] memory) {
        //on initialization, pool simply premints max BPT supply possible
        _require(sender == address(this), Errors.INVALID_INITIALIZATION);
        _require(recipient == address(this), Errors.INVALID_INITIALIZATION);

        uint256 bptAmountOut = _INITIAL_BPT_SUPPLY;

        uint256[] memory amountsIn = new uint256[](_TOTAL_TOKENS);
        amountsIn[_bptIndex] = _INITIAL_BPT_SUPPLY;

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
        uint256[] memory,
        uint256,
        uint256,
        uint256[] memory,
        bytes memory
    ) internal pure override returns (uint256, uint256[] memory) {
        //exits are not required now, but we perhaps need to provide an emergency pause mechanism that returns tokens to order takers and makers
        _revert(Errors.UNHANDLED_BY_SECONDARY_POOL);
    }

    function _getMaxTokens() internal pure override returns (uint256) {
        return _TOTAL_TOKENS;
    }

    function _getTotalTokens() internal view virtual override returns (uint256) {
        return _TOTAL_TOKENS;
    }

    function _scalingFactor(IERC20 token) internal view virtual override returns (uint256) {
        if (token == IERC20(_security) || token == IERC20(_currency) || token == IERC20(this)) {
            return FixedPoint.ONE;
        } else {
            _revert(Errors.INVALID_TOKEN);
        }
    }

    function _scalingFactors() internal view virtual override returns (uint256[] memory) {
        uint256[] memory scalingFactors = new uint256[](_TOTAL_TOKENS);
        scalingFactors[_securityIndex] = FixedPoint.ONE;
        scalingFactors[_currencyIndex] = FixedPoint.ONE;
        scalingFactors[_bptIndex] = FixedPoint.ONE;
        return scalingFactors;
    }

    function _getMinimumBpt() internal pure override returns (uint256) {
        // Secondary Pools don't lock any BPT, as the total supply will already be forever non-zero due to the preminting
        // mechanism, ensuring initialization only occurs once.
        return 0;
    }
}
