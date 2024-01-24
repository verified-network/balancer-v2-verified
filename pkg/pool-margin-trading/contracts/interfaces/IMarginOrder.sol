// Interface for orders
//"SPDX-License-Identifier: BUSL1.1"

pragma solidity 0.7.1;
pragma experimental ABIEncoderV2;

import "./ITrade.sol";
import "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v2-interfaces/contracts/solidity-utils/openzeppelin/IERC20.sol";

interface IMarginOrder {

    enum OrderType{ Market, Limit, Stop }

    enum OrderStatus{ Filled, PartlyFilled, Open, Cancelled, Expired }
    
    enum Order{ Buy, Sell } 

    struct order{
        address tokenIn;
        OrderType otype;
        OrderStatus status;
        address party;
        uint256 qty;
    }

    struct Params {
        OrderType trade;
        uint256 price;
    }

    function getPoolId() external view returns(bytes32);

    function getSecurity() external view returns (address);

    function getCurrency() external view returns (address);

    function getOrder(bytes32 _ref) external view returns(IMarginOrder.order memory);

    function getTrade(address _party, uint256 _timestamp) external view returns(ITrade.trade memory);

    function getTrades() external view returns(uint256[] memory);

    function getOrderRef() external view returns (bytes32[] memory);

    function reportTrade(bytes32 _ref, bytes32 _cref, uint256 securityTraded, uint256 currencyTraded, uint256 timestamp) external;

}