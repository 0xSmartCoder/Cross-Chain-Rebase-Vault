// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract RebaseToken is ERC20, Ownable, AccessControl {
    error RebaseToken__InterestRateCanOnlyDecrease(uint256, uint256);
    event interestRateSet(uint256);

    uint256 private constant PRECISION_FACTOR = 1e27;
    uint256 private s_interestRate = 5e10;
    bytes32 private constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");
    mapping(address => uint256) private s_userInterestRate;
    mapping(address => uint256) private s_lastUpdatedTimestamp;
    constructor() ERC20("Rebase Token", "RBT") Ownable(msg.sender) {}

    function setInterestRate(uint256 newInterestRate) external onlyOwner {
        if (newInterestRate >= s_interestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease(newInterestRate, s_interestRate);
        }
        s_interestRate = newInterestRate;
        emit interestRateSet(newInterestRate);
    }

    function grantMintAndBurnRole(address _to) external onlyOwner {
        _grantRole(MINT_AND_BURN_ROLE, _to);
    }

    /**
    @notice Mints new tokens to a user's balance, including accrued interest.
    @param _to The address to which to mint tokens.
    @param _amount The amount of tokens to mint (principal amount).
     */
    function mint(
        address _to,
        uint256 _amount,
        uint256 _interestRate
    ) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccuredInterest(_to);
        s_userInterestRate[_to] = _interestRate;
        _mint(_to, _amount);
    }

    /**
    @notice Burns tokens from a user's balance, including accrued interest.
    @param _from The address from which to burn tokens.
    @param _amount The amount of tokens to burn (principal amount).
     */
    function burn(address _from, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        // If _amount is set to max uint256, we want to burn the user's entire balance including accrued interest.
        if (_amount == type(uint256).max) {
            /** 
            @notice we used balanceOf instead of super.balanceOf to get the user's balance 
            including accrued interest, so we can burn the entire balance if _amount is set to max uint256
            */
            _amount = balanceOf(_from);
        }
        _mintAccuredInterest(_from);
        _burn(_from, _amount);
    }

    /**
    @notice Transfers tokens from the sender to a recipient, including accrued interest.
    @param _recipient The address to which to transfer tokens.
    @param _amount The amount of tokens to transfer (principal amount).
     */
    function transfer(address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccuredInterest(msg.sender);
        _mintAccuredInterest(_recipient);

        if (_amount == type(uint256).max) {
            _amount = balanceOf(msg.sender);
        }

        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[msg.sender];
        }
        return super.transfer(_recipient, _amount);
    }

    function transferFrom(
        address _sender,
        address _recipient,
        uint256 _amount
    ) public override returns (bool) {
        _mintAccuredInterest(_sender);
        _mintAccuredInterest(_recipient);

        if (_amount == type(uint256).max) {
            _amount = balanceOf(_sender);
        }

        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[_sender];
        }
        return super.transferFrom(_sender, _recipient, _amount);
    }

    /**
    @notice Calculates the user's accumulated interest since the last update.
     -How this acctually works:
     1. Get the time elapsed since the last update for the user.
        2. Calculate the linear interest multiplier using the formula:
            linearInterest = PRECISION_FACTOR + (s_userInterestRate[user] * timeElapsed)
        3. Return the linear interest multiplier, which can be used to calculate the user's current balance including accrued interest.
        4. The balanceOf function uses this multiplier to return the user's dynamic balance, which includes both the principal and the accrued interest.
        5. The _mintAccuredInterest function is called before any minting or burning to ensure that the user's balance is updated with the accrued interest before any changes to the principal balance are made.
     */
    function _calculateUserAccumlatedInterestSinceLastUpdate(
        address _user
    ) internal view returns (uint256 linearInterest) {
        uint256 timeElapsed = block.timestamp - s_lastUpdatedTimestamp[_user];
        linearInterest = PRECISION_FACTOR + (s_userInterestRate[_user] * timeElapsed);
    }
    // 1,000,750,000,000,000
    // 2,001,500,000,000,000
    // 1,500,000,000,000
    // 0.0015

    /**
    @notice Returns the user's balance including accrued interest.
     -How this acctually works:
        1. Calls super.balanceOf(_user) to get the user's principal balance (ignoring interest).
            2. Calls _calculateUserAccumlatedInterestSinceLastUpdate(_user) to get the linear interest multiplier.
            3. Multiplies the principal balance by the linear interest multiplier and divides by PRECISION_FACTOR to get the user's current balance including accrued interest.
     */
    function balanceOf(address _user) public view override returns (uint256) {
        return
            (super.balanceOf(_user) * _calculateUserAccumlatedInterestSinceLastUpdate(_user)) /
            PRECISION_FACTOR;
    }

    /**  Brief Explanation of the Balance Calculation Logic:
         
     This function calculates the user's dynamic balance including accrued linear interest since
     the last update. Step by step explanation:
    
     (1) PRINCIPAL: super.balanceOf(user) returns the base ERC20 token balance (ignores interest).
         Example: 6 tokens = 6 * 10^18 = 6,000,000,000,000,000,000 smallest units
    
     (2) LINEAR INTEREST MULTIPLIER:
       linearInterest = PRECISION_FACTOR + (s_userInterestRate[user] * timeElapsed)

         Example values:
        - PRECISION_FACTOR = 1e18 = 1,000,000,000,000,000,000
         - s_userInterestRate[user] = 5e10
           - timeElapsed = 8 seconds
    
         Step by step:
           5e10 * 8 = 400,000,000,000
           Add PRECISION_FACTOR:
           1,000,000,000,000,000,000 + 400,000,000,000
           ≈ 1,000,400,000,000,000,000
    
         Multiplier = linearInterest / PRECISION_FACTOR
           ≈ 1.0000000004 (tiny increase for short time)
    
    
     (3) FINAL DYNAMIC BALANCE:
         balanceOf(user) = principal * linearInterest / PRECISION_FACTOR
    
         Example:
           6,000,000,000,000,000,000 * 1,000,000,400,000,000,000 / 1,000,000,000,000,000,000
           = 6,000,002,400,000,000,000
    
      RESULT:
     - 6 tokens in principal → small accrued interest (~0.0000024 tokens) in 8 seconds
     - balanceOf always returns *principal + accrued interest*
     - _mintAccuredInterest() mints this tiny interest before any new mint
    
      KEY POINTS:
     - _CalculateUserAccumlatedInterestSinceLastUpdate() only returns linearInterest
     - Use multiplier = linearInterest / PRECISION_FACTOR to compute actual balance
     - Works for any ERC20 token with 18 decimals
    */

    /**
    @notice Mints the accrued interest to the user's balance before any new minting or burning.
     -How this acctually works:
        1. Gets the previous principal balance of the user.
        2. Gets the current dynamic balance of the user (including accrued interest).
        3. Calculates the difference between current and previous balances (this is the accrued interest).
        4. Updates the last updated timestamp for the user.
        5. Mints the accrued interest to the user's balance.
     */
    function _mintAccuredInterest(address _user) internal {
        // Get the previous principal balance (ignoring interest)
        uint256 previousPrincipleBalance = super.balanceOf(_user);

        // Get the current balance including accrued interest
        uint256 currentBalance = balanceOf(_user);
        uint256 balanceIncreased = currentBalance - previousPrincipleBalance;

        s_lastUpdatedTimestamp[_user] = block.timestamp;
        _mint(_user, balanceIncreased);
    }

    function getUserInterestRate(address user) external view returns (uint256) {
        return s_userInterestRate[user];
    }

    function getInterestRate() external view returns (uint256) {
        return s_interestRate;
    }

    function getPrincipleBalanceOf(address _user) external view returns (uint256) {
        return super.balanceOf(_user);
    }
}

// ccip deployed: 0x455CcB6E196653D293456ccaddE259032fe19231
// ccip at arbi: 0x6a5c8A66Fa10fFa1e2Be30C56bf349Ea14f03841
