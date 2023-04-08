// Implementation of order book for margin trading
// (c) Kallol Borah, 2022
//"SPDX-License-Identifier: BUSL1.1"

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "./interfaces/ITrade.sol";
import "./interfaces/IMarginOrder.sol";
import "./interfaces/IMarginTradingPool.sol";

import "@balancer-labs/v2-solidity-utils/contracts/math/Math.sol";
import "@balancer-labs/v2-solidity-utils/contracts/math/FixedPoint.sol";
import "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/Ownable.sol";
import "@balancer-labs/v2-interfaces/contracts/vault/IPoolSwapStructs.sol";

contract Orderbook is IMarginOrder, ITrade, Ownable{
    using FixedPoint for uint256;

    //counter for block timestamp nonce for creating unique order references
    uint256 private _previousTs = 0;

    //mapping order reference to order
    mapping(bytes32 => IMarginOrder.order) private _orders;

    //order references
    bytes32[] private _orderbook;

    mapping(bytes32 => uint256) private _orderIndex;

    //order references from party to order timestamp
    mapping(address => mapping(uint256 => ITrade.trade)) private _tradeRefs;

    //mapping parties to trade time stamps
    mapping(address => uint256[]) private _trades;

    address private _security;
    address private _currency;
    address payable private _balancerManager;
    address private _pool;

    constructor(address balancerManager, address security, address currency, address pool){       
        _balancerManager = payable(balancerManager);
        _security = security;
        _currency = currency;
        _pool = pool; 
    }

    function getPoolId() external override view returns(bytes32){
        bytes32 _poolId = IMarginTradingPool(_pool).getPoolId();
        return _poolId;
    }

    function getSecurity() external override view returns (address) {
        return _security;
    }

    function getCurrency() external override view returns (address) {
        return _currency;
    }

    function newOrder(
        IPoolSwapStructs.SwapRequest memory _request,
        IMarginOrder.Params memory _params
    ) public onlyOwner returns(bytes32){
        require(_params.trade == IMarginOrder.OrderType.Market || _params.trade == IMarginOrder.OrderType.Limit);

        if(block.timestamp == _previousTs)
            _previousTs = _previousTs + 1;
        else
            _previousTs = block.timestamp;
        bytes32 ref = keccak256(abi.encodePacked(_request.from, _previousTs));
        //fill up order details
        IMarginOrder.order memory nOrder = IMarginOrder.order({
            tokenIn: address(_request.tokenIn),
            otype: _params.trade,
            status: IMarginOrder.OrderStatus.Open,
            party: _request.from,
            qty: _request.amount
        });
        _orders[ref] = nOrder;
        _orderIndex[ref] = _orderbook.length;
        _orderbook.push(ref);
        return ref;
    }

    function getOrderRef() external override view returns (bytes32[] memory) {
        bytes32[] memory refs = new bytes32[](_orderbook.length);
        uint256 i;
        for(uint256 j=0; j<_orderbook.length; j++){
            if(_orders[_orderbook[j]].party==msg.sender && _orders[_orderbook[j]].status==OrderStatus.Open){
                refs[i] = _orderbook[j];
                i++;
            }
        }
        return refs;
    }

    function editOrder(
        bytes32 ref
    ) public view onlyOwner returns(uint256){        
        require(_orders[ref].status == IMarginOrder.OrderStatus.Open, "Order is already filled");
        require(_orders[ref].party == msg.sender, "Sender is not order creator");
        return _orders[ref].qty;
    }

    function cancelOrder(bytes32 ref) public onlyOwner returns(uint256){        
        require(_orders[ref].status == IMarginOrder.OrderStatus.Open, "Order is already filled");
        require(_orders[ref].party == msg.sender, "Sender is not order creator");
        _orders[ref].status = IMarginOrder.OrderStatus.Cancelled;
        delete _orderbook[_orderIndex[ref] - 1];
        return _orders[ref].qty;
    }
    
    function reportTrade(bytes32 _ref, bytes32 _cref, uint256 securityTraded, uint256 currencyTraded) public {
        _orders[_ref].status = IMarginOrder.OrderStatus.Filled;
        _orders[_cref].status = IMarginOrder.OrderStatus.Filled;
        _previousTs = _previousTs + 1;
        uint256 oIndex = _previousTs;
        ITrade.trade memory tradeToReport = ITrade.trade({
            partyRef: _ref,
            partyAddress:  _orders[_ref].party,
            counterpartyRef: _cref,            
            dt: oIndex,
            securityTraded: securityTraded,
            currencyTraded: currencyTraded
        });                 
        _tradeRefs[_orders[_ref].party][oIndex] = tradeToReport;
        _tradeRefs[_orders[_cref].party][oIndex] = tradeToReport;        
        _trades[_orders[_ref].party].push(tradeToReport.dt);
        _trades[_orders[_cref].party].push(tradeToReport.dt);
    }

    function getOrder(bytes32 _ref) external override view returns(IMarginOrder.order memory){
        require(msg.sender==owner() || msg.sender==_balancerManager || msg.sender==_orders[_ref].party, "Unauthorized access to orders");
        return _orders[_ref];
    }

    function getTrade(address _party, uint256 _timestamp) external override view returns(ITrade.trade memory){
        require(msg.sender==owner() || msg.sender==_party, "Unauthorized access to trades");
        return _tradeRefs[_party][_timestamp];
    }

    function getTrades() external override view returns(uint256[] memory){
        return _trades[msg.sender];
    }

    function removeTrade(address _party, uint256 _timestamp) public onlyOwner {
        for(uint256 i=0; i<_trades[_party].length; i++){
            if(_trades[_party][i]==_timestamp)
                delete _trades[_party][i];
        }
    }

    function revertTrade(
        bytes32 _orderRef
    ) external override {
        require(msg.sender==_balancerManager || msg.sender==owner(), "Unauthorized access");
        _orders[_orderRef].status = OrderStatus.Open;
    }

    function orderFilled(bytes32 partyRef, bytes32 counterpartyRef, uint256 executionDate) external override {
        require(msg.sender==_balancerManager || msg.sender==owner(), "Unauthorized access");
        delete _orders[partyRef];
        delete _orders[counterpartyRef];
        delete _tradeRefs[_orders[partyRef].party][executionDate];
        delete _tradeRefs[_orders[counterpartyRef].party][executionDate];
    }

}