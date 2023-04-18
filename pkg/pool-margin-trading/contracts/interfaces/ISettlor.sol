// Interface for creating secondary trading pools and settling secondary trades
//"SPDX-License-Identifier: BUSL1.1"

pragma solidity 0.7.1;
pragma experimental ABIEncoderV2;

import "./ITrade.sol";
import "./IMarginOrder.sol";

interface ISettlor {

    function requestSettlement(ITrade.trade memory tradeToReport, IMarginOrder orderbook) external;

    function getTrade(bytes32 ref) external view returns(uint256 b, uint256 a);

}