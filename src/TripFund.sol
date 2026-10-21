// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

/// @custom:oz-upgrades-unsafe-allow constructor
contract TripFund is Initializable {
    using SafeERC20 for IERC20;

    IERC20 public token;
    address public organizer;
    uint256 public goal;
    uint256 public deadline;
    mapping(address => uint256) public contributions;
    uint256 public totalRaised;
    bool public withdrawn;

    event Contributed(address indexed payer, address indexed beneficiary, uint256 amount);
    event Refunded(address indexed contributor, uint256 amount);
    event Withdrawn(address indexed organizer, uint256 amount);

    error InvalidToken();
    error InvalidOrganizer();
    error InvalidGoal();
    error InvalidDeadline();
    error InvalidAmount();
    error DeadlinePassed();
    error DeadlineNotReached();
    error NotOrganizer();
    error GoalNotReached();
    error GoalReached();
    error AlreadyWithdrawn();
    error NoContribution();
    error InvalidBeneficiary();

    constructor() {
        _disableInitializers();
    }

    function initialize(IERC20 token_, address organizer_, uint256 goal_, uint256 deadline_) public initializer {
        if (address(token_) == address(0)) revert InvalidToken();
        if (organizer_ == address(0)) revert InvalidOrganizer();
        if (goal_ == 0) revert InvalidGoal();
        if (deadline_ <= block.timestamp) revert InvalidDeadline();

        token = token_;
        organizer = organizer_;
        goal = goal_;
        deadline = deadline_;
    }

    function contribute(uint256 amount) external {
        _contribute(msg.sender, msg.sender, amount);
    }

    function _contribute(address payer, address beneficiary, uint256 amount) internal {
        if (beneficiary == address(0)) revert InvalidBeneficiary();
        if (amount == 0) revert InvalidAmount();
        if (block.timestamp >= deadline) revert DeadlinePassed();

        contributions[beneficiary] += amount;
        totalRaised += amount;
        token.safeTransferFrom(payer, address(this), amount);

        emit Contributed(payer, beneficiary, amount);
    }

    function withdraw() external {
        if (block.timestamp < deadline) revert DeadlineNotReached();
        if (totalRaised < goal) revert GoalNotReached();
        if (msg.sender != organizer) revert NotOrganizer();
        if (withdrawn) revert AlreadyWithdrawn();

        withdrawn = true;
        token.safeTransfer(organizer, totalRaised);
        emit Withdrawn(organizer, totalRaised);
    }

    function refund() external {
        if (block.timestamp < deadline) revert DeadlineNotReached();
        if (totalRaised >= goal) revert GoalReached();

        uint256 amount = contributions[msg.sender];
        if (amount == 0) revert NoContribution();

        contributions[msg.sender] = 0;
        token.safeTransfer(msg.sender, amount);
        emit Refunded(msg.sender, amount);
    }
}
