// Factory interface to create pools of tokenized CFDs
//"SPDX-License-Identifier: BUSL1.1"

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

interface ICFDPoolFactory {

    function create(
        string calldata name,
        string calldata symbol,
        address security,
        address currency,
        uint256 minOrderSize,
        uint256 margin,
        uint256 tradeFeePercentage
    ) external returns (address);

}