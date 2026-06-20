//SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {MaliciousContract} from "./MaliciousContract.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";
contract RebaseTokenTest is Test {
    RebaseToken private rebaseToken;
    Vault private vault;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");

    function setUp() public {
        vm.startPrank(owner);
        rebaseToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        rebaseToken.grantMintAndBurnRole(address(vault));
        vm.stopPrank();
    }

    function addRewardToVault(uint256 reward)public{
     (bool success,) = payable(address(vault)).call{value: reward}("");

    }
    function testDepositLinear(uint256 amount) public {
 
        amount = bound(amount, 1 ether, 10 ether);
        vm.deal(user, amount);

        vm.startPrank(user);
        
        // (1) Deposit
        vault.deposit{value: amount}();
        
        // (2) check Rebase Token Balance
        uint256 startBalance = rebaseToken.balanceOf(user);
        console.log("startBalance:", startBalance);
        assertEq(startBalance, amount);
        
        // (3) warp time again and check the balance
        vm.warp(block.timestamp + 1 hours);
        uint256 middletBalance = rebaseToken.balanceOf(user);
        assertGt(middletBalance, startBalance);

        // (4) warp the time again and check the balance again 

        vm.warp(block.timestamp + 2 hours);
        uint256 endBalance = rebaseToken.balanceOf(user);
        assertGt(endBalance, middletBalance);

        assertGt(middletBalance, startBalance);
        assertGt(endBalance, middletBalance);
        // assertApproxEqAbs(endBalance - middletBalance, middletBalance - startBalance, 1);
        vm.stopPrank();
    }

    function testReedem(uint256 amount) public {
        amount = bound(amount, 1 ether, 10 ether);

        // (1) deposit
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();
        assertEq(rebaseToken.balanceOf(user), amount);

        // (2) reedem
        vault.reedem(type(uint256).max);
        assertEq(rebaseToken.balanceOf(user), 0);
        assertEq(address(user).balance, amount);
        console.log("User Expected Balance", address(user).balance);
        console.log("User Actual Balance", amount);
        vm.stopPrank();
    }

    function testReedemAfterTimePassed(uint256 depositAmount, uint256 time) public {
        time = bound(time, 1000, type(uint96).max);
        depositAmount = bound(depositAmount, 1e10, type(uint96).max);

        // (1) deposit
        vm.prank(user);
        vm.deal(user, depositAmount);
        vault.deposit{value: depositAmount}();

        // (2) warp the time
        vm.warp(block.timestamp + time);
        uint256 balance = rebaseToken.balanceOf(user);

        // add reward amount to vault
        vm.deal(owner, balance);
        vm.prank(owner);
        addRewardToVault(balance);

        // reedem
        vm.prank(user);
        vault.reedem(type(uint256).max);

        uint256 ethBalance = address(user).balance;
        assertEq(ethBalance, balance);
        assertGe(ethBalance, depositAmount);
        
    }

    function testTransfer(uint256 amount, uint256 amountToSend)public{
        amount = bound(amount, 1e6 + 1e6, type(uint96).max);
        amountToSend = bound(amountToSend, 1e6, amount - 1e6);

        // (1) deposit
        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();

        address user2 = makeAddr("user2");
        uint256 userBalance = rebaseToken.balanceOf(user);
        uint256 user2Balance = rebaseToken.balanceOf(user2);

        assertEq(userBalance, amount);
        assertEq(user2Balance, 0);

        // owner reduces the interest rate
        vm.prank(owner);
        rebaseToken.setInterestRate(4e10);

        // (2) transfer
        vm.prank(user);
        rebaseToken.transfer(user2, amountToSend);

        uint256 userBalanceAfterTransfer = rebaseToken.balanceOf(user);
        uint256 user2BalanceAfterTransfer = rebaseToken.balanceOf(user2);

        assertEq(userBalanceAfterTransfer, userBalance - amountToSend);
        assertEq(user2BalanceAfterTransfer, amountToSend);

        assertEq(rebaseToken.getUserInterestRate(user), 5e10);
        assertEq(rebaseToken.getUserInterestRate(user2), 5e10);
        assertEq(rebaseToken.getInterestRate(), 4e10);

    }

    function testCannotSetInterestRateIfNotOwner(uint256 newRate) public {
        newRate = bound(newRate, 0, type(uint96).max);
        vm.prank(user);
        vm.expectPartialRevert(bytes4(Ownable.OwnableUnauthorizedAccount.selector));
        rebaseToken.setInterestRate(newRate);
    }

    function testCannotMint(uint256 amount) public {
        amount = bound(amount, 1e6, type(uint96).max);
        uint256 interestRate = IRebaseToken(address(rebaseToken)).getInterestRate();
        vm.prank(user);
        vm.expectPartialRevert(bytes4(IAccessControl.AccessControlUnauthorizedAccount.selector));
        rebaseToken.mint(user, amount, interestRate);

        vm.prank(user);
        vm.expectPartialRevert(bytes4(IAccessControl.AccessControlUnauthorizedAccount.selector));
        rebaseToken.burn(user, amount);
    }

    function testPrincipleAmount(uint256 amount) public  {
        amount = bound (amount, 1e6, type(uint96).max);
        vm.prank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();
        assertEq(rebaseToken.getPrincipleBalanceOf(user), amount);

        vm.warp(block.timestamp + 5 hours);
        assertEq(rebaseToken.getPrincipleBalanceOf(user), amount);

    }

    function testGetRebaseTokenAddress() public view {
        assertEq(vault.getRebaseTokenAddress(), address(rebaseToken));
    }

    function testInterestRateCanOnlyDecrease(uint256 newRate) public {
        uint256 initialInterestRate = rebaseToken.getInterestRate();
        newRate = bound(newRate, initialInterestRate, type(uint96).max);
        vm.prank(owner);
        vm.expectPartialRevert(bytes4(RebaseToken.RebaseToken__InterestRateCanOnlyDecrease.selector));
        rebaseToken.setInterestRate(newRate);

        assertEq(rebaseToken.getInterestRate(), initialInterestRate);

    }

    function testTransferFrom(uint256 amount) public {
        amount = bound(amount, 1e6, type(uint96).max);
        address user2 = makeAddr("user2");

        // (1) deposit
        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();

        // (2) approve and transferFrom
        vm.prank(user);
        rebaseToken.approve(user2, amount);

        vm.prank(user2);
        rebaseToken.transferFrom(user, user2, type(uint256).max);

        assertEq(rebaseToken.balanceOf(user), 0);
        assertEq(rebaseToken.balanceOf(user2), amount);
    }

    function testReedemRevertsIfTransferFailed() public {

        MaliciousContract maliciousContract = new MaliciousContract();
        vm.deal(address(maliciousContract), 1 ether);
        vm.prank(address(maliciousContract));
        vault.deposit{value: 1 ether}();

        // Remove vault ETH so transfer fails
        vm.deal(owner, 1 ether);
        vm.prank(owner);
        addRewardToVault(0.001 ether);

        vm.prank(address(maliciousContract));
        vm.expectPartialRevert(bytes4(Vault.Vault_ReedemFailed.selector));
        vault.reedem(type(uint256).max);

    }

    function testReedemRevertsIfAmountExceedsBalance() public {
        vm.prank(user);
        vm.deal(user, 1 ether);
        vault.deposit{value: 1 ether}();
        vm.prank(user);
        vm.expectRevert("Not enough balance");
        vault.reedem(2 ether);
        
    }

    function testRedeemWhenVaultHasLessETH() public{
        vm.prank(user);
        vm.deal(user, 10 ether);
        vault.deposit{value: 10 ether}();

        // add reward to vault less than user's balance
        vm.deal(owner, 1 ether);
        vm.prank(owner);
        addRewardToVault(1 ether);

        vm.prank(user);
        vault.reedem(10 ether);
    }

    function testTransferConditions() public {

        address user2 = makeAddr("user2");

         // (1) deposit
        vm.prank(user);
        vm.deal(user, 10 ether);
        vault.deposit{value: 10 ether}();

        rebaseToken.transfer(user2, type(uint256).max);
    }

    function testHitBurnWithLargeAmount() public {
        // Just for testing we will giving Mint&Burn role to user, so we can call burn function directly without going through the vault
        vm.prank(owner);
        rebaseToken.grantMintAndBurnRole(user);

        // (1) deposit
        vm.prank(user);
        vm.deal(user, 0.5 ether);
        vault.deposit{value: 0.5 ether}();

        vm.prank(user);
        rebaseToken.burn(user, type(uint256).max);
        assertEq(rebaseToken.balanceOf(user), 0);
    }
}