// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.20;

import "./tokens/ClToken.sol";
import "./base/PriceOracle.sol";

contract UnitrollerAdminStorage {
    /**
     * @notice Administrator for this contract
     */
    address public admin;

    /**
     * @notice Pending administrator for this contract
     */
    address public pendingAdmin;

    /**
     * @notice Active brains of Unitroller
     */
    address public comptrollerImplementation;

    /**
     * @notice Pending brains of Unitroller
     */
    address public pendingComptrollerImplementation;
}

contract ComptrollerV1Storage is UnitrollerAdminStorage {
    /**
     * @notice Oracle which gives the price of any given asset
     */
    PriceOracle public oracle;

    /**
     * @notice Multiplier used to calculate the maximum repayAmount when liquidating a borrow
     */
    uint public closeFactorMantissa;

    /**
     * @notice Multiplier representing the discount on collateral that a liquidator receives
     */
    uint public liquidationIncentiveMantissa;

    /**
     * @notice Max number of assets a single account can participate in (borrow or use as collateral)
     */
    uint public maxAssets;

    /**
     * @notice Per-account mapping of "assets you are in", capped by maxAssets
     */
    mapping(address => ClToken[]) public accountAssets;
}

contract ComptrollerV2Storage is ComptrollerV1Storage {
    struct Market {
        // Whether or not this market is listed
        bool isListed;
        //  Multiplier representing the most one can borrow against their collateral in this market.
        //  For instance, 0.9 to allow borrowing 90% of collateral value.
        //  Must be between 0 and 1, and stored as a mantissa.
        uint collateralFactorMantissa;
        // Per-market mapping of "accounts in this asset"
        mapping(address => bool) accountMembership;
        // Whether or not this market receives CLR
        bool isClred;
    }

    /**
     * @notice Official mapping of clTokens -> Market metadata
     * @dev Used e.g. to determine if a market is supported
     */
    mapping(address => Market) public markets;

    /**
     * @notice The Pause Guardian can pause certain actions as a safety mechanism.
     *  Actions which allow users to remove their own assets cannot be paused.
     *  Liquidation / seizing / transfer can only be paused globally, not by market.
     */
    address public pauseGuardian;
    bool public _mintGuardianPaused;
    bool public _borrowGuardianPaused;
    bool public transferGuardianPaused;
    bool public seizeGuardianPaused;
    mapping(address => bool) public mintGuardianPaused;
    mapping(address => bool) public borrowGuardianPaused;
}

contract ComptrollerV3Storage is ComptrollerV2Storage {
    struct ClrMarketState {
        // The market's last updated clrBorrowIndex or clrSupplyIndex
        uint224 index;
        // The block number the index was last updated at
        uint32 block;
    }

    /// @notice A list of all markets
    ClToken[] public allMarkets;

    /// @notice The rate at which the flywheel distributes CLR, per block
    uint public clrRate;

    /// @notice The portion of clrRate that each market currently receives
    mapping(address => uint) public clrSpeeds;

    /// @notice The CLR market supply state for each market
    mapping(address => ClrMarketState) public clrSupplyState;

    /// @notice The CLR market borrow state for each market
    mapping(address => ClrMarketState) public clrBorrowState;

    /// @notice The CLR borrow index for each market for each supplier as of the last time they accrued CLR
    mapping(address => mapping(address => uint)) public clrSupplierIndex;

    /// @notice The CLR borrow index for each market for each borrower as of the last time they accrued CLR
    mapping(address => mapping(address => uint)) public clrBorrowerIndex;

    /// @notice The CLR accrued but not yet transferred to each user
    mapping(address => uint) public clrAccrued;
}

contract ComptrollerV4Storage is ComptrollerV3Storage {
    /// @notice The borrowCapGuardian can set borrowCaps to any number for any market.
    /// Lowering the borrow cap could disable borrowing on the given market.
    address public borrowCapGuardian;

    /// @notice Borrow caps enforced by borrowAllowed for each clToken address.
    /// Defaults to zero which corresponds to unlimited borrowing.
    mapping(address => uint) public borrowCaps;
}

contract ComptrollerV5Storage is ComptrollerV4Storage {
    /// @notice The portion of CLR that each contributor receives per block
    mapping(address => uint) public clrContributorSpeeds;

    /// @notice Last block at which a contributor's CLR rewards have been allocated
    mapping(address => uint) public lastContributorBlock;
}

contract ComptrollerV6Storage is ComptrollerV5Storage {
    /// @notice The rate at which clr is distributed to the corresponding borrow market (per block)
    mapping(address => uint) public clrBorrowSpeeds;

    /// @notice The rate at which clr is distributed to the corresponding supply market (per block)
    mapping(address => uint) public clrSupplySpeeds;
}

contract ComptrollerV7Storage is ComptrollerV6Storage {
    /// @notice Flag indicating whether the function to fix CLR accruals has been executed (RE: proposal 62 bug)
    bool public proposal65FixExecuted;

    /// @notice Accounting storage mapping account addresses to how much CLR they owe the protocol.
    mapping(address => uint) public clrReceivable;
}