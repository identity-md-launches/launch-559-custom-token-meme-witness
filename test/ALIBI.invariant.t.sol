// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ALIBI} from "../src/ALIBI.sol";

/// @dev Exercises arbitrary sequences against an independent balance/allowance model.
contract ALIBIHandler is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    ALIBI public immutable token;
    address[4] public actors = [address(0xA11CE), address(0xB0B), address(0xCA11), address(0xD00D)];
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor() {
        token = new ALIBI();
        uint256 allocation = SUPPLY / actors.length;
        for (uint256 i; i < actors.length; ++i) {
            expectedBalance[actors[i]] = allocation;
            require(token.transfer(actors[i], allocation), "initial allocation failed");
        }
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = bound(amountSeed, 0, expectedBalance[from]);
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) public {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        expectedAllowance[owner][spender] = amount;
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
    }

    /// @dev Reach revocation, exact-one, and finite/infinite boundaries reliably.
    function approveBoundary(uint256 ownerSeed, uint256 spenderSeed, uint256 boundarySeed) external {
        uint256[5] memory amounts = [uint256(0), 1, SUPPLY, type(uint256).max - 1, type(uint256).max];
        approve(ownerSeed, spenderSeed, amounts[boundarySeed % amounts.length]);
    }

    function transferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address spender = actors[spenderSeed % actors.length];
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowance = expectedAllowance[from][spender];
        uint256 limit = allowance < expectedBalance[from] ? allowance : expectedBalance[from];
        uint256 amount = bound(amountSeed, 0, limit);
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
        if (allowance != type(uint256).max) {
            expectedAllowance[from][spender] -= amount;
        }
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
    }

    /// @dev Rejected transfers leave the entire ghost ledger unchanged.
    function rejectTransfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed, bool zeroRecipient) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[from];
        uint256 amount;
        if (zeroRecipient) {
            to = address(0);
            amount = bound(amountSeed, 0, balance);
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        } else {
            amount = bound(amountSeed, balance + 1, type(uint256).max);
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount)
            );
        }
        vm.prank(from);
        token.transfer(to, amount);
    }

    /// @dev Prepare a specific failure, then retain the approval in the model: a
    /// reverted transferFrom must not consume it or change any actor's balance.
    function rejectTransferFrom(
        uint256 fromSeed,
        uint256 spenderSeed,
        uint256 amountSeed,
        uint256 failureSeed,
        bool infinite
    ) external {
        address from = actors[fromSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[(fromSeed % actors.length + 1) % actors.length];
        uint256 balance = expectedBalance[from];
        uint256 failure = failureSeed % 3;
        uint256 amount;
        uint256 approved;
        bytes memory reason;
        if (failure == 0) {
            approved = bound(amountSeed, 0, SUPPLY);
            amount = approved + 1;
            reason = abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, amount);
        } else if (failure == 1) {
            amount = bound(amountSeed, balance + 1, type(uint256).max - 1);
            approved = infinite ? type(uint256).max : amount;
            reason = abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount);
        } else {
            amount = bound(amountSeed, 0, balance);
            approved = infinite ? type(uint256).max : amount;
            to = address(0);
            reason = abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0));
        }
        approve(fromSeed, spenderSeed, approved);
        vm.expectRevert(reason);
        vm.prank(spender);
        token.transferFrom(from, to, amount);
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract ALIBIInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    ALIBIHandler private handler;
    ALIBI private token;

    function setUp() public {
        handler = new ALIBIHandler();
        token = handler.token();
        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = ALIBIHandler.transfer.selector;
        selectors[1] = ALIBIHandler.approve.selector;
        selectors[2] = ALIBIHandler.transferFrom.selector;
        selectors[3] = ALIBIHandler.approveBoundary.selector;
        selectors[4] = ALIBIHandler.rejectTransfer.selector;
        selectors[5] = ALIBIHandler.rejectTransferFrom.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_fixedSupplyAndExactBalancesAndAllowances() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        uint256 trackedSupply;
        for (uint256 i; i < 4; ++i) {
            address holder = handler.actors(i);
            uint256 balance = token.balanceOf(holder);
            trackedSupply += balance;
            assertEq(balance, handler.expectedBalance(holder));
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(holder, spender), handler.expectedAllowance(holder, spender));
            }
        }
        assertEq(trackedSupply, SUPPLY);
    }

    /// @dev After any sequence, every holder can still move its full balance and
    /// receive it back without fees. Intermediate checks prevent offsetting errors.
    function afterInvariant() public {
        for (uint256 i; i < 4; ++i) {
            address holder = handler.actors(i);
            address recipient = handler.actors((i + 1) % 4);
            uint256 held = token.balanceOf(holder);
            uint256 otherHeld = token.balanceOf(recipient);
            vm.prank(holder);
            assertTrue(token.transfer(recipient, held));
            assertEq(token.balanceOf(holder), 0);
            assertEq(token.balanceOf(recipient), otherHeld + held);
            vm.prank(recipient);
            assertTrue(token.transfer(holder, held));
            assertEq(token.balanceOf(holder), held);
            assertEq(token.balanceOf(recipient), otherHeld);
        }
        invariant_fixedSupplyAndExactBalancesAndAllowances();
    }

    /// @dev Pin a mixed sequence so all failure branches and allowance boundaries
    /// are covered even if a future random seed does not select them.
    function testMixedSequencePreservesLedgerAndTransferability() public {
        handler.transfer(0, 1, 1);
        handler.approve(0, 2, 2);
        handler.transferFrom(2, 0, 0, 1);
        invariant_fixedSupplyAndExactBalancesAndAllowances();
        handler.transferFrom(2, 0, 1, 1);
        invariant_fixedSupplyAndExactBalancesAndAllowances();
        handler.rejectTransfer(0, 0, type(uint256).max, false);
        handler.rejectTransfer(0, 1, 0, true);
        invariant_fixedSupplyAndExactBalancesAndAllowances();
        for (uint256 failure; failure < 3; ++failure) {
            handler.rejectTransferFrom(0, 2, 1, failure, false);
            invariant_fixedSupplyAndExactBalancesAndAllowances();
            handler.rejectTransferFrom(0, 2, 1, failure, true);
            invariant_fixedSupplyAndExactBalancesAndAllowances();
        }
        for (uint256 boundary; boundary < 5; ++boundary) {
            handler.approveBoundary(0, 1, boundary);
            handler.transferFrom(1, 0, 2, boundary == 0 ? 0 : 1);
            invariant_fixedSupplyAndExactBalancesAndAllowances();
        }
        afterInvariant();
    }
}
