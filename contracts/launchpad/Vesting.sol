// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Vesting {
    using SafeERC20 for IERC20;

    IERC20 public immutable token;
    uint256 public immutable vestingStart;
    uint256 public immutable vestingDuration;

    mapping(address => uint256) public vestedAmounts;
    mapping(address => uint256) public claimedAmounts;

    event Vested(address indexed user, uint256 amount);
    event Claimed(address indexed user, uint256 amount);

    constructor(address _token, uint256 _vestingDuration) {
        token = IERC20(_token);
        vestingStart = block.timestamp;
        vestingDuration = _vestingDuration;
    }

    function vest(address user, uint256 amount) external {
        vestedAmounts[user] += amount;
        emit Vested(user, amount);
    }

    function claim() external {
        uint256 claimable = getClaimableAmount(msg.sender);
        require(claimable > 0, "No claimable tokens");

        claimedAmounts[msg.sender] += claimable;
        token.safeTransfer(msg.sender, claimable);

        emit Claimed(msg.sender, claimable);
    }

    function getClaimableAmount(address user) public view returns (uint256) {
        if (block.timestamp < vestingStart) return 0;
        uint256 elapsed = block.timestamp - vestingStart;
        uint256 vested = vestedAmounts[user] * elapsed / vestingDuration;
        return vested - claimedAmounts[user];
    }
}