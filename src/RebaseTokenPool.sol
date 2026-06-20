//SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {TokenPool} from "@ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {Pool} from "@ccip/contracts/src/v0.8/ccip/libraries/Pool.sol";
import {IRebaseToken} from "./interfaces/IRebaseToken.sol";
import {
    IERC20
} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
contract RebaseTokenPool is TokenPool {
    constructor(
        IERC20 _token,
        address[] memory _allowList,
        address rnmProxy,
        address router
    ) TokenPool(_token, _allowList, rnmProxy, router) {}

    function lockOrBurn(
        Pool.LockOrBurnInV1 calldata lockOrBurnInV1
    ) external virtual override returns (Pool.LockOrBurnOutV1 memory lockOrBurnOutV1) {
        _validateLockOrBurn(lockOrBurnInV1);

        uint256 interestRate = IRebaseToken(address(i_token)).getUserInterestRate(
            lockOrBurnInV1.originalSender
        );

        IRebaseToken(address(i_token)).burn(address(this), lockOrBurnInV1.amount);

        lockOrBurnOutV1 = Pool.LockOrBurnOutV1({
            destTokenAddress: getRemoteToken(lockOrBurnInV1.remoteChainSelector),
            destPoolData: abi.encode(interestRate)
        });
    }

    function releaseOrMint(
        Pool.ReleaseOrMintInV1 calldata releaseOrMintInV1
    ) external returns (Pool.ReleaseOrMintOutV1 memory releaseOrMintOutV1) {
        _validateReleaseOrMint(releaseOrMintInV1);

        uint256 interestRate = abi.decode(releaseOrMintInV1.sourcePoolData, (uint256));

        IRebaseToken(address(i_token)).mint(
            releaseOrMintInV1.receiver,
            releaseOrMintInV1.amount,
            interestRate
        );
        releaseOrMintOutV1 = Pool.ReleaseOrMintOutV1({destinationAmount: releaseOrMintInV1.amount});
    }
}
