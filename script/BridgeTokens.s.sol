// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {IRouterClient} from "@ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import {
    IERC20
} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

contract BridgeTokensScript is Script {
    function sendMessage(
        address receiver,
        uint64 destinationChainSelector,
        address tokenToSendAddress,
        uint256 amountToSend,
        address link,
        address routerAddress
    ) public {
        vm.startBroadcast();
        Client.EVMTokenAmount[] memory tokenAmount = new Client.EVMTokenAmount[](1);
        tokenAmount[0] = Client.EVMTokenAmount({token: tokenToSendAddress, amount: amountToSend});

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: "",
            tokenAmounts: tokenAmount,
            feeToken: link,
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV2({gasLimit: 0, allowOutOfOrderExecution: false})
            )
        });

        uint256 fee = IRouterClient(routerAddress).getFee(destinationChainSelector, message);
        IERC20(link).approve(routerAddress, fee);
        IERC20(tokenToSendAddress).approve(routerAddress, amountToSend);

        IRouterClient(routerAddress).ccipSend(destinationChainSelector, message);

        vm.stopBroadcast();
    }
}
