// Interface for trade
//"SPDX-License-Identifier: BUSL1.1"

pragma solidity 0.7.1;
pragma experimental ABIEncoderV2;

import "./IOrder.sol";

interface ITrade {

    struct trade{
        bytes32 partyRef;
        uint256 partyAmount;
        address partyAddress;
        bytes32 counterpartyRef;
        uint256 counterpartyAmount;
        uint256 price;
        uint256 dt;
    }

}