// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {TripFund} from "../src/TripFund.sol";
import {MockToken} from "../src/MockToken.sol";

contract FailingToken is MockToken {
    bool public failTransfer;
    bool public failTransferFrom;

    function setFailures(bool transfer_, bool transferFrom_) external {
        failTransfer = transfer_;
        failTransferFrom = transferFrom_;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (failTransfer) return false;
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (failTransferFrom) return false;
        return super.transferFrom(from, to, amount);
    }
}

contract TripFundTest is Test {
    address internal organizer = makeAddr("organizer");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal stranger = makeAddr("stranger");

    MockToken internal token;
    TripFund internal fund;
    TripFund internal implementation;
    uint256 internal constant DEADLINE = 2_000;

    event Contributed(address indexed payer, address indexed beneficiary, uint256 amount);
    event Refunded(address indexed contributor, uint256 amount);
    event Withdrawn(address indexed organizer, uint256 amount);

    function setUp() public {
        vm.warp(1_000);
        token = new MockToken();
        implementation = new TripFund();
        fund = _deploy(token, organizer, 100, DEADLINE);
        token.mint(alice, 200);
        token.mint(bob, 200);
    }

    function _deploy(IERC20 token_, address organizer_, uint256 goal_, uint256 deadline_) internal returns (TripFund) {
        bytes memory data = abi.encodeCall(TripFund.initialize, (token_, organizer_, goal_, deadline_));
        return TripFund(address(new TransparentUpgradeableProxy(address(implementation), stranger, data)));
    }

    function _contribute(address who, uint256 amount) internal {
        vm.startPrank(who);
        token.approve(address(fund), amount);
        fund.contribute(amount);
        vm.stopPrank();
    }

    function testInitializationValidationAndLock() public {
        vm.expectRevert(TripFund.InvalidToken.selector);
        _deploy(IERC20(address(0)), organizer, 100, DEADLINE);

        vm.expectRevert(TripFund.InvalidOrganizer.selector);
        _deploy(token, address(0), 100, DEADLINE);

        vm.expectRevert(TripFund.InvalidGoal.selector);
        _deploy(token, organizer, 0, DEADLINE);

        vm.expectRevert(TripFund.InvalidDeadline.selector);
        _deploy(token, organizer, 100, block.timestamp);

        vm.expectRevert();
        implementation.initialize(token, organizer, 100, DEADLINE);

        vm.expectRevert();
        fund.initialize(token, organizer, 100, DEADLINE);
    }

    function testContributionsAndFailuresRollback() public {
        vm.prank(alice);
        token.approve(address(fund), 60);
        vm.expectEmit(true, true, false, true, address(fund));
        emit Contributed(alice, alice, 40);
        vm.prank(alice);
        fund.contribute(40);
        vm.prank(alice);
        fund.contribute(20);
        _contribute(bob, 30);

        assertEq(fund.contributions(alice), 60);
        assertEq(fund.contributions(bob), 30);
        assertEq(fund.totalRaised(), 90);
        assertEq(token.balanceOf(address(fund)), 90);
        assertEq(token.balanceOf(alice), 140);
        assertEq(token.balanceOf(bob), 170);

        vm.prank(alice);
        vm.expectRevert(TripFund.InvalidAmount.selector);
        fund.contribute(0);
        vm.prank(alice);
        vm.expectRevert();
        fund.contribute(1);

        token.mint(stranger, 1);
        vm.prank(stranger);
        token.approve(address(fund), 2);
        vm.prank(stranger);
        vm.expectRevert();
        fund.contribute(2);

        assertEq(fund.contributions(alice), 60);
        assertEq(fund.contributions(bob), 30);
        assertEq(fund.contributions(stranger), 0);
        assertEq(fund.totalRaised(), 90);
        assertEq(token.balanceOf(address(fund)), 90);
        assertEq(token.balanceOf(alice), 140);
        assertEq(token.balanceOf(bob), 170);
        assertEq(token.balanceOf(stranger), 1);
    }

    function testDeadlineBoundaryAndEarlyPayouts() public {
        _contribute(alice, 100);
        vm.prank(organizer);
        vm.expectRevert(TripFund.DeadlineNotReached.selector);
        fund.withdraw();
        vm.prank(alice);
        vm.expectRevert(TripFund.DeadlineNotReached.selector);
        fund.refund();

        vm.warp(DEADLINE - 1);
        _contribute(bob, 1);
        vm.warp(DEADLINE);
        vm.prank(bob);
        vm.expectRevert(TripFund.DeadlinePassed.selector);
        fund.contribute(1);
        assertEq(fund.totalRaised(), 101);
    }

    function testExactGoalWithdrawOnlyOnce() public {
        _contribute(alice, 40);
        _contribute(bob, 60);
        vm.warp(DEADLINE);

        vm.prank(stranger);
        vm.expectRevert(TripFund.NotOrganizer.selector);
        fund.withdraw();
        vm.prank(alice);
        vm.expectRevert(TripFund.GoalReached.selector);
        fund.refund();

        vm.expectEmit(true, false, false, true, address(fund));
        emit Withdrawn(organizer, 100);
        vm.prank(organizer);
        fund.withdraw();
        assertEq(token.balanceOf(organizer), 100);
        assertEq(token.balanceOf(address(fund)), 0);
        assertEq(fund.totalRaised(), 100);
        assertTrue(fund.withdrawn());

        vm.prank(organizer);
        vm.expectRevert(TripFund.AlreadyWithdrawn.selector);
        fund.withdraw();
    }

    function testAboveGoalAndDirectTransferRemain() public {
        _contribute(alice, 90);
        _contribute(bob, 30);
        vm.prank(alice);
        token.transfer(address(fund), 7);
        assertEq(fund.totalRaised(), 120);
        assertEq(token.balanceOf(address(fund)), 127);

        vm.warp(DEADLINE);
        vm.prank(organizer);
        fund.withdraw();
        assertEq(token.balanceOf(organizer), 120);
        assertEq(token.balanceOf(address(fund)), 7);
        assertEq(fund.totalRaised(), 120);
    }

    function testBelowGoalIndependentRefundsAndDirectTransfer() public {
        _contribute(alice, 40);
        _contribute(bob, 30);
        vm.prank(alice);
        token.transfer(address(fund), 5);
        assertEq(fund.totalRaised(), 70);

        vm.warp(DEADLINE);
        vm.prank(organizer);
        vm.expectRevert(TripFund.GoalNotReached.selector);
        fund.withdraw();
        vm.prank(stranger);
        vm.expectRevert(TripFund.NoContribution.selector);
        fund.refund();

        vm.expectEmit(true, false, false, true, address(fund));
        emit Refunded(alice, 40);
        vm.prank(alice);
        fund.refund();
        assertEq(fund.contributions(alice), 0);
        assertEq(fund.contributions(bob), 30);
        assertEq(token.balanceOf(alice), 195);

        vm.prank(alice);
        vm.expectRevert(TripFund.NoContribution.selector);
        fund.refund();
        vm.prank(bob);
        fund.refund();
        assertEq(fund.contributions(bob), 0);
        assertEq(token.balanceOf(bob), 200);
        assertEq(fund.totalRaised(), 70);
        assertEq(token.balanceOf(address(fund)), 5);
    }

    function testFalseTransfersRevertAndRestoreAccounting() public {
        FailingToken badToken = new FailingToken();
        TripFund badFund = _deploy(badToken, organizer, 50, DEADLINE);
        badToken.mint(alice, 100);
        vm.prank(alice);
        badToken.approve(address(badFund), 100);

        badToken.setFailures(false, true);
        vm.prank(alice);
        vm.expectRevert();
        badFund.contribute(40);
        assertEq(badFund.totalRaised(), 0);
        assertEq(badFund.contributions(alice), 0);
        assertEq(badToken.balanceOf(alice), 100);
        assertEq(badToken.balanceOf(address(badFund)), 0);

        badToken.setFailures(false, false);
        vm.prank(alice);
        badFund.contribute(40);
        badToken.setFailures(true, false);
        vm.warp(DEADLINE);
        vm.prank(alice);
        vm.expectRevert();
        badFund.refund();
        assertEq(badFund.contributions(alice), 40);
        assertEq(badFund.totalRaised(), 40);
        assertEq(badToken.balanceOf(address(badFund)), 40);

        badToken.setFailures(false, false);
        vm.prank(alice);
        badFund.refund();
        assertEq(badToken.balanceOf(alice), 100);
    }

    function testRevertedWithdrawRestoresWithdrawnFlag() public {
        FailingToken badToken = new FailingToken();
        TripFund badFund = _deploy(badToken, organizer, 40, DEADLINE);
        badToken.mint(alice, 40);
        vm.startPrank(alice);
        badToken.approve(address(badFund), 40);
        badFund.contribute(40);
        vm.stopPrank();

        badToken.setFailures(true, false);
        vm.warp(DEADLINE);
        vm.prank(organizer);
        vm.expectRevert();
        badFund.withdraw();
        assertFalse(badFund.withdrawn());
        assertEq(badFund.totalRaised(), 40);
        assertEq(badToken.balanceOf(address(badFund)), 40);

        badToken.setFailures(false, false);
        vm.prank(organizer);
        badFund.withdraw();
        assertEq(badToken.balanceOf(organizer), 40);
    }
}
