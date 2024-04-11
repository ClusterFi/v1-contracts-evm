// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.20;

import "./ClErc20.sol";

/**
 * @title Cluster's ClErc20Delegate Contract
 * @notice ClTokens which wrap an EIP-20 underlying and are delegated to
 *         modified version of Compound's CErc20Delegate
 * @author Cluster
 */
contract ClErc20Delegate is ClErc20, ClDelegateInterface {

    error NotAdmin();

    /**
     * @notice Called by the delegator on a delegate to initialize it for duty
     * @param data The encoded bytes data for any initialization
     */
    function _becomeImplementation(bytes memory data) virtual override public {
        // Shh -- currently unused
        data;

        // Shh -- we don't ever want this hook to be marked pure
        if (false) {
            implementation = address(0);
        }

        if (msg.sender != admin) {
            revert NotAdmin();
        }
    }

    /**
     * @notice Called by the delegator on a delegate to forfeit its responsibility
     */
    function _resignImplementation() virtual override public {
        // Shh -- we don't ever want this hook to be marked pure
        if (false) {
            implementation = address(0);
        }

        if (msg.sender != admin) {
            revert NotAdmin();
        }
    }
}