// Factory interface to create margin trading pools
//"SPDX-License-Identifier: BUSL1.1"

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

interface IMarginTradingPoolFactory {

    function create(
        string calldata name,
        string calldata symbol,
        address security,
        address currency,
        uint256 maxAmountsIn,
        uint256 tradeFeePercentage
    ) external returns (address);

}