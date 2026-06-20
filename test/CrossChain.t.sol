 //SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {RebaseTokenPool} from "../src/RebaseTokenPool.sol";
import {Vault} from "../src/Vault.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {
    CCIPLocalSimulatorFork,
    Register
} from "@chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";
import {
    RegistryModuleOwnerCustom
} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {
    TokenAdminRegistry
} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";
import {Client} from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "@ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";
import {TokenPool} from "@ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {RateLimiter} from "@ccip/contracts/src/v0.8/ccip/libraries/RateLimiter.sol";
import {IOwner} from "@ccip/contracts/src/v0.8/ccip/interfaces/IOwner.sol";
import {
    IERC20
} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

contract CrossChainTest is Test {
    address public Owner = address(0xABCD);
    address public user = address(0x1234);
    uint256 Send_Value = 1 ether;

    RebaseToken sepoliaRebaseToken;
    RebaseTokenPool sepoliaRebaseTokenPool;

    RebaseToken arbSepoliaRebaseToken;
    RebaseTokenPool arbSepoliaRebaseTokenPool;

    CCIPLocalSimulatorFork public ccipLocalSimulatorFork;
    Vault vault;

    uint256 arbSepolia;
    uint256 sepolia;

    Register.NetworkDetails sepoliaNetworkDetails;
    Register.NetworkDetails arbSepoliaNetworkDetails;

    TokenAdminRegistry tokenAdminRegistrySepolia;
    TokenAdminRegistry tokenAdminRegistryArbSepolia;

    RegistryModuleOwnerCustom registryModuleOwnerCustomSepolia;
    RegistryModuleOwnerCustom registryModuleOwnerCustomArbSepolia;

    function setUp() public {
        address[] memory allowList = new address[](1);
        allowList[0] = user;
        sepolia = vm.createSelectFork("sepolia");
        arbSepolia = vm.createFork("arbSepolia");

        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork));

        sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        vm.startPrank(Owner);
        sepoliaRebaseToken = new RebaseToken();

        sepoliaRebaseTokenPool = new RebaseTokenPool(
            IERC20(address(sepoliaRebaseToken)),
            allowList,
            sepoliaNetworkDetails.rmnProxyAddress,
            sepoliaNetworkDetails.routerAddress
        );

        vault = new Vault(IRebaseToken(address(sepoliaRebaseToken)));
        vm.deal(address(vault), 10 ether);

        // grant mint and burn role to pool and vault on sepolia
        sepoliaRebaseToken.grantMintAndBurnRole(address(sepoliaRebaseTokenPool));
        sepoliaRebaseToken.grantMintAndBurnRole(address(vault));

        // claim role on sepolia
        registryModuleOwnerCustomSepolia = RegistryModuleOwnerCustom(
            sepoliaNetworkDetails.registryModuleOwnerCustomAddress
        );
        registryModuleOwnerCustomSepolia.registerAdminViaOwner(address(sepoliaRebaseToken));

        tokenAdminRegistrySepolia = TokenAdminRegistry(
            sepoliaNetworkDetails.tokenAdminRegistryAddress
        );

        tokenAdminRegistrySepolia.acceptAdminRole(address(sepoliaRebaseToken));

        // link token with pool on sepolia
        tokenAdminRegistrySepolia.setPool(
            address(sepoliaRebaseToken),
            address(sepoliaRebaseTokenPool)
        );

        console.log(tokenAdminRegistrySepolia.getPool(address(sepoliaRebaseToken)));
        vm.stopPrank();

        vm.selectFork(arbSepolia);
        vm.startPrank(Owner);

        arbSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        // deploy token and pool on arb sepolia
        arbSepoliaRebaseToken = new RebaseToken();

        arbSepoliaRebaseTokenPool = new RebaseTokenPool(
            IERC20(address(arbSepoliaRebaseToken)),
            allowList,
            arbSepoliaNetworkDetails.rmnProxyAddress,
            arbSepoliaNetworkDetails.routerAddress
        );

        // grant mint and burn role to pool on arb sepolia
        arbSepoliaRebaseToken.grantMintAndBurnRole(address(arbSepoliaRebaseTokenPool));

        // claim role on arb sepolia
        registryModuleOwnerCustomArbSepolia = RegistryModuleOwnerCustom(
            arbSepoliaNetworkDetails.registryModuleOwnerCustomAddress
        );

        registryModuleOwnerCustomArbSepolia.registerAdminViaOwner(address(arbSepoliaRebaseToken));

        // accept role on arb sepolia
        tokenAdminRegistryArbSepolia = TokenAdminRegistry(
            arbSepoliaNetworkDetails.tokenAdminRegistryAddress
        );
        tokenAdminRegistryArbSepolia.acceptAdminRole(address(arbSepoliaRebaseToken));

        // link token with pool on arb sepolia
        tokenAdminRegistryArbSepolia.setPool(
            address(arbSepoliaRebaseToken),
            address(arbSepoliaRebaseTokenPool)
        );

        console.log(tokenAdminRegistryArbSepolia.getPool(address(arbSepoliaRebaseToken)));

        vm.stopPrank();
    }

    function configureTokenPool(
        uint256 fork,
        TokenPool localPool,
        TokenPool remotePool,
        IRebaseToken remoteToken,
        Register.NetworkDetails memory remoteNetworkDetails
    ) public {
        vm.selectFork(fork);
        vm.prank(Owner);
        TokenPool.ChainUpdate[] memory chainUpdates = new TokenPool.ChainUpdate[](1);
        chainUpdates[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteNetworkDetails.chainSelector,
            allowed: true,
            remotePoolAddress: abi.encode(address(remotePool)),
            remoteTokenAddress: abi.encode(address(remoteToken)),
            outboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0}),
            inboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0})
        });
        localPool.applyChainUpdates(chainUpdates);
    }

    function BridgeToken(
        uint256 amountToBridge,
        uint256 localFork,
        uint256 remoteFork,
        Register.NetworkDetails memory localNetwork,
        Register.NetworkDetails memory remoteNetwork,
        RebaseToken localToken,
        RebaseToken remoteToken
    ) public {
        vm.selectFork(localFork);
        vm.startPrank(user);

        Client.EVMTokenAmount[] memory tokenAmount = new Client.EVMTokenAmount[](1);
        tokenAmount[0] = Client.EVMTokenAmount({
            token: address(localToken),
            amount: amountToBridge
        });

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(user),
            data: "",
            tokenAmounts: tokenAmount,
            feeToken: localNetwork.linkAddress,
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV2({gasLimit: 500_000, allowOutOfOrderExecution: false})
            )
        });

        uint256 fee = IRouterClient(localNetwork.routerAddress).getFee(
            remoteNetwork.chainSelector,
            message
        );

        vm.stopPrank();

        ccipLocalSimulatorFork.requestLinkFromFaucet(user, fee);

        vm.startPrank(user);
        IERC20(localNetwork.linkAddress).approve(localNetwork.routerAddress, fee);
        IERC20(address(localToken)).approve(localNetwork.routerAddress, amountToBridge);

        uint256 userBalanceBefore = localToken.balanceOf(user);

        IRouterClient(localNetwork.routerAddress).ccipSend(remoteNetwork.chainSelector, message);

        console.log("User balance after send", localToken.balanceOf(user));
        console.log(
            "Pool balance after send",
            localToken.balanceOf(address(sepoliaRebaseTokenPool))
        );
        console.log("Pool total supply", localToken.totalSupply());

        uint256 userBalanceAfter = localToken.balanceOf(user);
        uint256 localUserInterestRate = localToken.getUserInterestRate(user);
        assertEq(userBalanceAfter, userBalanceBefore - amountToBridge);
        console.log("Remote total supply", remoteToken.totalSupply());
        vm.stopPrank();

        vm.selectFork(remoteFork);
        vm.warp(block.timestamp + 25 minutes);
        uint256 userRemoteBalanceBefore = remoteToken.balanceOf(user);
        console.log("Remote balance before routing:", userRemoteBalanceBefore);

        vm.selectFork(localFork);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(remoteFork);

        console.log("Remote total supply after routing", remoteToken.totalSupply());

        uint256 userRemoteBalanceAfter = remoteToken.balanceOf(user);
        uint256 remoteUserInterestRate = remoteToken.getUserInterestRate(user);
        assertEq(userRemoteBalanceAfter, userRemoteBalanceBefore + amountToBridge);
        assertEq(localUserInterestRate, remoteUserInterestRate);
    }

    function testBridgeAllToken() public {
        configureTokenPool(
            sepolia,
            sepoliaRebaseTokenPool,
            arbSepoliaRebaseTokenPool,
            IRebaseToken(address(arbSepoliaRebaseToken)),
            arbSepoliaNetworkDetails
        );

        configureTokenPool(
            arbSepolia,
            arbSepoliaRebaseTokenPool,
            sepoliaRebaseTokenPool,
            IRebaseToken(address(sepoliaRebaseToken)),
            sepoliaNetworkDetails
        );

        vm.selectFork(sepolia);
        vm.prank(user);
        vm.deal(user, Send_Value);
        Vault(payable(address(vault))).deposit{value: Send_Value}();
        console.log("User balance after deposit:", sepoliaRebaseToken.balanceOf(user));
        BridgeToken(
            Send_Value,
            sepolia,
            arbSepolia,
            sepoliaNetworkDetails,
            arbSepoliaNetworkDetails,
            sepoliaRebaseToken,
            arbSepoliaRebaseToken
        );

        vm.selectFork(arbSepolia);
        vm.warp(block.timestamp + 20 minutes);
        BridgeToken(arbSepoliaRebaseToken.balanceOf(user), arbSepolia, sepolia, arbSepoliaNetworkDetails, sepoliaNetworkDetails, arbSepoliaRebaseToken, sepoliaRebaseToken);
    }
}
