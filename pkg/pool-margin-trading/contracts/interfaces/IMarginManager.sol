// Interface for creating margin trading pools and settling offchain orders matched
//"SPDX-License-Identifier: BUSL1.1"

pragma solidity 0.7.1;
pragma experimental ABIEncoderV2;

import "./ITrade.sol";
import "./IMarginOrder.sol";

interface IMarginManager {

    function requestSettlement(ITrade.trade memory tradeToReport, IMarginOrder orderbook) external;

}