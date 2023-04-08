// Interface for orders
//"SPDX-License-Identifier: BUSL1.1"

pragma solidity 0.7.1;

import "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v2-interfaces/contracts/solidity-utils/openzeppelin/IERC20.sol";

interface IOrder {

    enum OrderType{ Market, Limit, Stop }

    enum OrderStatus{ Filled, PartlyFilled, Open, Cancelled, Expired }
    
    enum Order{ Buy, Sell } 

    struct order{
        address party;
        address tokenIn;
        OrderType otype;
        OrderStatus status;
        uint256 qty;        
    }

    struct Params {
        OrderType trade;
        uint256 price;
    }

    function getPoolId() external view returns(bytes32);

    function getSecurity() external view returns (address);

    function getCurrency() external view returns (address);

    function orderFilled(bytes32 partyRef, bytes32 counterpartyRef, uint256 executionDate) external;

    function revertTrade(bytes32 _orderRef, uint256 _qty, uint256 _price) external;
    
}