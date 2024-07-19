// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ComptrollerStorage
 * @dev When we need to add new storage variables, we create a new version of ComptrollerStorage
 * e.g. ComptrollerStorage<versionNumber>, so finally it would look like
 * contract ComptrollerStorage is ComptrollerStorageV1, ComptrollerStorageV2
 * @author Cluster
 */
abstract contract ComptrollerStorageV1 {
    struct Market {
        // Whether or not this market is listed
        bool isListed;
        //  Multiplier representing the most one can borrow against their collateral in this market.
        //  For instance, 0.9 to allow borrowing 90% of collateral value.
        //  Must be between 0 and 1, and stored as a mantissa.
        uint256 collateralFactorMantissa;
        // Per-market mapping of "accounts in this asset"
        mapping(address => bool) accountMembership;
        // Whether or not this market receives CLR
        bool isClred;
    }

    /// @notice Administrator for this contract
    address public admin;

    /// @notice Pending administrator for this contract
    address public pendingAdmin;

    /// @notice Oracle which gives the price of any given asset
    address public oracle;

    /// @notice Multiplier used to calculate the maximum repayAmount when liquidating a borrow
    uint256 public closeFactorMantissa;

    /// @notice Multiplier representing the discount on collateral that a liquidator receives
    uint256 public liquidationIncentiveMantissa;

    /// @notice Per-account mapping of "assets you are in"
    mapping(address => address[]) public accountAssets;

    /**
     * @notice Official mapping of clTokens -> Market metadata
     * @dev Used e.g. to determine if a market is supported
     */
    mapping(address => Market) public markets;

    /**
     * @notice The borrowCapGuardian can set borrowCaps to any number for any market.
     * Lowering the borrow cap could disable borrowing on the given market.
     */
    address public borrowCapGuardian;

    /**
     * @notice Borrow caps enforced by borrowAllowed for each clToken address.
     * Defaults to zero which corresponds to unlimited borrowing.
     */
    mapping(address => uint256) public borrowCaps;

    /**
     * @notice The Pause Guardian can pause certain actions as a safety mechanism.
     * Actions which allow users to remove their own assets cannot be paused.
     * Liquidation / seizing / transfer can only be paused globally, not by market.
     */
    address public pauseGuardian;

    bool public transferGuardianPaused;

    bool public seizeGuardianPaused;

    mapping(address => bool) public mintGuardianPaused;

    mapping(address => bool) public borrowGuardianPaused;

    /// @notice A list of all markets
    address[] public allMarkets;
}

abstract contract ComptrollerStorageV2 {
    struct ClrMarketState {
        // The market's last updated clrBorrowIndex or clrSupplyIndex
        uint224 index;
        // The block number the index was last updated at
        uint32 block;
    }

    /// @notice CLR token contract address
    address public clrAddress;

    /// @notice Leverage contract address
    address public leverageAddress;

    /// @notice The portion of clrRate that each market currently receives
    mapping(address => uint256) public clrSpeeds;

    /// @notice The CLR market supply state for each market
    mapping(address => ClrMarketState) public clrSupplyState;

    /// @notice The CLR market borrow state for each market
    mapping(address => ClrMarketState) public clrBorrowState;

    /// @notice The CLR borrow index for each market for each supplier as of the last time they accrued CLR
    mapping(address => mapping(address => uint256)) public clrSupplierIndex;

    /// @notice The CLR borrow index for each market for each borrower as of the last time they accrued CLR
    mapping(address => mapping(address => uint256)) public clrBorrowerIndex;

    /// @notice The CLR accrued but not yet transferred to each user
    mapping(address => uint256) public clrAccrued;

    /// @notice The portion of CLR that each contributor receives per block
    mapping(address => uint256) public clrContributorSpeeds;

    /// @notice Last block at which a contributor's CLR rewards have been allocated
    mapping(address => uint256) public lastContributorBlock;

    /// @notice The rate at which clr is distributed to the corresponding borrow market (per block)
    mapping(address => uint256) public clrBorrowSpeeds;

    /// @notice The rate at which clr is distributed to the corresponding supply market (per block)
    mapping(address => uint256) public clrSupplySpeeds;

    /// @notice The rate at which the flywheel distributes CLR, per block
    uint256 public clrRate;
}

// solhint-disable-next-line no-empty-blocks
abstract contract ComptrollerStorage is ComptrollerStorageV1, ComptrollerStorageV2 {}
