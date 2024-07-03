import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import {
    ClErc20,
    ClusterToken,
    CompositeChainlinkOracle,
    PriceOracle,
    RETHMock,
    WstETHMock
} from "../typechain-types";

const { parseEther, parseUnits } = ethers;

describe("Comptroller", function () {
    let deployer: HardhatEthersSigner, user: HardhatEthersSigner;
    let comptroller: any;
    let leverage: any;
    let clWstETH: ClErc20, clRETH: ClErc20;
    let clWstETHAddr: string, clRETHAddr: string;
    let wstETHMock: WstETHMock, rETHMock: RETHMock;
    let priceOracle: PriceOracle;
    let wstETHCompositeOracle: CompositeChainlinkOracle;
    let rETHCompositeOracle: CompositeChainlinkOracle;
    let clusterToken: ClusterToken;

    const baseRatePerYear = parseEther("0.1");
    const multiplierPerYear = parseEther("0.45");
    const jumpMultiplierPerYear = parseEther("5");
    const kink = parseEther("0.9");

    const initialExchangeRate = parseEther("1");

    // Base oracle addresses
    const ETH_USD_FEED = "0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419";
    const STETH_USD_FEED = "0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8";

    // Multiplier(Quote) oracle addresses
    const RETH_ETH_FEED = "0x536218f9E9Eb48863970252233c8F271f554C2d0";
    const STETHAddr = "0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84";

    beforeEach(async () => {
        // Contracts are deployed using the first signer/account by default
        [deployer, user] = await ethers.getSigners();

        // Comptroller
        const Comptroller = await ethers.getContractFactory("Comptroller");
        comptroller = await upgrades.deployProxy(Comptroller);
        comptroller.waitForDeployment();

        // Leverage
        const Leverage = await ethers.getContractFactory("Leverage");
        leverage = await upgrades.deployProxy(Leverage, [
            await comptroller.getAddress()
        ]);
        leverage.waitForDeployment();

        const stETHMock = await ethers.deployContract("StETHMock");
        wstETHMock = await ethers.deployContract("WstETHMock", [
            await stETHMock.getAddress()
        ]);

        rETHMock = await ethers.deployContract("RETHMock");

        const blocksPerYear = 2102400n;
        const jumpRateModel = await ethers.deployContract("JumpRateModel", [
            blocksPerYear,
            baseRatePerYear,
            multiplierPerYear,
            jumpMultiplierPerYear,
            kink,
            deployer.address
        ]);
        
        // ClErc20 contract instances
        clWstETH = await ethers.deployContract("ClErc20", [
            await wstETHMock.getAddress(),
            await comptroller.getAddress(),
            await jumpRateModel.getAddress(),
            initialExchangeRate,
            "Cluster WstETH Token",
            "clWstETH",
            8,
            deployer.address
        ]);

        clRETH = await ethers.deployContract("ClErc20", [
            await rETHMock.getAddress(),
            await comptroller.getAddress(),
            await jumpRateModel.getAddress(),
            initialExchangeRate,
            "Cluster RETH Token",
            "clRETH",
            8,
            deployer.address
        ]);

        priceOracle = await ethers.deployContract("PriceOracle");

        wstETHCompositeOracle = await ethers.deployContract("CompositeChainlinkOracle", [
            STETH_USD_FEED,
            STETHAddr,
            ethers.ZeroAddress
        ]);

        rETHCompositeOracle = await ethers.deployContract("CompositeChainlinkOracle", [
            ETH_USD_FEED,
            RETH_ETH_FEED,
            ethers.ZeroAddress
        ]);
    
        clWstETHAddr = await clWstETH.getAddress();
        clRETHAddr = await clRETH.getAddress();

        clusterToken = await ethers.deployContract("ClusterToken", [
            deployer.address
        ]);

        // Initial mint; 10M CLR tokens
        await clusterToken.initialMint(deployer.address, parseEther("10000000"));
    });

    context("Deployment", () => {
        it("Should return isComptroller as true", async () => {
            expect(await comptroller.isComptroller()).to.equal(true);
        });

        it("Should set deployer as admin", async () => {
            expect(await comptroller.admin()).to.equal(deployer.address);
        });

        it("Should return unset pendingAdmin", async () => {
            expect(await comptroller.pendingAdmin()).to.equal(ethers.ZeroAddress);
        });

        it("Should return unset close factor", async () => {
            expect(await comptroller.closeFactorMantissa()).to.equal(0n);
        });
    });

    context("Admin Functions", () => {
        context("Sets pending admin", () => {
            it("Should revert if caller is not admin", async () => {
                const setPendingAdminTx = comptroller
                    .connect(user)
                    .setPendingAdmin(
                        user.address
                    );

                await expect(setPendingAdminTx).to.be.revertedWithCustomError(
                    comptroller, "NotAdmin"
                );
            });

            it("Should revert if zero address is passed", async () => {
                const setPendingAdminTx = comptroller
                    .connect(deployer)
                    .setPendingAdmin(
                        ethers.ZeroAddress
                    );

                await expect(setPendingAdminTx).to.be.revertedWithCustomError(
                    comptroller, "ZeroAddress"
                );
            });

            it("Should be able to set if caller is admin", async () => {
                const oldPendingAdmin = await comptroller.pendingAdmin();

                const setPendingAdminTx = comptroller
                    .connect(deployer)
                    .setPendingAdmin(
                        user.address
                    );

                await expect(setPendingAdminTx).to.emit(
                    comptroller, "NewPendingAdmin"
                ).withArgs(oldPendingAdmin, user.address);
            });
        });

        context("Accepts new admin", () => {
            beforeEach(async () => {
                // To accept new admin, the pending admin should be set first.
                await comptroller.connect(deployer).setPendingAdmin(
                    user.address
                );
            });

            it("Should revert if caller is not pending admin", async () => {
                const acceptAdminTx = comptroller
                    .connect(deployer)
                    .acceptAdmin();

                await expect(acceptAdminTx).to.be.revertedWithCustomError(
                    comptroller, "NotPendingAdmin"
                );
            });

            it("Should be able to accept if caller is pending admin", async () => {
                const oldAdmin = await comptroller.admin();

                const acceptAdminTx = comptroller
                    .connect(user)
                    .acceptAdmin();

                await expect(acceptAdminTx).to.emit(
                    comptroller, "NewAdmin"
                ).withArgs(oldAdmin, user.address);
            });
        });

        context("Support Market", () => {
            it("Should revert if caller is not admin", async () => {
                const supportMarketTx = comptroller
                    .connect(user)
                    .supportMarket(
                        clWstETHAddr
                    );

                await expect(supportMarketTx).to.be.revertedWithCustomError(
                    comptroller, "NotAdmin"
                );
            });

            it("Should be able to list a market", async () => {
                const supportMarketTx = comptroller
                    .connect(deployer)
                    .supportMarket(
                        clWstETHAddr
                    );

                await expect(supportMarketTx).to.emit(
                    comptroller, "MarketListed"
                ).withArgs(clWstETHAddr);

                expect(await comptroller.allMarkets(0)).to.equal(clWstETHAddr);
            });

            it("Should revert if a market is already listed", async () => {
                await comptroller.connect(deployer).supportMarket(
                    clWstETHAddr
                );
                
                const secondTx = comptroller
                    .connect(deployer)
                    .supportMarket(
                        clWstETHAddr
                    );

                await expect(secondTx).to.be.revertedWithCustomError(
                    comptroller, "MarketIsAlreadyListed"
                );
            });
        });

        context("Set price oracle", () => {
            it("Should revert if caller is not admin", async () => {
                const setOracleTx = comptroller
                    .connect(user)
                    .setPriceOracle(
                        await priceOracle.getAddress()
                    );

                await expect(setOracleTx).to.be.revertedWithCustomError(
                    comptroller, "NotAdmin"
                );
            });

            it("Should revert if passed an invalid contract address", async () => {
                await expect(comptroller.connect(deployer).setPriceOracle(
                    await comptroller.getAddress()
                )).to.be.reverted;
            });

            it("Should be able to set valid price oracle by admin", async () => {
                const oracleAddr = await priceOracle.getAddress()
                const setOracleTx = comptroller
                    .connect(deployer)
                    .setPriceOracle(
                        oracleAddr
                    );

                await expect(setOracleTx).to.emit(
                    comptroller, "NewPriceOracle"
                ).withArgs(ethers.ZeroAddress, oracleAddr);
            });
        });

        context("Set close factor", () => {
            const newCloseFactor = ethers.parseEther("0.05");
            it("Should revert if caller is not admin", async () => {
                await expect(
                    comptroller.connect(user).setCloseFactor(newCloseFactor)
                ).to.be.revertedWithCustomError(comptroller, "NotAdmin");
            });

            it("Should set new close factor and emit NewCloseFactor event", async () => {
                const oldCloseFactor = await comptroller.closeFactorMantissa();

                await expect(
                    comptroller.setCloseFactor(newCloseFactor)
                ).to.emit(comptroller, "NewCloseFactor")
                .withArgs(oldCloseFactor, newCloseFactor);
            });
        });

        context("Set collateral factor", () => {
            const newCollateralFactor = ethers.parseEther("0.8");

            beforeEach(async () => {
                // Set comptroller price oracle first
                await comptroller.connect(deployer).setPriceOracle(
                    await priceOracle.getAddress()
                );

                await comptroller.connect(deployer).supportMarket(
                    await clWstETH.getAddress()
                );
            });

            it("Should revert if caller is not admin", async () => {
                const setCollateralTx = comptroller
                    .connect(user)
                    .setCollateralFactor(
                        clWstETHAddr,
                        newCollateralFactor
                    );

                await expect(setCollateralTx).to.be.revertedWithCustomError(
                    comptroller, "NotAdmin"
                );
            });

            it("Should revert if a market is not listed", async () => {
                const setCollateralTx = comptroller
                    .connect(deployer)
                    .setCollateralFactor(
                        clRETHAddr,
                        newCollateralFactor
                    );

                await expect(setCollateralTx).to.be.revertedWithCustomError(
                    comptroller, "MarketIsNotListed"
                ).withArgs(clRETHAddr);
            });

            it("Should revert if underlying price is zero", async () => {
                const setCollateralTx = comptroller
                    .connect(deployer)
                    .setCollateralFactor(
                        clWstETHAddr,
                        newCollateralFactor
                    );
                
                await expect(setCollateralTx).to.be.revertedWithCustomError(
                    comptroller, "SetCollFactorWithoutPrice"
                );
            });

            it("Should be able to set collateral factor successfully", async () => {
                // set underlying price feed
                await priceOracle.setFeed(
                    await wstETHMock.symbol(),
                    await wstETHCompositeOracle.getAddress()
                );

                const setCollateralTx = comptroller
                    .connect(deployer)
                    .setCollateralFactor(
                        clWstETHAddr,
                        newCollateralFactor
                    );

                await expect(setCollateralTx).to.emit(
                    comptroller, "NewCollateralFactor")
                .withArgs(clWstETHAddr, 0n, newCollateralFactor);
            });
        });

        context("Set liquidation incentive", () => {
            const newIncentiveMantissa = ethers.parseEther("1.1");

            it("Should revert if caller is not admin", async () => {
                const setLiquidationIncentiveTx = comptroller
                    .connect(user)
                    .setLiquidationIncentive(
                        newIncentiveMantissa
                    )
                await expect(setLiquidationIncentiveTx).to.be.revertedWithCustomError(
                    comptroller, "NotAdmin"
                );
            });

            it("Should be able to set new liquidation incentive by admin", async () => {
                const setLiquidationIncentiveTx = comptroller
                    .connect(deployer)
                    .setLiquidationIncentive(
                        newIncentiveMantissa
                    );

                await expect(setLiquidationIncentiveTx).to.emit(
                    comptroller, "NewLiquidationIncentive")
                .withArgs(0n, newIncentiveMantissa);
            });
        });

        context("Set borrow cap guardian", () => {
            it("Should revert if caller is not admin", async () => {
                const setBorrowCapGuardianTx = comptroller
                    .connect(user)
                    .setBorrowCapGuardian(
                        user.address
                    );

                await expect(setBorrowCapGuardianTx).to.be.revertedWithCustomError(
                    comptroller, "NotAdmin"
                );
            });

            it("Should be able to set new borrow cap guardian by admin", async () => {
                const setBorrowCapGuardianTx = comptroller
                    .connect(deployer)
                    .setBorrowCapGuardian(
                        user.address
                    );

                await expect(setBorrowCapGuardianTx).to.emit(
                    comptroller, "NewBorrowCapGuardian"
                ).withArgs(ethers.ZeroAddress, user.address);
            });
        });

        context("Set pause guardian", () => {
            it("Should revert if caller is not admin", async () => {
                const setPauseGuardianTx = comptroller
                    .connect(user)
                    .setPauseGuardian(
                        user.address
                    );

                await expect(setPauseGuardianTx).to.be.revertedWithCustomError(
                    comptroller, "NotAdmin"
                );
            });

            it("Should be able to set new borrow cap guardian by admin", async () => {
                const setPauseGuardianTx = comptroller
                    .connect(deployer)
                    .setPauseGuardian(
                        user.address
                    );

                await expect(setPauseGuardianTx).to.emit(
                    comptroller, "NewPauseGuardian"
                ).withArgs(ethers.ZeroAddress, user.address);
            });
        });

        context("Set mint paused", () => {
            beforeEach(async () => {
                await comptroller.connect(deployer).supportMarket(clWstETHAddr);
            });

            it("Should revert if a market is not listed", async () => {
                const setMintPausedTx = comptroller
                    .connect(deployer)
                    .setMintPaused(
                        clRETHAddr,
                        true
                    );

                await expect(setMintPausedTx).to.be.revertedWithCustomError(
                    comptroller, "MarketIsNotListed"
                ).withArgs(clRETHAddr);
            });

            it("Should revert if caller is nether admin nor pauseGuardian", async () => {
                const setMintPausedTx = comptroller
                    .connect(user)
                    .setMintPaused(
                        clWstETHAddr,
                        true
                    );

                await expect(setMintPausedTx).to.be.revertedWithCustomError(
                    comptroller, "NotAdminOrPauseGuardian"
                );
            });

            it("Should revert if caller is not admin when state is false", async () => {
                await comptroller.connect(deployer).setPauseGuardian(user.address);
                const setMintPausedTx = comptroller
                    .connect(user)
                    .setMintPaused(
                        clWstETHAddr,
                        false
                    );

                await expect(setMintPausedTx).to.be.revertedWithCustomError(
                    comptroller, "NotAdmin"
                );
            });

            it("Should be able to pause mint action by pauseGuardian", async () => {
                await comptroller.connect(deployer).setPauseGuardian(user.address);
                const state = true;
                const setMintPausedTx = comptroller
                    .connect(user)
                    .setMintPaused(
                        clWstETHAddr,
                        state
                    );

                await expect(setMintPausedTx).to.emit(
                    comptroller, "MarketActionPaused"
                ).withArgs(clWstETHAddr, "Mint", state);
            });

            it("Should be able to pause mint action by admin", async () => {
                const state = true;

                const setMintPausedTx = comptroller
                    .connect(deployer)
                    .setMintPaused(
                        clWstETHAddr,
                        state
                    );

                await expect(setMintPausedTx).to.emit(
                    comptroller, "MarketActionPaused"
                ).withArgs(clWstETHAddr, "Mint", state);
            });

            it("Should be able to unpause mint action by admin", async () => {
                const state = false;

                const setMintPausedTx = comptroller
                    .connect(deployer)
                    .setMintPaused(
                        clWstETHAddr,
                        state
                    );

                await expect(setMintPausedTx).to.emit(
                    comptroller, "MarketActionPaused"
                ).withArgs(clWstETHAddr, "Mint", state);
            });
        });

        // Skip test for borrow paused since it's exactly same as mint paused
        context.skip("Set borrow paused", () => {});

        context("Set transfer paused", () => {
            it("Should revert if caller is nether admin nor pauseGuardian", async () => {
                const setTransferPausedTx = comptroller
                    .connect(user)
                    .setTransferPaused(
                        true
                    );

                await expect(setTransferPausedTx).to.be.revertedWithCustomError(
                    comptroller, "NotAdminOrPauseGuardian"
                );
            });

            it("Should revert if caller is not admin when state is false", async () => {
                await comptroller.connect(deployer).setPauseGuardian(user.address);
                
                const setTransferPausedTx = comptroller
                    .connect(user)
                    .setTransferPaused(
                        false
                    );

                await expect(setTransferPausedTx).to.be.revertedWithCustomError(
                    comptroller, "NotAdmin"
                );
            });

            it("Should be able to pause transfer action by pauseGuardian", async () => {
                await comptroller.connect(deployer).setPauseGuardian(user.address);

                const setTransferPausedTx = comptroller
                    .connect(user)
                    .setTransferPaused(
                        true
                    );

                await expect(setTransferPausedTx).to.emit(
                    comptroller, "ActionPaused"
                ).withArgs("Transfer", true);
            });

            it("Should be able to unpause transfer action by only admin", async () => {
                const setTransferPausedTx = comptroller
                    .connect(deployer)
                    .setTransferPaused(
                        false
                    );

                await expect(setTransferPausedTx).to.emit(
                    comptroller, "ActionPaused"
                ).withArgs("Transfer", false);
            });
        });

        // Skip test for seize paused since it's exactly same as transfer paused
        context.skip("Set seize paused", () => {});

        context("Set CLR address", () => {
            it("Should revert if caller is not admin", async () => {
                const setClrAddressTx = comptroller
                    .connect(user)
                    .setClrAddress(
                        await clusterToken.getAddress()
                    );

                await expect(setClrAddressTx).to.be.revertedWithCustomError(
                    comptroller, "NotAdmin"
                );
            });

            it("Should set new CLR address by admin", async () => {
                const clrAddr = await clusterToken.getAddress();
                const setClrTx = comptroller
                    .connect(deployer)
                    .setClrAddress(
                        clrAddr
                    );

                await expect(setClrTx).to.emit(
                    comptroller, "NewClrAddress"
                ).withArgs(ethers.ZeroAddress, clrAddr);
            });
        });

        context("Set Leverage address", () => {
            it("Should revert if caller is not admin", async () => {
                const setLeverageTx = comptroller
                    .connect(user)
                    .setLeverageAddress(
                        await leverage.getAddress()
                    );

                await expect(setLeverageTx).to.be.revertedWithCustomError(
                    comptroller, "NotAdmin"
                );
            });

            it("Should set new CLR address by admin", async () => {
                const leverageAddr = await leverage.getAddress();
                const setLeverageTx = comptroller
                    .connect(deployer)
                    .setLeverageAddress(
                        leverageAddr
                    );

                await expect(setLeverageTx).to.emit(
                    comptroller, "NewLeverageAddress"
                ).withArgs(ethers.ZeroAddress, leverageAddr);
            });
        });

        context.skip("Set market borrow caps", () => {});
        context.skip("Set CLR speed for a single contributor", () => {});
        context.skip("Set CLR borrow and supply speeds for the specified markets", () => {});

        context("Grant CLR", () => {
            const amountToTransfer = parseEther("1000");
            beforeEach(async () => {
                // The CLR Address should be set first.
                await comptroller.connect(deployer).setClrAddress(
                    await clusterToken.getAddress()
                );
            });

            it("Should revert if caller is neither admin nor new implementation", async () => {
                const grantClrTx = comptroller
                    .connect(user)
                    .grantClr(
                        user.address,
                        amountToTransfer
                    );

                await expect(grantClrTx).to.be.revertedWithCustomError(
                    comptroller, "NotAdmin"
                );
            });

            it("Should revert if there is not enough CLR", async () => {
                const grantClrTx = comptroller
                    .connect(deployer)
                    .grantClr(
                        user.address,
                        amountToTransfer
                    );
                
                await expect(grantClrTx).to.be.revertedWithCustomError(
                    comptroller, "InsufficientClrForGrant"
                );
            });

            it("Should transfer CLR to the specific recipient", async () => {
                await clusterToken.transfer(
                    await comptroller.getAddress(),
                    amountToTransfer
                );

                const grantClrTx = comptroller
                    .connect(deployer)
                    .grantClr(
                        user.address,
                        amountToTransfer
                    );

                await expect(grantClrTx).to.emit(
                    comptroller, "ClrGranted"
                ).withArgs(user.address, amountToTransfer);
            });
        });
    });

    context("View Functions", () => {
        context("getMarketInfo", () => {
            const collateralFactor = parseEther("0.8");

            beforeEach(async () => {
                // list clWstETH market
                await comptroller.connect(deployer).supportMarket(
                    clWstETHAddr
                );

                // should set underlying price feed prior to collateral factor configuration
                await priceOracle.setFeed(
                    await wstETHMock.symbol(),
                    await wstETHCompositeOracle.getAddress()
                );

                // should set price oracle
                await comptroller.connect(deployer).setPriceOracle(
                    await priceOracle.getAddress()
                );

                await comptroller.connect(deployer).setCollateralFactor(
                    clWstETHAddr,
                    collateralFactor
                );
            });

            it("Should return listed market info", async () => {
                const marketInfo = await comptroller.getMarketInfo(clWstETHAddr);
                expect(marketInfo[0]).to.equal(true);
                expect(marketInfo[1]).to.equal(collateralFactor);
            });

            it("Should return unset market info", async () => {
                const marketInfo = await comptroller.getMarketInfo(clRETHAddr);
                expect(marketInfo[0]).to.equal(false);
                expect(marketInfo[1]).to.equal(0n);
            });
        });
    });
});
