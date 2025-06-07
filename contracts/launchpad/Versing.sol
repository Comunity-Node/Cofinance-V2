// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

contract Vesting is Ownable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    IERC20 public immutable token;
    uint256 public immutable vestingStart;
    uint256 public immutable vestingDuration;

    mapping(address => uint256) public vestedAmounts;
    mapping(address => uint256) public claimedAmounts;

    event Vested(address indexed user, uint256 amount);
    event Claimed(address indexed user, uint256 amount);

    constructor(address _token, uint256 _vestingDuration) Ownable(msg.sender) {
        require(_token != address(0), "Invalid token address");
        require(_vestingDuration > 0, "Invalid vesting duration");
        token = IERC20(_token);
        vestingStart = block.timestamp;
        vestingDuration = _vestingDuration;
    }

    function vest(address user, uint256 amount) external onlyOwner {
        require(user != address(0), "Invalid user address");
        require(amount > 0, "Invalid amount");
        vestedAmounts[user] = vestedAmounts[user] + amount;
        emit Vested(user, amount);
    }

    function claim() external {
        uint256 claimable = getClaimableAmount(msg.sender);
        require(claimable > 0, "No claimable tokens");

        claimedAmounts[msg.sender] = claimedAmounts[msg.sender] + claimable;
        token.safeTransfer(msg.sender, claimable);
        emit Claimed(msg.sender, claimable);
    }

    function getClaimableAmount(address user) public view returns (uint256) {
        if (block.timestamp < vestingStart) return 0;
        uint256 elapsed = Math.min(block.timestamp - vestingStart, vestingDuration);
        uint256 vested = vestedAmounts[user] * elapsed / vestingDuration;
        return vested > claimedAmounts[user] ? vested - claimedAmounts[user] : 0;
    }
}