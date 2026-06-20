// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IRebaseToken} from "./interfaces/IRebaseToken.sol";
contract Vault {
    error Vault_ReedemFailed();

    event Deposit(address indexed user, uint256 _amount);
    event Reedem(address indexed user, uint256 _amount);

    IRebaseToken private immutable i_RebaseToken;

    constructor(IRebaseToken _rebaseToken) {
        i_RebaseToken = _rebaseToken;
    }

    receive() external payable {}

    function deposit() external payable {
        uint256 interestRate = i_RebaseToken.getInterestRate();
        i_RebaseToken.mint(msg.sender, msg.value, interestRate);
        emit Deposit(msg.sender, msg.value);
    }

    function reedem(uint256 _amount) external {
        uint256 userBalance = i_RebaseToken.balanceOf(msg.sender);
        if (_amount == type(uint256).max) {
            _amount = userBalance;
        } else {
            require(_amount <= userBalance, "Not enough balance");
        }

        i_RebaseToken.burn(msg.sender, _amount);

        uint256 vaultBalance = address(this).balance;
        uint256 payout = _amount > vaultBalance ? vaultBalance : _amount;

        (bool success, ) = payable(msg.sender).call{value: payout}("");
        if (!success) {
            revert Vault_ReedemFailed();
        }
        emit Reedem(msg.sender, _amount);
    }

    function getRebaseTokenAddress() external view returns (address) {
        return address(i_RebaseToken);
    }
}
