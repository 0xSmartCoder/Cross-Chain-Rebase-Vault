// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

// RateLimiter struct jo aapke contract mein hai
library RateLimiter {
    struct Config {
        bool isRateLimited;
        uint128 refillTokensPerSubInterval;
        uint128 bucketCapacity;
    }
}

// Target Contract Interface
interface IPool {
    struct ChainUpdate {
        uint64 remoteChainSelector;
        bool allowed;
        bytes remotePoolAddress;
        bytes remoteTokenAddress;
        RateLimiter.Config outboundRateLimiterConfig;
        RateLimiter.Config inboundRateLimiterConfig;
    }
    function applyChainUpdates(ChainUpdate[] calldata chains) external;
}

contract ApplyUpdates is Script {
    function applyUpdates(
        uint64 remoteChainSelector,
        address poolAddress,
        address tokenAddress
    ) external {
        vm.startBroadcast();

        IPool pool = IPool(poolAddress);

        IPool.ChainUpdate[] memory updates = new IPool.ChainUpdate[](1);

        updates[0] = IPool.ChainUpdate({
            remoteChainSelector: remoteChainSelector,
            allowed: true,
            remotePoolAddress: abi.encode(poolAddress),
            remoteTokenAddress: abi.encode(tokenAddress),
            outboundRateLimiterConfig: RateLimiter.Config(false, 0, 0),
            inboundRateLimiterConfig: RateLimiter.Config(false, 0, 0)
        });

        pool.applyChainUpdates(updates);

        vm.stopBroadcast();
    }
}
