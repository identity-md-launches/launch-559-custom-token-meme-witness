// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ALIBI} from "../src/ALIBI.sol";

/// @dev A test-only deployer that demonstrates constructor allocation to a contract caller.
contract TokenFactoryProbe {
    function deploy() external returns (ALIBI) {
        return new ALIBI();
    }

    function distribute(ALIBI token, address recipient, uint256 amount) external returns (bool) {
        return token.transfer(recipient, amount);
    }
}

contract ALIBITest is Test {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant SPENDER = address(0x5EED);

    ALIBI private token;

    function setUp() public {
        token = new ALIBI();
    }

    function testMetadataAndEntireInitialSupply() public view {
        assertEq(token.name(), "Meme Witness Protection");
        assertEq(token.symbol(), "ALIBI");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function testConstructorEmitsMintTransfer() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), address(this), SUPPLY);
        ALIBI deployed = new ALIBI();
        assertEq(deployed.balanceOf(address(this)), SUPPLY);
    }

    function testFactoryReceivesEntireSupply() public {
        TokenFactoryProbe factory = new TokenFactoryProbe();
        ALIBI deployed = factory.deploy();
        assertEq(deployed.balanceOf(address(factory)), SUPPLY);
        assertEq(deployed.balanceOf(address(this)), 0);
        assertEq(deployed.totalSupply(), SUPPLY);
    }

    /// @dev Custody smoke test only: this does not initialize a DEX pool or execute swaps.
    function testFactoryDistributorClaimAndPoolCustodyTransfersHaveNoFee() public {
        TokenFactoryProbe factory = new TokenFactoryProbe();
        ALIBI deployed = factory.deploy();
        address distributor = address(0xD157);
        address poolCustody = address(0xC057);
        uint256 swarm = SUPPLY / 10;
        uint256 poolAllocation = SUPPLY / 2;
        uint256 bought = 25 ether;

        assertTrue(factory.distribute(deployed, distributor, swarm));
        assertEq(deployed.balanceOf(distributor), swarm);
        vm.prank(distributor);
        assertTrue(deployed.transfer(ALICE, swarm));
        assertEq(deployed.balanceOf(ALICE), swarm);
        assertEq(deployed.balanceOf(distributor), 0);

        assertTrue(factory.distribute(deployed, poolCustody, poolAllocation));
        assertEq(deployed.balanceOf(poolCustody), poolAllocation);
        vm.prank(poolCustody);
        assertTrue(deployed.transfer(BOB, bought));
        assertEq(deployed.balanceOf(BOB), bought);
        assertEq(deployed.balanceOf(poolCustody), poolAllocation - bought);
        vm.prank(BOB);
        assertTrue(deployed.transfer(poolCustody, bought));
        assertEq(deployed.balanceOf(BOB), 0);
        assertEq(deployed.balanceOf(poolCustody), poolAllocation);

        uint256 remainder = SUPPLY - swarm - poolAllocation;
        assertTrue(factory.distribute(deployed, SPENDER, remainder));
        assertEq(deployed.balanceOf(SPENDER), remainder);
        assertEq(deployed.balanceOf(address(factory)), 0);
        assertEq(deployed.totalSupply(), SUPPLY);
    }

    function testTransferEmitsEventAndDeliversExactAmount() public {
        uint256 amount = 123 ether + 1;
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, amount);
        assertTrue(token.transfer(ALICE, amount));
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testTransferEntireSupply() public {
        assertTrue(token.transfer(ALICE, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(ALICE), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testZeroTransferFromUnfundedAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, BOB, 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testSelfTransferPreservesBalance() public {
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testApprovalEmitsEventAndCanBeReplacedAndRevoked() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), SPENDER, 10 ether);
        assertTrue(token.approve(SPENDER, 10 ether));
        assertEq(token.allowance(address(this), SPENDER), 10 ether);

        assertTrue(token.approve(SPENDER, 3 ether));
        assertEq(token.allowance(address(this), SPENDER), 3 ether);
        assertTrue(token.approve(SPENDER, 0));
        assertEq(token.allowance(address(this), SPENDER), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function testTransferFromSpendsFiniteAllowanceAndEmitsTransfer() public {
        token.approve(SPENDER, 10 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, 4 ether);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 4 ether));
        assertEq(token.allowance(address(this), SPENDER), 6 ether);
        assertEq(token.balanceOf(ALICE), 4 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 4 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testTransferFromPreservesInfiniteAllowance() public {
        token.approve(SPENDER, type(uint256).max);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, SUPPLY));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(ALICE), SUPPLY);
    }

    function testTransferFromToOwnerSpendsAllowanceWithoutChangingBalance() public {
        token.approve(SPENDER, 10 ether);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), address(this), 10 ether));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function testZeroTransferFromNeedsNoAllowance() public {
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 0));
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function testTransferFromOwnerStillRequiresAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function testTransferRejectsInsufficientBalanceWithoutChangingState() public {
        token.transfer(ALICE, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 1, 2));
        vm.prank(ALICE);
        token.transfer(BOB, 2);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testTransferRejectsMaximumAmountWithoutOverflow() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(ALICE, type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function testTransferRejectsZeroRecipientIncludingZeroValue() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function testApproveRejectsZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function testTransferFromRejectsInsufficientAllowanceWithoutChangingState() public {
        token.approve(SPENDER, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 1, 2));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 2);
        assertEq(token.allowance(address(this), SPENDER), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function testTransferFromBalanceFailureRestoresSpentAllowance() public {
        vm.prank(ALICE);
        token.approve(SPENDER, 10);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 10));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 10);
        assertEq(token.allowance(ALICE, SPENDER), 10);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function testTransferFromInvalidRecipientRestoresSpentAllowance() public {
        token.approve(SPENDER, 10);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), 10);
        assertEq(token.allowance(address(this), SPENDER), 10);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testTransferFromRejectsZeroSenderEvenForZeroValue() public {
        // OpenZeppelin validates the allowance owner before attempting the transfer.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(0), ALICE, 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function testDeployerCannotSpendHolderFundsWithoutApproval() public {
        token.transfer(ALICE, 100 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(ALICE, address(this), 1);
        assertEq(token.balanceOf(ALICE), 100 ether);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 100 ether));
        assertEq(token.balanceOf(BOB), 100 ether);
    }

    function testNoMintOrPrivilegedBalanceControlsExist() public {
        token.transfer(ALICE, 100 ether);
        bytes[8] memory calls = [
            abi.encodeWithSignature("mint(address,uint256)", BOB, SUPPLY),
            abi.encodeWithSignature("initialize(address)", BOB),
            abi.encodeWithSignature("upgradeTo(address)", BOB),
            abi.encodeWithSignature("pause()"),
            abi.encodeWithSignature("blacklist(address)", ALICE),
            abi.encodeWithSignature("freeze(address)", ALICE),
            abi.encodeWithSignature("burnFrom(address,uint256)", ALICE, 100 ether),
            abi.encodeWithSignature("seize(address)", ALICE)
        ];
        for (uint256 i; i < calls.length; ++i) {
            (bool deployerSucceeded,) = address(token).call(calls[i]);
            assertFalse(deployerSucceeded);
            vm.prank(BOB);
            (bool strangerSucceeded,) = address(token).call(calls[i]);
            assertFalse(strangerSucceeded);
            assertEq(token.totalSupply(), SUPPLY);
            assertEq(token.balanceOf(ALICE), 100 ether);
            assertEq(token.balanceOf(BOB), 0);
        }
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 100 ether));
        assertEq(token.balanceOf(BOB), 100 ether);
    }

    function testRuntimeHasNoForbiddenOpcodes() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 opcode = uint8(runtime[i]);
            if (opcode >= 0x60 && opcode <= 0x7f) {
                i += opcode - 0x5f;
                continue;
            }
            assertTrue(opcode != 0xf4, "DELEGATECALL");
            assertTrue(opcode != 0xf2, "CALLCODE");
            assertTrue(opcode != 0xff, "SELFDESTRUCT");
        }
    }

    function testFuzzTransferConservesBalancesAndSupply(address recipient, uint256 rawAmount) public {
        vm.assume(recipient != address(0) && recipient != address(this));
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.balanceOf(recipient) + token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzSelfTransferCannotCreateBalance(uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        assertTrue(token.transfer(address(this), amount));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzTransferFromConservesBalancesAndSpendsAllowance(uint256 rawAmount, uint256 rawAllowance) public {
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        uint256 approved = bound(rawAllowance, amount, SUPPLY);
        token.approve(SPENDER, approved);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, amount));
        assertEq(token.allowance(address(this), SPENDER), approved - amount);
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzInsufficientAllowanceIsAtomic(uint256 rawAmount, uint256 rawAllowance) public {
        uint256 amount = bound(rawAmount, 1, SUPPLY);
        uint256 approved = bound(rawAllowance, 0, amount - 1);
        token.approve(SPENDER, approved);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, approved, amount)
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, amount);
        assertEq(token.allowance(address(this), SPENDER), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
