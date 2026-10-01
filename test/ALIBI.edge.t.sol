// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ALIBI} from "../src/ALIBI.sol";

/// @dev Supplements the deployment/basic ERC-20 suite with allowance lifecycles,
/// arithmetic boundaries, and failures after successful operations.
/// forge-config: default.fuzz.runs = 1000
contract ALIBIEdgeTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant SPENDER = address(0x5EED);
    ALIBI private token;

    function setUp() public {
        token = new ALIBI();
    }

    function testOneWeiAndFullSupplyRoundTripsLeaveNoDust() public {
        assertTrue(token.transfer(ALICE, 1));
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        vm.prank(ALICE);
        assertTrue(token.transfer(address(this), 1));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);

        assertTrue(token.approve(SPENDER, SUPPLY));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(ALICE), SUPPLY);
        assertEq(token.allowance(address(this), SPENDER), 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testMaximumMinusOneAllowanceIsFiniteAcrossRepeatedSpends() public {
        token.approve(SPENDER, type(uint256).max - 1);
        for (uint256 i = 1; i <= 2; ++i) {
            vm.prank(SPENDER);
            assertTrue(token.transferFrom(address(this), ALICE, 1));
            assertEq(token.allowance(address(this), SPENDER), type(uint256).max - 1 - i);
            assertEq(token.balanceOf(ALICE), i);
            assertEq(token.balanceOf(address(this)), SUPPLY - i);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testInfiniteApprovalCanBeReducedAndRevokedAfterUse() public {
        token.approve(SPENDER, type(uint256).max);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);

        token.approve(SPENDER, 1);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), SPENDER), 0);
        _expectAllowanceFailure(address(this), 0, 1);

        token.approve(SPENDER, type(uint256).max);
        token.approve(SPENDER, 0);
        _expectAllowanceFailure(address(this), 0, 1);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 2);
        assertEq(token.balanceOf(address(this)), SUPPLY - 2);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testApprovalsAreIndependentForEachOwnerAndSpender() public {
        token.transfer(ALICE, 10);
        token.approve(SPENDER, 3);
        token.approve(BOB, 5);
        vm.prank(ALICE);
        token.approve(SPENDER, 7);

        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), BOB, 1));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 2));
        vm.prank(BOB);
        assertTrue(token.transferFrom(address(this), ALICE, 3));
        assertEq(token.allowance(address(this), SPENDER), 2);
        assertEq(token.allowance(address(this), BOB), 2);
        assertEq(token.allowance(ALICE, SPENDER), 5);
        assertEq(token.allowance(SPENDER, ALICE), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 14);
        assertEq(token.balanceOf(ALICE), 11);
        assertEq(token.balanceOf(BOB), 3);
        assertEq(token.balanceOf(SPENDER), 0);

        _expectAllowanceFailure(address(this), 2, 3);
        assertEq(token.allowance(address(this), SPENDER), 2);
        assertEq(token.allowance(address(this), BOB), 2);
        assertEq(token.allowance(ALICE, SPENDER), 5);
        assertEq(token.balanceOf(address(this)), SUPPLY - 14);
        assertEq(token.balanceOf(ALICE), 11);
        assertEq(token.balanceOf(BOB), 3);
    }

    function testAnApprovalDoesNotFollowTokensToTheirNewOwner() public {
        token.approve(SPENDER, type(uint256).max);
        token.transfer(ALICE, 10);
        _expectAllowanceFailure(ALICE, 0, 1);
        assertEq(token.balanceOf(ALICE), 10);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
    }

    function testApprovalBeforeFundingSurvivesFailedSpendThenBecomesUsable() public {
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 1);
        assertEq(token.allowance(ALICE, SPENDER), 1);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);

        token.transfer(ALICE, 1);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 1));
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testSelfTransferStillChecksBalanceAndPreservesAllowanceOnFailure() public {
        token.transfer(ALICE, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 1, 2));
        vm.prank(ALICE);
        token.transfer(ALICE, 2);
        assertEq(token.balanceOf(ALICE), 1);

        vm.prank(ALICE);
        token.approve(SPENDER, 2);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 1, 2));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, ALICE, 2);
        assertEq(token.allowance(ALICE, SPENDER), 2);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testMaximumTransferFromRevertsWithoutConsumingInfiniteAllowance() public {
        token.approve(SPENDER, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, type(uint256).max);
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testZeroDelegatedTransferRejectsZeroRecipientForFiniteAndInfiniteAllowances() public {
        uint256[3] memory approvals = [uint256(0), 1, type(uint256).max];
        for (uint256 i; i < approvals.length; ++i) {
            token.approve(SPENDER, approvals[i]);
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(SPENDER);
            token.transferFrom(address(this), address(0), 0);
            assertEq(token.allowance(address(this), SPENDER), approvals[i]);
            assertEq(token.balanceOf(address(this)), SUPPLY);
            assertEq(token.balanceOf(address(0)), 0);
            assertEq(token.totalSupply(), SUPPLY);
        }
    }

    function testZeroApprovalToZeroSpenderIsRejected() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzOverdrawIsAtomic(uint256 balanceSeed, uint256 amountSeed) public {
        uint256 balance = bound(balanceSeed, 0, SUPPLY);
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max);
        token.transfer(ALICE, balance);
        vm.prank(ALICE);
        token.approve(SPENDER, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, balance, amount));
        vm.prank(ALICE);
        token.transfer(BOB, amount);
        assertEq(token.balanceOf(ALICE), balance);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.allowance(ALICE, SPENDER), type(uint256).max);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzSplitSpendingExhaustsAllowanceAndCannotReplay(uint256 totalSeed, uint256 firstSeed) public {
        uint256 total = bound(totalSeed, 1, SUPPLY);
        uint256 first = bound(firstSeed, 0, total);
        token.approve(SPENDER, total);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, first));
        assertEq(token.allowance(address(this), SPENDER), total - first);
        assertEq(token.balanceOf(ALICE), first);
        assertEq(token.balanceOf(address(this)), SUPPLY - first);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), BOB, total - first));
        assertEq(token.allowance(address(this), SPENDER), 0);

        _expectAllowanceFailure(address(this), 0, 1);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(ALICE), first);
        assertEq(token.balanceOf(BOB), total - first);
        assertEq(token.balanceOf(address(this)), SUPPLY - total);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzApprovalReplacementIsIdempotentAndDoesNotMoveFunds(uint256 oldAmount, uint256 newAmount) public {
        vm.startPrank(ALICE);
        assertTrue(token.approve(SPENDER, oldAmount));
        assertTrue(token.approve(SPENDER, newAmount));
        assertEq(token.allowance(ALICE, SPENDER), newAmount);
        assertTrue(token.approve(SPENDER, newAmount));
        vm.stopPrank();
        assertEq(token.allowance(ALICE, SPENDER), newAmount);
        assertEq(token.allowance(SPENDER, ALICE), 0);
        assertEq(token.allowance(ALICE, BOB), 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function _expectAllowanceFailure(address owner, uint256 allowance, uint256 amount) private {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, allowance, amount)
        );
        vm.prank(SPENDER);
        token.transferFrom(owner, BOB, amount);
    }
}
