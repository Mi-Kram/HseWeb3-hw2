// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {TripFund} from "../src/TripFund.sol";
import {MockToken} from "../src/MockToken.sol";

contract TripFund2Test is Test {
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address organizer = makeAddr("organizer");
    address stranger = makeAddr("stranger");

    MockToken token;
    TripFund fund;
    uint256 constant DEADLINE = 2_000;

    function setUp() public {
        vm.warp(1_000);
        token = new MockToken();
        TripFund implementation = new TripFund();
        bytes memory data = abi.encodeCall(TripFund.initialize, (IERC20(token), organizer, 100, DEADLINE));
        fund = TripFund(address(new TransparentUpgradeableProxy(address(implementation), stranger, data)));
        token.mint(alice, 200);
        token.mint(bob, 200);
    }

    function contribute(address user, uint256 amount) internal {
        vm.startPrank(user);
        token.approve(address(fund), amount);
        fund.contribute(amount);
        vm.stopPrank();
    }

    function testInitializationAndRepeatCall() public {
        TripFund implementation = new TripFund();
        vm.expectRevert();
        implementation.initialize(token, organizer, 100, DEADLINE);
        vm.expectRevert();
        fund.initialize(token, organizer, 100, DEADLINE);

        vm.expectRevert(TripFund.InvalidGoal.selector);
        new TransparentUpgradeableProxy(
            address(implementation),
            stranger,
            abi.encodeCall(TripFund.initialize, (IERC20(token), organizer, 0, DEADLINE))
        );
    }

    function testContributionsAndDeadline() public {
        vm.prank(alice);
        token.approve(address(fund), 60);
        vm.prank(alice);
        fund.contribute(40);
        vm.prank(alice);
        fund.contribute(20);
        contribute(bob, 30);

        assertEq(fund.contributions(alice), 60);
        assertEq(fund.contributions(bob), 30);
        assertEq(fund.totalRaised(), 90);
        assertEq(token.balanceOf(address(fund)), 90);

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
        assertEq(fund.contributions(stranger), 0);
        assertEq(fund.totalRaised(), 90);
        assertEq(token.balanceOf(address(fund)), 90);

        vm.prank(organizer);
        vm.expectRevert(TripFund.DeadlineNotReached.selector);
        fund.withdraw();
        vm.prank(alice);
        vm.expectRevert(TripFund.DeadlineNotReached.selector);
        fund.refund();

        vm.warp(DEADLINE - 1);
        contribute(bob, 1);
        vm.warp(DEADLINE);
        vm.prank(bob);
        vm.expectRevert(TripFund.DeadlinePassed.selector);
        fund.contribute(1);
        assertEq(fund.totalRaised(), 91);
    }

    function testGoalReachedAndDirectTransfer() public {
        contribute(alice, 40);
        contribute(bob, 60);
        vm.prank(alice);
        token.transfer(address(fund), 7);
        assertEq(fund.totalRaised(), 100);

        vm.warp(DEADLINE);
        vm.prank(stranger);
        vm.expectRevert(TripFund.NotOrganizer.selector);
        fund.withdraw();
        vm.prank(alice);
        vm.expectRevert(TripFund.GoalReached.selector);
        fund.refund();

        vm.prank(organizer);
        fund.withdraw();
        assertEq(token.balanceOf(organizer), 100);
        assertEq(token.balanceOf(address(fund)), 7);
        assertEq(fund.totalRaised(), 100);
        vm.prank(organizer);
        vm.expectRevert(TripFund.AlreadyWithdrawn.selector);
        fund.withdraw();
    }

    function testAboveGoal() public {
        contribute(alice, 60);
        contribute(bob, 50);
        vm.warp(DEADLINE);
        vm.prank(organizer);
        fund.withdraw();
        assertEq(token.balanceOf(organizer), 110);
    }

    function testBelowGoalRefunds() public {
        contribute(alice, 40);
        contribute(bob, 30);
        vm.prank(alice);
        token.transfer(address(fund), 5);
        vm.warp(DEADLINE);

        vm.prank(organizer);
        vm.expectRevert(TripFund.GoalNotReached.selector);
        fund.withdraw();
        vm.prank(stranger);
        vm.expectRevert(TripFund.NoContribution.selector);
        fund.refund();

        vm.prank(alice);
        fund.refund();
        vm.prank(alice);
        vm.expectRevert(TripFund.NoContribution.selector);
        fund.refund();
        vm.prank(bob);
        fund.refund();

        assertEq(fund.contributions(alice), 0);
        assertEq(fund.contributions(bob), 0);
        assertEq(token.balanceOf(alice), 195);
        assertEq(token.balanceOf(bob), 200);
        assertEq(token.balanceOf(address(fund)), 5);
        assertEq(fund.totalRaised(), 70);
    }
}
