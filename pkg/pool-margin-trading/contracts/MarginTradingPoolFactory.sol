// Factory to create margin trading pools for security tokens
// (c) Kallol Borah, 2022
//"SPDX-License-Identifier: BUSL1.1"

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";

import "@balancer-labs/v2-pool-utils/contracts/factories/BasePoolFactory.sol";
import "@balancer-labs/v2-pool-utils/contracts/factories/FactoryWidePauseWindow.sol";

import "./MarginTradingPool.sol";
import "./interfaces/IMarginTradingPoolFactory.sol";

contract MarginTradingPoolFactory is BasePoolFactory, FactoryWidePauseWindow {
    constructor(IVault vault, IProtocolFeePercentagesProvider protocolFeeProvider) 
        BasePoolFactory(vault, protocolFeeProvider, type(MarginTradingPool).creationCode)
    {
        // solhint-disable-previous-line no-empty-blocks
    }

    function create(
        IMarginTradingPoolFactory.FactoryPoolParams memory factoryPoolParams
    ) external returns (address) {
        
        (uint256 pauseWindowDuration, uint256 bufferPeriodDuration) = getPauseConfiguration();

        return
            _create(
                abi.encode(  
                    getVault(),
                    factoryPoolParams,
                    pauseWindowDuration,
                    bufferPeriodDuration,
                    msg.sender
                ));
    }

}