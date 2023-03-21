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
    ) public onlyOwner returns(bytes32, uint256, uint256){
        require(_params.trade == IOrder.OrderType.Market || _params.trade == IOrder.OrderType.Limit);
        if(block.timestamp == _previousTs)
            _previousTs = _previousTs + 1;
        else
            _previousTs = block.timestamp;
        bytes32 ref = keccak256(abi.encodePacked(_request.from, _previousTs));
        //fill up order details
        IOrder.order memory nOrder = IOrder.order({
            tokenIn: address(_request.tokenIn),
            otype: _params.trade,
            status: IOrder.OrderStatus.Open,
            qty: _request.amount,
            party: _request.from,
            price: _params.price
        });
        _orders[ref] = nOrder;        
        if (_params.trade == IOrder.OrderType.Market) {                   
            return matchOrders(ref, nOrder, IOrder.OrderType.Market);
        } else if (_params.trade == IOrder.OrderType.Limit) {    
            if(nOrder.tokenIn==_security)
                //sell order
                insertSellOrder(_params.price, ref);    
            else if(nOrder.tokenIn==_currency)
                //buy order
                insertBuyOrder(_params.price, ref);
            return matchOrders(ref, nOrder, IOrder.OrderType.Limit);
        } 
    }

    /* //remove this function using unbounded for loop, use the subgraph instead
    function getOrderRef() external view override returns (bytes32[] memory) {
        bytes32[] memory refs = new bytes32[](_orderbook.length);
        uint256 i;
        for(uint256 j=0; j<_orderbook.length; j++){
            if(_orders[_orderbook[j].ref].party==msg.sender){
                refs[i] = _orderbook[j].ref;
                i++;
            }
        }
        return refs;
    }*/

    //to do : adjust price in orderbook
    function editOrder(
        bytes32 ref,
        uint256 _price,
        uint256 _qty
    ) public onlyOwner returns(uint256){
        require (_orders[ref].otype != IOrder.OrderType.Market, "Market order can not be changed");
        require(_orders[ref].status == IOrder.OrderStatus.Open, "Order is already filled");
        require(_orders[ref].party == msg.sender, "Sender is not order creator");
        _orders[ref].price = _price;
        uint256 qty = _orders[ref].qty;
        _orders[ref].qty = _qty;
        return qty;
    }

    function cancelOrder(bytes32 ref) public onlyOwner returns(uint256){
        require (_orders[ref].otype != IOrder.OrderType.Market, "Market order can not be cancelled");
        require(_orders[ref].status == IOrder.OrderStatus.Open, "Order is already filled");
        require(_orders[ref].party == msg.sender, "Sender is not order creator");
        /* // to do : remove element from orderbook
        for(uint256 i=0; i<_orderbook.length; i++){
            if(_orderbook[i].ref==ref)
                deleteOrder(i);
        }*/
        uint256 qty = _orders[ref].qty;
        delete _orders[ref];
        return qty;
    }

    //check if a buy order in the limit order book can execute over the prevailing (low) price passed to the function
    //check if a sell order in the limit order book can execute under the prevailing (high) price passed to the function
    function checkLimitOrders(bytes32 _ref, IOrder.OrderType _trade) private returns (uint256, bytes32[] memory){
        uint256 volume;
        bytes32[] memory _marketOrders;
        if(_orders[_ref].tokenIn==_security)
            //sell order, sellers want the buy orderbook
            _marketOrders = new bytes32[](_buyOrderbook.length);
        else
            //buy order, buyers want the sell orderbook
            _marketOrders = new bytes32[](_sellOrderbook.length);
        uint256 index;
        if(_orders[_ref].tokenIn==_security){
            for (uint256 i=0; i<_buyOrderbook.length; i++){
                if (getBestBuyPrice() >= _orders[_ref].price || _orders[_ref].price==0){
                    //since this is a sell order, counter offers must offer a better price
                    _marketOrders[index] = removeBuyOrder();
                    volume = Math.add(volume, _orders[_marketOrders[index]].qty);
                    /*if(_trade!=IOrder.OrderType.Market && _marketOrders[index]!=_ref){
                        //only if the consecutive order is a limit order, it goes to the market order book
                        _marketOrders[++index] = _ref;
                    }*/ 
                    //if it is a sell order, ie, security in
                    if(volume >= _orders[_ref].qty)
                        //if available market depth exceeds qty to trade, exit and avoid unnecessary lookup through orderbook  
                        return (volume, _marketOrders); 
                    index++;                    
                } 
                else //no more better counteroffers in the sorted orderbook, so no need to traverse it unnecessarily
                    break;
            }
            return (volume, _marketOrders);
        }
        else if(_orders[_ref].tokenIn==_currency){
            for (uint256 i=0 ; i<_sellOrderbook.length; i++){
                if (getBestSellPrice() <= _orders[_ref].price || _orders[_ref].price==0){
                    //since this is a buy order, counter offers to sell must be for lesser price 
                    _marketOrders[index] = removeSellOrder();
                    volume = Math.add(volume, _orders[_marketOrders[index]].price.mulDown(_orders[_marketOrders[index]].qty));
                    /*if(_trade!=IOrder.OrderType.Market && _marketOrders[index]!=_ref){
                        //only if the consecutive order is a limit order, it goes to the market order book
                        _marketOrders[++index] = _ref;
                    }*/  
                    //if it is a buy order, ie, currency in
                    if(volume >= _orders[_ref].qty)
                        //if available market depth exceeds qty to trade, exit and avoid unnecessary lookup through orderbook  
                        return (volume, _marketOrders); 
                    index++;                    
                } 
                else //no more better counteroffers in the sorted orderbook, so no need to traverse it unnecessarily
                    break;
            }
            return (volume, _marketOrders);
        }  
    }

    function reinsertOrders(bytes32[] memory _marketOrders) private {
        for(uint256 i=0; i<_marketOrders.length; i++){
            if(_orders[_marketOrders[i]].tokenIn==_security)
                insertSellOrder(_orders[_marketOrders[i]].price, _marketOrders[i]);
            else if(_orders[_marketOrders[i]].tokenIn==_currency)
                insertBuyOrder(_orders[_marketOrders[i]].price, _marketOrders[i]);
        }
    }

    //match market orders. Sellers get the best price (highest bid) they can sell at.
    //Buyers get the best price (lowest offer) they can buy at.
    function matchOrders(bytes32 ref, IOrder.order memory _order, IOrder.OrderType _trade) private returns (bytes32, uint256, uint256){
        bytes32 bestBid;
        uint256 bestPrice = 0;
        bytes32 bestOffer;        
        uint256 bidIndex = 0;   
        uint256 securityTraded;
        uint256 currencyTraded;
        uint256 i;
        bytes32[] memory _marketOrders;
        if(_order.tokenIn==_security)
            _marketOrders = new bytes32[](_buyOrderbook.length);
        else
            _marketOrders = new bytes32[](_sellOrderbook.length);

        //check if enough market volume exist to fulfil market orders, or if market depth is zero
        (i, _marketOrders) = checkLimitOrders(ref, _trade);
        if(_trade==IOrder.OrderType.Market){
            if(i < _order.qty){
                reinsertOrders(_marketOrders);
                return (ref, block.timestamp, 0);
            }
        }
        else if(_trade==IOrder.OrderType.Limit){
            if(i==0){
                return (ref, block.timestamp, 0);
            }
        }
        //if market depth exists, then fill order at one or more price points in the order book
        for(i=0; i<_marketOrders.length; i++){
            if (_order.qty == 0) break; //temporary condition to avoid unnesscary looping for consecutive limit orders
            if (
                _marketOrders[i] != ref && //orders can not be matched with themselves
                _orders[_marketOrders[i]].party != _order.party && //orders posted by a party can not be matched by a counter offer by the same party
                _orders[_marketOrders[i]].status != IOrder.OrderStatus.Filled //orders that are filled can not be matched /traded again
            ) {
                if (_orders[_marketOrders[i]].price == 0 && _order.price == 0) continue; // Case: If Both CP & Party place Order@CMP
                if (_orders[_marketOrders[i]].tokenIn == _currency && _order.tokenIn == _security) {
                    if (_orders[_marketOrders[i]].price >= _order.price || _order.price == 0) {
                        bestPrice = _orders[_marketOrders[i]].price;  
                        bestBid = _marketOrders[i];
                        bidIndex = i;
                    }
                } 
                else if (_orders[_marketOrders[i]].tokenIn == _security && _order.tokenIn == _currency) {
                    if (_orders[_marketOrders[i]].price <= _order.price || _order.price == 0) {
                        bestPrice = _orders[_marketOrders[i]].price;  
                        bestOffer = _marketOrders[i];
                        bidIndex = i;
                    }
                }
            }
            if (bestBid != "") {
                if(_order.tokenIn==_security){
                    securityTraded = _orders[bestBid].qty.divDown(bestPrice); // calculating amount of security that can be brought
                    if(securityTraded >= _order.qty){
                        securityTraded = _order.qty;
                        currencyTraded = _order.qty.mulDown(bestPrice);
                        _orders[bestBid].qty = Math.sub(_orders[bestBid].qty, _order.qty);
                        _order.qty = 0;
                        if(_orders[bestBid].qty == 0)
                        {
                            _orders[bestBid].status = IOrder.OrderStatus.Filled;
                            //deleteOrder(bidIndex); //not required since we have already removed element from heap
                        }
                        else{
                            _orders[bestBid].status = IOrder.OrderStatus.PartlyFilled;
                        }
                        _order.status = IOrder.OrderStatus.Filled;  
                        bidIndex = reportTrade(ref, bestBid, securityTraded, currencyTraded);
                        if(_order.otype == IOrder.OrderType.Market){
                            uint256 traded = calcTraded(ref, _order.party, true);
                            return (ref, bidIndex, traded);  
                        }
                    }    
                    else if(securityTraded!=0){
                        currencyTraded = securityTraded.mulDown(bestPrice);
                        _order.qty = Math.sub(_order.qty, securityTraded);
                        _orders[bestBid].qty = 0;
                        _orders[bestBid].status = IOrder.OrderStatus.Filled;
                        _order.status = IOrder.OrderStatus.PartlyFilled;
                        reportTrade(ref, bestBid, securityTraded, currencyTraded);
                        //deleteOrder(bidIndex); //not required since we have already removed element from heap
                    }
                }
            }
            else if (bestOffer != "") {
                if(_order.tokenIn==_currency){
                    currencyTraded = _orders[bestOffer].qty.mulDown(bestPrice); // calculating amount of currency that can taken out    
                    if(currencyTraded >= _order.qty){
                        currencyTraded = _order.qty;
                        securityTraded = _order.qty.divDown(bestPrice);
                        _orders[bestOffer].qty = Math.sub(_orders[bestOffer].qty, _order.qty);
                        _order.qty = 0;
                        if(_orders[bestOffer].qty == 0)
                        {
                            _orders[bestOffer].status = IOrder.OrderStatus.Filled;
                            //deleteOrder(bidIndex); //not required since we have already removed element from heap
                        }
                        else{
                            _orders[bestOffer].status = IOrder.OrderStatus.PartlyFilled;
                        }
                        _order.status = IOrder.OrderStatus.Filled;  
                        bidIndex = reportTrade(ref, bestOffer, securityTraded, currencyTraded);
                        if(_order.otype == IOrder.OrderType.Market){
                            uint256 traded = calcTraded(ref, _order.party, false); 
                            return (ref, bidIndex, traded);  
                        }  
                    }    
                    else if(currencyTraded!=0){
                        securityTraded = currencyTraded.divDown(bestPrice);
                        _order.qty = Math.sub(_order.qty, currencyTraded);
                        _orders[bestOffer].qty = 0;
                        _orders[bestOffer].status = IOrder.OrderStatus.Filled;
                        _order.status = IOrder.OrderStatus.PartlyFilled;    
                        reportTrade(ref, bestOffer, securityTraded, currencyTraded);                    
                        //deleteOrder(bidIndex); //not required since we have already removed element from heap
                    }                    
                }
            }
        }
    }
    
    function reportTrade(bytes32 _ref, bytes32 _cref, uint256 securityTraded, uint256 currencyTraded) private returns(uint256){
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
        return (oIndex);
    }

    function calcTraded(bytes32 _ref, address _party, bool currencyTraded) private returns(uint256){
        uint256 oIndex;
        uint256 volume;
        ITrade.trade memory tradeReport;
        for(uint256 i=0; i<_trades[_party].length; i++){
            oIndex = _trades[_party][i];
            tradeReport = _tradeRefs[_party][oIndex];
            if(tradeReport.partyRef==_ref){
                uint256 amount = currencyTraded ? tradeReport.currencyTraded : tradeReport.securityTraded;
                volume = Math.add(volume, amount);
            }
            delete _trades[_party][i];
            delete _tradeRefs[_party][oIndex];
        }
        return volume; 
    }   

    function getOrder(bytes32 _ref) external view returns(IOrder.order memory){
        require(msg.sender==owner() || msg.sender==_balancerManager || msg.sender==_orders[_ref].party, "Unauthorized access to orders");
        return _orders[_ref];
    }

    function getTrade(address _party, uint256 _timestamp) external view returns(ITrade.trade memory){
        require(msg.sender==owner() || msg.sender==_party, "Unauthorized access to trades");
        return _tradeRefs[_party][_timestamp];
    }

    function getTrades() external view returns(uint256[] memory){
        return _trades[msg.sender];
    }

    function removeTrade(address _party, uint256 _timestamp) public onlyOwner {
        for(uint256 i=0; i<_trades[_party].length; i++){
            if(_trades[_party][i]==_timestamp)
                delete _trades[_party][i];
        }
    }

    function revertTrade(
        bytes32 _orderRef,
        uint256 _qty
    ) external override {
        require(msg.sender==_balancerManager || msg.sender==owner(), "Unauthorized access");
        _orders[_orderRef].qty = _orders[_orderRef].qty + _qty;
        _orders[_orderRef].status = OrderStatus.Open;
        //push to order book
        if (_orders[_orderRef].otype == IOrder.OrderType.Limit) {
            if(_orders[_orderRef].tokenIn==_security)
                //sell order
                insertSellOrder(_orders[_orderRef].price, _orderRef);    
            else if(_orders[_orderRef].tokenIn==_currency)
                //buy order
                insertBuyOrder(_orders[_orderRef].price, _orderRef);
        } 
    }

    function orderFilled(bytes32 partyRef, bytes32 counterpartyRef, uint256 executionDate) external override {
        require(msg.sender==_balancerManager || msg.sender==owner(), "Unauthorized access");
        delete _orders[partyRef];
        delete _orders[counterpartyRef];
        delete _tradeRefs[_orders[partyRef].party][executionDate];
        delete _tradeRefs[_orders[counterpartyRef].party][executionDate];
    }

}