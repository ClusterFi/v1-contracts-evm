// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./base/ClTokenInterfaces.sol";

/**
 * @title Cluster's ClErc20Delegator Contract
 * @notice ClTokens which wrap an EIP-20 underlying and delegate to an implementation
 * @author Modified from Compound CErc20Delegator contract
 * (https://github.com/compound-finance/compound-protocol/blob/master/contracts/CErc20Delegator.sol)
 */
contract ClErc20Delegator is ClTokenInterface, ClErc20Interface, ClDelegatorInterface {
    error NotAdmin();
    error FallbackNotReceiveEther();

    /**
     * @notice Construct a new money market
     * @param _underlying The address of the underlying asset
     * @param _comptroller The address of the Comptroller
     * @param _interestRateModel The address of the interest rate model
     * @param _initialExchangeRateMantissa The initial exchange rate, scaled by 1e18
     * @param _name ERC-20 name of this token
     * @param _symbol ERC-20 symbol of this token
     * @param _decimals ERC-20 decimal precision of this token
     * @param _admin Address of the administrator of this token
     * @param _implementation The address of the implementation the contract delegates to
     * @param _becomeImplementationData The encoded args for becomeImplementation
     */
    constructor(
        address _underlying,
        ComptrollerInterface _comptroller,
        IInterestRateModel _interestRateModel,
        uint _initialExchangeRateMantissa,
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address payable _admin,
        address _implementation,
        bytes memory _becomeImplementationData
    ) {
        // Creator of the contract is admin during initialization
        admin = payable(msg.sender);

        // First delegate gets to initialize the delegator (i.e. storage contract)
        _delegateTo(
            _implementation,
            abi.encodeWithSignature(
                "initialize(address,address,address,uint256,string,string,uint8)",
                _underlying,
                _comptroller,
                _interestRateModel,
                _initialExchangeRateMantissa,
                _name,
                _symbol,
                _decimals
            )
        );

        // New implementations always get set via the settor (post-initialize)
        setImplementation(_implementation, false, _becomeImplementationData);

        // Set the proper admin now that initialization is done
        admin = _admin;
    }

    /**
     * @notice Called by the admin to update the implementation of the delegator
     * @param _implementation The address of the new implementation for delegation
     * @param _allowResign Flag to indicate whether to call resignImplementation on the old implementation
     * @param _becomeImplementationData The encoded bytes data to be passed to _becomeImplementation
     */
    function setImplementation(
        address _implementation,
        bool _allowResign,
        bytes memory _becomeImplementationData
    ) public override {
        if (msg.sender != admin) {
            revert NotAdmin();
        }

        if (_allowResign) {
            delegateToImplementation(abi.encodeWithSignature("resignImplementation()"));
        }

        address oldImplementation = implementation;
        implementation = _implementation;

        delegateToImplementation(
            abi.encodeWithSignature("becomeImplementation(bytes)", _becomeImplementationData)
        );

        emit NewImplementation(oldImplementation, implementation);
    }

    /**
     * @notice Sender supplies assets into the market and receives clTokens in exchange
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param _mintAmount The amount of the underlying asset to supply
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function mint(uint _mintAmount) external override returns (uint) {
        bytes memory data = delegateToImplementation(
            abi.encodeWithSignature("mint(uint256)", _mintAmount)
        );
        return abi.decode(data, (uint));
    }

    /**
     * @notice Sender redeems clTokens in exchange for the underlying asset
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param _redeemTokens The number of clTokens to redeem into underlying
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function redeem(uint _redeemTokens) external override returns (uint) {
        bytes memory data = delegateToImplementation(
            abi.encodeWithSignature("redeem(uint256)", _redeemTokens)
        );
        return abi.decode(data, (uint));
    }

    /**
     * @notice Sender redeems clTokens in exchange for a specified amount of underlying asset
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param _redeemAmount The amount of underlying to redeem
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function redeemUnderlying(uint _redeemAmount) external override returns (uint) {
        bytes memory data = delegateToImplementation(
            abi.encodeWithSignature("redeemUnderlying(uint256)", _redeemAmount)
        );
        return abi.decode(data, (uint));
    }

    /**
     * @notice Sender borrows assets from the protocol to their own address
     * @param _borrowAmount The amount of the underlying asset to borrow
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function borrow(uint _borrowAmount) external override returns (uint) {
        bytes memory data = delegateToImplementation(
            abi.encodeWithSignature("borrow(uint256)", _borrowAmount)
        );
        return abi.decode(data, (uint));
    }

    /**
     * @notice Sender repays their own borrow
     * @param _repayAmount The amount to repay, or -1 for the full outstanding amount
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function repayBorrow(uint _repayAmount) external override returns (uint) {
        bytes memory data = delegateToImplementation(
            abi.encodeWithSignature("repayBorrow(uint256)", _repayAmount)
        );
        return abi.decode(data, (uint));
    }

    /**
     * @notice Sender repays a borrow belonging to borrower
     * @param _borrower the account with the debt being payed off
     * @param _repayAmount The amount to repay, or -1 for the full outstanding amount
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function repayBorrowBehalf(
        address _borrower,
        uint _repayAmount
    ) external override returns (uint) {
        bytes memory data = delegateToImplementation(
            abi.encodeWithSignature("repayBorrowBehalf(address,uint256)", _borrower, _repayAmount)
        );
        return abi.decode(data, (uint));
    }

    /**
     * @notice The sender liquidates the borrowers collateral.
     *  The collateral seized is transferred to the liquidator.
     * @param _borrower The borrower of this clToken to be liquidated
     * @param _clTokenCollateral The market in which to seize collateral from the borrower
     * @param _repayAmount The amount of the underlying borrowed asset to repay
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function liquidateBorrow(
        address _borrower,
        uint _repayAmount,
        ClTokenInterface _clTokenCollateral
    ) external override returns (uint) {
        bytes memory data = delegateToImplementation(
            abi.encodeWithSignature(
                "liquidateBorrow(address,uint256,address)",
                _borrower,
                _repayAmount,
                _clTokenCollateral
            )
        );
        return abi.decode(data, (uint));
    }

    /**
     * @notice Transfer `_amount` tokens from `msg.sender` to `_dst`
     * @param _dst The address of the destination account
     * @param _amount The number of tokens to transfer
     * @return Whether or not the transfer succeeded
     */
    function transfer(address _dst, uint _amount) external override returns (bool) {
        bytes memory data = delegateToImplementation(
            abi.encodeWithSignature("transfer(address,uint256)", _dst, _amount)
        );
        return abi.decode(data, (bool));
    }

    /**
     * @notice Transfer `_amount` tokens from `_src` to `_dst`
     * @param _src The address of the source account
     * @param _dst The address of the destination account
     * @param _amount The number of tokens to transfer
     * @return Whether or not the transfer succeeded
     */
    function transferFrom(
        address _src,
        address _dst,
        uint256 _amount
    ) external override returns (bool) {
        bytes memory data = delegateToImplementation(
            abi.encodeWithSignature("transferFrom(address,address,uint256)", _src, _dst, _amount)
        );
        return abi.decode(data, (bool));
    }

    /**
     * @notice Approve `_spender` to transfer up to `_amount` from `src`
     * @dev This will overwrite the approval amount for `_spender`
     *  and is subject to issues noted [here](https://eips.ethereum.org/EIPS/eip-20#approve)
     * @param _spender The address of the account which may transfer tokens
     * @param _amount The number of tokens that are approved (-1 means infinite)
     * @return Whether or not the approval succeeded
     */
    function approve(address _spender, uint256 _amount) external override returns (bool) {
        bytes memory data = delegateToImplementation(
            abi.encodeWithSignature("approve(address,uint256)", _spender, _amount)
        );
        return abi.decode(data, (bool));
    }

    /**
     * @notice Get the current allowance from `_owner` for `_spender`
     * @param _owner The address of the account which owns the tokens to be spent
     * @param _spender The address of the account which may transfer tokens
     * @return The number of tokens allowed to be spent (-1 means infinite)
     */
    function allowance(address _owner, address _spender) external view override returns (uint) {
        bytes memory data = delegateToViewImplementation(
            abi.encodeWithSignature("allowance(address,address)", _owner, _spender)
        );
        return abi.decode(data, (uint));
    }

    /**
     * @notice Get the token balance of the `_owner`
     * @param _owner The address of the account to query
     * @return The number of tokens owned by `_owner`
     */
    function balanceOf(address _owner) external view override returns (uint) {
        bytes memory data = delegateToViewImplementation(
            abi.encodeWithSignature("balanceOf(address)", _owner)
        );
        return abi.decode(data, (uint));
    }

    /**
     * @notice Get the underlying balance of the `_owner`
     * @dev This also accrues interest in a transaction
     * @param _owner The address of the account to query
     * @return The amount of underlying owned by `_owner`
     */
    function balanceOfUnderlying(address _owner) external override returns (uint) {
        bytes memory data = delegateToImplementation(
            abi.encodeWithSignature("balanceOfUnderlying(address)", _owner)
        );
        return abi.decode(data, (uint));
    }

    /**
     * @notice Get a snapshot of the account's balances, and the cached exchange rate
     * @dev This is used by comptroller to more efficiently perform liquidity checks.
     * @param _account Address of the account to snapshot
     * @return (possible error, token balance, borrow balance, exchange rate mantissa)
     */
    function getAccountSnapshot(
        address _account
    ) external view override returns (uint, uint, uint, uint) {
        bytes memory data = delegateToViewImplementation(
            abi.encodeWithSignature("getAccountSnapshot(address)", _account)
        );
        return abi.decode(data, (uint, uint, uint, uint));
    }

    /**
     * @notice Returns the current per-block borrow interest rate for this clToken
     * @return The borrow interest rate per block, scaled by 1e18
     */
    function borrowRatePerBlock() external view override returns (uint) {
        bytes memory data = delegateToViewImplementation(
            abi.encodeWithSignature("borrowRatePerBlock()")
        );
        return abi.decode(data, (uint));
    }

    /**
     * @notice Returns the current per-block supply interest rate for this clToken
     * @return The supply interest rate per block, scaled by 1e18
     */
    function supplyRatePerBlock() external view override returns (uint) {
        bytes memory data = delegateToViewImplementation(
            abi.encodeWithSignature("supplyRatePerBlock()")
        );
        return abi.decode(data, (uint));
    }

    /**
     * @notice Returns the current total borrows plus accrued interest
     * @return The total borrows with interest
     */
    function totalBorrowsCurrent() external override returns (uint) {
        bytes memory data = delegateToImplementation(
            abi.encodeWithSignature("totalBorrowsCurrent()")
        );
        return abi.decode(data, (uint));
    }

    /**
     * @notice Accrue interest to updated borrowIndex and then calculate account's borrow balance
     * using the updated borrowIndex
     * @param _account The address whose balance should be calculated after updating borrowIndex
     * @return The calculated balance
     */
    function borrowBalanceCurrent(address _account) external override returns (uint) {
        bytes memory data = delegateToImplementation(
            abi.encodeWithSignature("borrowBalanceCurrent(address)", _account)
        );
        return abi.decode(data, (uint));
    }

    /**
     * @notice Return the borrow balance of account based on stored data
     * @param _account The address whose balance should be calculated
     * @return The calculated balance
     */
    function borrowBalanceStored(address _account) public view override returns (uint) {
        bytes memory data = delegateToViewImplementation(
            abi.encodeWithSignature("borrowBalanceStored(address)", _account)
        );
        return abi.decode(data, (uint));
    }

    /**
     * @notice Accrue interest then return the up-to-date exchange rate
     * @return Calculated exchange rate scaled by 1e18
     */
    function exchangeRateCurrent() public override returns (uint) {
        bytes memory data = delegateToImplementation(
            abi.encodeWithSignature("exchangeRateCurrent()")
        );
        return abi.decode(data, (uint));
    }

    /**
     * @notice Calculates the exchange rate from the underlying to the ClToken
     * @dev This function does not accrue interest before calculating the exchange rate
     * @return Calculated exchange rate scaled by 1e18
     */
    function exchangeRateStored() public view override returns (uint) {
        bytes memory data = delegateToViewImplementation(
            abi.encodeWithSignature("exchangeRateStored()")
        );
        return abi.decode(data, (uint));
    }

    /**
     * @notice Get cash balance of this clToken in the underlying asset
     * @return The quantity of underlying asset owned by this contract
     */
    function getCash() external view override returns (uint) {
        bytes memory data = delegateToViewImplementation(abi.encodeWithSignature("getCash()"));
        return abi.decode(data, (uint));
    }

    /**
     * @notice Applies accrued interest to total borrows and reserves.
     * @dev This calculates interest accrued from the last checkpointed block
     *      up to the current block and writes new checkpoint to storage.
     */
    function accrueInterest() public override returns (uint) {
        bytes memory data = delegateToImplementation(abi.encodeWithSignature("accrueInterest()"));
        return abi.decode(data, (uint));
    }

    /**
     * @notice Transfers collateral tokens (this market) to the liquidator.
     * @dev Will fail unless called by another clToken during the process of liquidation.
     *  Its absolutely critical to use msg.sender as the borrowed clToken and not a parameter.
     * @param _liquidator The account receiving seized collateral
     * @param _borrower The account having collateral seized
     * @param _seizeTokens The number of clTokens to seize
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function seize(
        address _liquidator,
        address _borrower,
        uint _seizeTokens
    ) external override returns (uint) {
        bytes memory data = delegateToImplementation(
            abi.encodeWithSignature(
                "seize(address,address,uint256)",
                _liquidator,
                _borrower,
                _seizeTokens
            )
        );
        return abi.decode(data, (uint));
    }

    /**
     * @notice A public function to sweep accidental ERC-20 transfers to this contract.
     * Tokens are sent to admin (timelock)
     * @param _token The address of the ERC-20 token to sweep
     */
    function sweepToken(EIP20NonStandardInterface _token) external override {
        delegateToImplementation(abi.encodeWithSignature("sweepToken(address)", _token));
    }

    /*** Admin Functions ***/

    /**
     * @notice Begins transfer of admin rights. The newPendingAdmin must call `acceptAdmin` to finalize the transfer.
     * @dev Admin function to begin change of admin. The newPendingAdmin must call `acceptAdmin`
     *      to finalize the transfer.
     * @param _newPendingAdmin New pending admin.
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function setPendingAdmin(address payable _newPendingAdmin) external override returns (uint) {
        bytes memory data = delegateToImplementation(
            abi.encodeWithSignature("setPendingAdmin(address)", _newPendingAdmin)
        );
        return abi.decode(data, (uint));
    }

    /**
     * @notice Sets a new comptroller for the market
     * @dev Admin function to set a new comptroller
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function setComptroller(ComptrollerInterface _newComptroller) external override returns (uint) {
        bytes memory data = delegateToImplementation(
            abi.encodeWithSignature("setComptroller(address)", _newComptroller)
        );
        return abi.decode(data, (uint));
    }

    /**
     * @notice accrues interest and sets a new reserve factor for the protocol using _setReserveFactorFresh
     * @dev Admin function to accrue interest and set a new reserve factor
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function setReserveFactor(uint _newReserveFactorMantissa) external override returns (uint) {
        bytes memory data = delegateToImplementation(
            abi.encodeWithSignature("setReserveFactor(uint256)", _newReserveFactorMantissa)
        );
        return abi.decode(data, (uint));
    }

    /**
     * @notice Accepts transfer of admin rights. msg.sender must be pendingAdmin
     * @dev Admin function for pending admin to accept role and update admin
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function acceptAdmin() external override returns (uint) {
        bytes memory data = delegateToImplementation(abi.encodeWithSignature("acceptAdmin()"));
        return abi.decode(data, (uint));
    }

    /**
     * @notice Accrues interest and adds reserves by transferring from admin
     * @param _addAmount Amount of reserves to add
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function addReserves(uint _addAmount) external override returns (uint) {
        bytes memory data = delegateToImplementation(
            abi.encodeWithSignature("addReserves(uint256)", _addAmount)
        );
        return abi.decode(data, (uint));
    }

    /**
     * @notice Accrues interest and reduces reserves by transferring to admin
     * @param _reduceAmount Amount of reduction to reserves
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function reduceReserves(uint _reduceAmount) external override returns (uint) {
        bytes memory data = delegateToImplementation(
            abi.encodeWithSignature("reduceReserves(uint256)", _reduceAmount)
        );
        return abi.decode(data, (uint));
    }

    /**
     * @notice Accrues interest and updates the interest rate model using _setInterestRateModelFresh
     * @dev Admin function to accrue interest and update the interest rate model
     * @param _newInterestRateModel the new interest rate model to use
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function setInterestRateModel(address _newInterestRateModel) external override returns (uint) {
        bytes memory data = delegateToImplementation(
            abi.encodeWithSignature("setInterestRateModel(address)", _newInterestRateModel)
        );
        return abi.decode(data, (uint));
    }

    /**
     * @notice Delegates execution to the implementation contract
     * @dev It returns to the external caller whatever the implementation returns or forwards reverts
     * @param _data The raw data to delegatecall
     * @return The returned bytes from the delegatecall
     */
    function delegateToImplementation(bytes memory _data) public returns (bytes memory) {
        return _delegateTo(implementation, _data);
    }

    /**
     * @notice Delegates execution to an implementation contract
     * @dev It returns to the external caller whatever the implementation returns or forwards reverts
     *  There are an additional 2 prefix uints from the wrapper returndata, which we ignore since we make an extra hop.
     * @param _data The raw data to delegatecall
     * @return The returned bytes from the delegatecall
     */
    function delegateToViewImplementation(bytes memory _data) public view returns (bytes memory) {
        (bool success, bytes memory returnData) = address(this).staticcall(
            abi.encodeWithSignature("delegateToImplementation(bytes)", _data)
        );
        assembly {
            if eq(success, 0) {
                revert(add(returnData, 0x20), returndatasize())
            }
        }
        return abi.decode(returnData, (bytes));
    }

    /**
     * @notice Internal method to delegate execution to another contract
     * @dev It returns to the external caller whatever the implementation returns or forwards reverts
     * @param _callee The contract to delegatecall
     * @param _data The raw data to delegatecall
     * @return The returned bytes from the delegatecall
     */
    function _delegateTo(address _callee, bytes memory _data) internal returns (bytes memory) {
        (bool success, bytes memory returnData) = _callee.delegatecall(_data);
        assembly {
            if eq(success, 0) {
                revert(add(returnData, 0x20), returndatasize())
            }
        }
        return returnData;
    }

    /**
     * @notice Delegates execution to an implementation contract
     * @dev It returns to the external caller whatever the implementation returns or forwards reverts
     */
    fallback() external payable {
        if (msg.value != 0) revert FallbackNotReceiveEther();

        // delegate all other functions to current implementation
        (bool success, ) = implementation.delegatecall(msg.data);

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
