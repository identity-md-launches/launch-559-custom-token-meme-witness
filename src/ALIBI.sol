// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Meme Witness Protection (ALIBI)
/// @notice A fixed-supply, fee-free ERC-20 with 18 decimals and no administrative powers.
contract ALIBI is ERC20 {
    /// @notice One billion tokens, expressed in the token's smallest units.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @notice Mints the entire supply once to the immediate deploying address.
    /// @dev When deployed by a factory, the factory receives the supply.
    constructor() ERC20("Meme Witness Protection", "ALIBI") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
