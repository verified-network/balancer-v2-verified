// Interface for trade
//"SPDX-License-Identifier: BUSL1.1"

pragma solidity 0.7.1;
pragma experimental ABIEncoderV2;

interface ITrade {

    struct trade{
        address partyAddress;
        bytes32 partyRef;
        bytes32 counterpartyRef;
        uint256 dt;
        uint256 securityTraded;
        uint256 currencyTraded;
    }

}