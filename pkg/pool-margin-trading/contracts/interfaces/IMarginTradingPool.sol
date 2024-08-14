//Margin trading pool interface 
//"SPDX-License-Identifier: BUSL1.1"

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

interface IMarginTradingPool {

    function getPoolId() external view returns(bytes32);
    
    function getSecurity() external view returns (address);

    function getCurrency() external view returns (address);

    function getMinOrderSize() external view returns(uint256);

    function getOrderbook() external view returns (address);

    function getMargin() external view returns(uint256);

    function getCollateral() external view returns(uint256);

    function getFee() external view returns(uint256);

    function getManager() external view returns(address);
}

