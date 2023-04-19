// Factory interface to create margin trading pools
//"SPDX-License-Identifier: BUSL1.1"

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

interface IMarginTradingPoolFactory {

    struct FactoryPoolParams{
        string name;
        string symbol;
        address security;
        bytes32 securityType;
        address currency;
        bytes32 cficode;
        uint256 minOrderSize;
        uint256 margin;
        uint256 collateral;
        uint256 tradeFeePercentage;
    }

    function create(
        FactoryPoolParams memory params
    ) external returns (address);

}