// Implementation of order book for secondary issues of security tokens that support multiple order types
// (c) Kallol Borah, 2022
//"SPDX-License-Identifier: BUSL1.1"

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "./Heap.sol";

import "./interfaces/IOrder.sol";
import "./interfaces/ITrade.sol";
import "./interfaces/ISecondaryIssuePool.sol";

import "@balancer-labs/v2-solidity-utils/contracts/math/Math.sol";
import "@balancer-labs/v2-solidity-utils/contracts/math/FixedPoint.sol";
import "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/Ownable.sol";
import "@balancer-labs/v2-interfaces/contracts/vault/IPoolSwapStructs.sol";

contract Orderbook is IOrder, ITrade, Ownable, Heap{
    using FixedPoint for uint256;

    //counter for block timestamp nonce for creating unique order references
    uint256 private _previousTs = 0;

    //mapping order reference to order
    mapping(bytes32 => IOrder.order) private _orders;

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
        bytes32 _poolId = ISecondaryIssuePool(_pool).getPoolId();
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
        IOrder.Params memory _params
    ) public onlyOwner returns(bytes32){
        require(_params.trade == IOrder.OrderType.Market || _params.trade == IOrder.OrderType.Limit);
        _previousTs = block.timestamp == _previousTs ? _previousTs + 1 : block.timestamp;
        bytes32 ref = keccak256(abi.encodePacked(_request.from, _previousTs));
        //fill up order details
        IOrder.order memory nOrder = IOrder.order({
            tokenIn: address(_request.tokenIn),
            otype: _params.trade,
            status: IOrder.OrderStatus.Open,
            qty: _request.amount,
            party: _request.from
        });
        _orders[ref] = nOrder;        
        if(nOrder.tokenIn==_security)
            //sell order
            insertSellOrder(_params.price, ref);    
        else if(nOrder.tokenIn==_currency)
            //buy order
            insertBuyOrder(_params.price, ref);
        return matchOrders(ref, nOrder, _params.price);
    }

    function editOrder(
        bytes32 ref,
        uint256 _price,
        IPoolSwapStructs.SwapRequest memory _request
    ) public onlyOwner returns(uint256){
        require(_orders[ref].status == IOrder.OrderStatus.Open, "Order is already filled");
        require(_orders[ref].party == _request.from, "Sender is not order creator");
        bool buy = _orders[ref].tokenIn==_security ? false : true;
        editOrderbook(_price, ref, buy);
        uint256 qty = _orders[ref].qty;
        _orders[ref].qty = _request.amount;
        return qty;
    }

    function cancelOrder(bytes32 ref, address sender) public onlyOwner returns(uint256){
        require(_orders[ref].status == IOrder.OrderStatus.Open, "Order is already filled");
        require(_orders[ref].party == sender, "Sender is not order creator");
        bool buy = _orders[ref].tokenIn==_security ? false : true;
        cancelOrderbook(ref, buy);
        uint256 qty = _orders[ref].qty;
        delete _orders[ref];
        return qty;
    }

    //match market orders. Sellers get the best price (highest bid) they can sell at.
    //Buyers get the best price (lowest offer) they can buy at.
    function matchOrders(bytes32 ref, IOrder.order memory _order, uint256 price) private returns (bytes32){
        Node memory bestBid;
        uint256 bestPrice = 0;
        Node memory bestOffer;        
        //uint256 bidIndex = 0;   
        uint256 securityTraded;
        uint256 currencyTraded;
        uint256 i;
        Node[] memory _marketOrders;
        //sell order, sellers want the buy orderbook && buy order, buyers want the sell orderbook
        _marketOrders =  _order.tokenIn == _security ? _buyOrderbook : _sellOrderbook;
        //if market depth exists, then fill order at one or more price points in the order book
        for(i=0; i<_marketOrders.length; i++){
            if (_order.qty == 0) break; //temporary condition to avoid unnesscary looping for consecutive limit orders
            if (
                _marketOrders[i].ref != ref && //orders can not be matched with themselves
                _orders[_marketOrders[i].ref].party != _order.party && //orders posted by a party can not be matched by a counter offer by the same party
                _orders[_marketOrders[i].ref].status != IOrder.OrderStatus.Filled //orders that are filled can not be matched /traded again
            ) {
                if (_marketOrders[i].price == 0 && price == 0) continue; // Case: If Both CP & Party place Order@CMP
                if (_orders[_marketOrders[i].ref].tokenIn == _currency && _order.tokenIn == _security) {
                    //check if a buy order in the order book can execute over the prevailing (low) price passed to the function
                    if (getBestBuyPrice() >= price || price == 0) { 
                        bestPrice = _marketOrders[i].price;    
                        bestBid = _marketOrders[i];
                    }
                } 
                else if (_orders[_marketOrders[i].ref].tokenIn == _security && _order.tokenIn == _currency) {
                    //check if a sell order in the order book can execute under the prevailing (high) price passed to the function
                    if (getBestSellPrice() <= price || price == 0) { 
                        bestPrice = getBestSellPrice() == 0 ? price : _marketOrders[i].price;  
                        bestOffer = _marketOrders[i];
                    }
                }
            }
            if (bestBid.ref != "") {
                if(_order.tokenIn==_security){
                    securityTraded = _orders[bestBid.ref].qty.divDown(bestPrice); // calculating amount of security that can be brought
                    if(securityTraded >= _order.qty){
                        securityTraded = _order.qty;
                        currencyTraded = _order.qty.mulDown(bestPrice);
                        _orders[bestBid.ref].qty = Math.sub(_orders[bestBid.ref].qty, _order.qty);
                        _order.qty = 0;
                        _orders[bestBid.ref].status = _orders[bestBid.ref].qty == 0 ? IOrder.OrderStatus.Filled : IOrder.OrderStatus.PartlyFilled;
                        _order.status = IOrder.OrderStatus.Filled;  
                        reportTrade(ref, bestBid.ref, securityTraded, currencyTraded);
                        break;
                    }    
                    else if(securityTraded!=0){
                        currencyTraded = securityTraded.mulDown(bestPrice);
                        _order.qty = Math.sub(_order.qty, securityTraded);
                        _orders[bestBid.ref].qty = 0;
                        _orders[bestBid.ref].status = IOrder.OrderStatus.Filled;
                        _order.status = IOrder.OrderStatus.PartlyFilled;
                        reportTrade(ref, bestBid.ref, securityTraded, currencyTraded);
                        removeBuyOrder();
                    }
                }
            }
            else if (bestOffer.ref != "") {
                if(_order.tokenIn==_currency){
                    currencyTraded = _orders[bestOffer.ref].qty.mulDown(bestPrice); // calculating amount of currency that can taken out    
                    if(currencyTraded >=  _order.qty){
                        currencyTraded = _order.qty;
                        securityTraded = _order.qty.divDown(bestPrice);
                        _orders[bestOffer.ref].qty = Math.sub(_orders[bestOffer.ref].qty, securityTraded);
                        _order.qty = 0;
                        _orders[bestOffer.ref].status = _orders[bestOffer.ref].qty == 0 ? IOrder.OrderStatus.Filled : IOrder.OrderStatus.PartlyFilled;
                        _order.status = IOrder.OrderStatus.Filled;  
                        reportTrade(ref, bestOffer.ref, securityTraded, currencyTraded);
                        break;
                    }    
                    else if(currencyTraded!=0){
                        securityTraded = currencyTraded.divDown(bestPrice);
                        _order.qty = Math.sub(_order.qty, currencyTraded);
                        _orders[bestOffer.ref].qty = 0;
                        _orders[bestOffer.ref].status = IOrder.OrderStatus.Filled;
                        _order.status = IOrder.OrderStatus.PartlyFilled;    
                        reportTrade(ref, bestOffer.ref, securityTraded, currencyTraded);     
                        removeSellOrder();               
                    }                    
                }
            }
            //i++;
        }        
        //remove filled order from orderbook
        if(_order.status == IOrder.OrderStatus.Filled){
            bool buy = _order.tokenIn==_security ? false : true;
            cancelOrderbook(ref, buy);
        }
        return ref;
    }
    
    function reportTrade(bytes32 _ref, bytes32 _cref, uint256 securityTraded, uint256 currencyTraded) private {//returns(uint256){
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

    function getOrder(bytes32 _ref) external override view returns(IOrder.order memory){
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
    
    //remove this function using unbounded for loop, use the subgraph instead
    function getOrderRef() external override view returns (bytes32[] memory) {
        bytes32[] memory refs = new bytes32[](_sellOrderbook.length);
        uint256 i;
        for(uint256 j=0; j<_sellOrderbook.length; j++){
            if(_orders[_sellOrderbook[j].ref].party==msg.sender){
                refs[i] = _sellOrderbook[j].ref;
                i++;
            }
        }
        return refs;
    }

    function revertTrade(
        bytes32 _orderRef,
        uint256 _qty,
        uint256 _price
    ) external override {
        require(msg.sender==_balancerManager || msg.sender==owner(), "Unauthorized access");
        _orders[_orderRef].qty = _orders[_orderRef].qty + _qty;
        _orders[_orderRef].status = OrderStatus.Open;
        //push to order book
        if(_orders[_orderRef].tokenIn==_security)
            //sell order
            insertSellOrder(_price, _orderRef);    
        else if(_orders[_orderRef].tokenIn==_currency)
            //buy order
            insertBuyOrder(_price, _orderRef);
    }

    function orderFilled(bytes32 partyRef, bytes32 counterpartyRef, uint256 executionDate) external override {
        require(msg.sender==_balancerManager || msg.sender==owner(), "Unauthorized access");
        delete _orders[partyRef];
        delete _orders[counterpartyRef];
        delete _tradeRefs[_orders[partyRef].party][executionDate];
        delete _tradeRefs[_orders[counterpartyRef].party][executionDate];
    }

}