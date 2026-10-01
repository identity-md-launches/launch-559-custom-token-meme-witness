// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {ALIBI} from "../src/ALIBI.sol";

/// @dev Exercises arbitrary sequences against an independent balance/allowance model.
contract ALIBIHandler is Test {
    ALIBI public immutable token;
    address[4] public actors = [address(0xA11CE), address(0xB0B), address(0xCA11), address(0xD00D)];
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor() {
        token = new ALIBI();
        uint256 allocation = token.totalSupply() / actors.length;
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

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        expectedAllowance[owner][spender] = amount;
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
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
}

contract ALIBIInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    ALIBIHandler private handler;
    ALIBI private token;

    function setUp() public {
        handler = new ALIBIHandler();
        token = handler.token();
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = ALIBIHandler.transfer.selector;
        selectors[1] = ALIBIHandler.approve.selector;
        selectors[2] = ALIBIHandler.transferFrom.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_fixedSupplyAndExactBalancesAndAllowances() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
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
}
