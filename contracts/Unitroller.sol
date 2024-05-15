// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { UnitrollerAdminStorage } from "./ComptrollerStorage.sol";

/**
 * @title Comptroller Proxy
 * @dev Storage for the comptroller is at this address, while execution is delegated to
 * the `comptrollerImplementation`. 
 * NOTE: ClTokens should reference this contract as their comptroller.
 * @author Modified from Compound V2 Unitroller.
 * (https://github.com/compound-finance/compound-protocol/blob/master/contracts/Unitroller.sol)
 */
contract Unitroller is UnitrollerAdminStorage {
    /**
     * @notice Emitted when pendingComptrollerImplementation is updated
     */
    event NewPendingImplementation(
        address oldPendingImplementation,
        address newPendingImplementation
    );

    /**
     * @notice Emitted when pendingComptrollerImplementation is accepted, which means
     * comptroller implementation is updated
     */
    event NewImplementation(address oldImplementation, address newImplementation);

    /**
     * @notice Emitted when pendingAdmin is updated
     */
    event NewPendingAdmin(address oldPendingAdmin, address newPendingAdmin);

    /**
     * @notice Emitted when pendingAdmin is accepted, which means admin is updated
     */
    event NewAdmin(address oldAdmin, address newAdmin);

    error ZeroAddress();
    error NotAdmin();
    error NotPendingAdmin();
    error NotPendingImplementation();
    
    constructor() {
        // Set admin to caller
        admin = msg.sender;
    }

    function setPendingImplementation(address _newPendingImplementation) public {
        // check if caller is admin
        if (msg.sender != admin) revert NotAdmin();
        // check if new implementation is not zero address
        if (_newPendingImplementation == address(0)) revert ZeroAddress();

        address oldPendingImplementation = pendingComptrollerImplementation;

        pendingComptrollerImplementation = _newPendingImplementation;

        emit NewPendingImplementation(oldPendingImplementation, pendingComptrollerImplementation);
    }

    /**
     * @notice Accepts new implementation of comptroller. msg.sender must be pendingImplementation
     * @dev Admin function for new implementation to accept it's role as implementation
     */
    function acceptImplementation() public {
        // Check if caller is pendingImplementation
        if (msg.sender != pendingComptrollerImplementation) revert NotPendingImplementation();

        // Save current values for inclusion in log
        address _oldImplementation = comptrollerImplementation;
        address _oldPendingImplementation = pendingComptrollerImplementation;

        comptrollerImplementation = pendingComptrollerImplementation;

        pendingComptrollerImplementation = address(0);

        emit NewImplementation(_oldImplementation, comptrollerImplementation);
        emit NewPendingImplementation(_oldPendingImplementation, pendingComptrollerImplementation);
    }

    /**
     * @notice Admin function to begin change of admin.
     * @dev Begins transfer of admin rights. The newPendingAdmin must call `acceptAdmin` to
     * finalize the transfer.
     * @param _newPendingAdmin New pending admin.
     */
    function setPendingAdmin(address _newPendingAdmin) public {
        // Check if caller is admin
        if (msg.sender != admin) revert NotAdmin();
        // check if new admin is not zero address
        if (_newPendingAdmin == address(0)) revert ZeroAddress();

        address _oldPendingAdmin = pendingAdmin;

        pendingAdmin = _newPendingAdmin;

        emit NewPendingAdmin(_oldPendingAdmin, _newPendingAdmin);
    }

    /**
     * @notice Accepts transfer of admin rights. msg.sender must be pendingAdmin
     * @dev Admin function for pending admin to accept role and update admin
     */
    function acceptAdmin() public {
        // Check if caller is pendingImplementation
        if (msg.sender != pendingAdmin) revert NotPendingAdmin();

        address _oldAdmin = admin;
        address _oldPendingAdmin = pendingAdmin;

        admin = pendingAdmin;

        // Clear the pending value
        pendingAdmin = address(0);

        emit NewAdmin(_oldAdmin, admin);
        emit NewPendingAdmin(_oldPendingAdmin, pendingAdmin);
    }

    /**
     * @dev Delegates execution to an implementation contract.
     * It returns to the external caller whatever the implementation returns
     * or forwards reverts.
     */
    fallback() external payable {
        // delegate all other functions to current implementation
        (bool success, ) = comptrollerImplementation.delegatecall(msg.data);

        assembly {
            let free_mem_ptr := mload(0x40)
            returndatacopy(free_mem_ptr, 0, returndatasize())

            switch success
            case 0 {
                revert(free_mem_ptr, returndatasize())
            }
            default {
                return(free_mem_ptr, returndatasize())
            }
        }
    }
}
