import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import {
    ClErc20,
    CompositeChainlinkOracle,
    Comptroller,
    PriceOracle,
    RETHMock,
    WstETHMock
} from "../typechain-types";

describe("Comptroller", function () {
    let deployer: HardhatEthersSigner, user: HardhatEthersSigner;
    let comptroller: Comptroller;
    let clWstETH: ClErc20, clRETH: ClErc20;
    let clWstETHAddr: string, clRETHAddr: string;
    let wstETHMock: WstETHMock, rETHMock: RETHMock;
    let priceOracle: PriceOracle;
    let wstETHCompositeOracle: CompositeChainlinkOracle;
    let rETHCompositeOracle: CompositeChainlinkOracle;

    const baseRatePerYear = ethers.parseEther("0.1");
    const multiplierPerYear = ethers.parseEther("0.45");
    const jumpMultiplierPerYear = ethers.parseEther("5");
    const kink = ethers.parseEther("0.9");

    const initialExchangeRate = ethers.parseEther("1");

    // Base oracle addresses
    const ETH_USD_FEED = "0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419";
    const STETH_USD_FEED = "0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8";

    // Multiplier(Quote) oracle addresses
    const RETH_ETH_FEED = "0x536218f9E9Eb48863970252233c8F271f554C2d0";
    const STETHAddr = "0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84";

    beforeEach(async () => {
        // Contracts are deployed using the first signer/account by default
        [deployer, user] = await ethers.getSigners();
        // Comptroller contract instance
        comptroller = await ethers.deployContract("Comptroller");

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
        context("Support Market", () => {
            it("Should revert if caller is not admin", async () => {
                const supportMarketTx = comptroller
                    .connect(user)
                    .supportMarket(
                        await clWstETH.getAddress()
                    );

                await expect(supportMarketTx).to.be.revertedWithCustomError(
                    comptroller, "NotAdmin"
                );
            });

            it("Should be able to list a market", async () => {
                const marketAddr = await clWstETH.getAddress();
                const supportMarketTx = comptroller
                    .connect(deployer)
                    .supportMarket(
                        marketAddr
                    );

                await expect(supportMarketTx).to.emit(
                    comptroller, "MarketListed"
                ).withArgs(marketAddr);

                expect(await comptroller.allMarkets(0)).to.equal(marketAddr);
            });

            it("Should revert if a market is already listed", async () => {
                const marketAddr = await clWstETH.getAddress();

                await comptroller.connect(deployer).supportMarket(
                    marketAddr
                );
                
                const secondTx = comptroller
                    .connect(deployer)
                    .supportMarket(
                        marketAddr
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
                console.log(await wstETHCompositeOracle.latestRoundData());
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

        context.skip("Set market borrow caps", () => {});

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

            it.skip("Should be able to pause mint by pauseGuardian", async () => {
                await comptroller.connect(deployer).setPauseGuardian(user.address);
                const state = true;
                const setMintPausedTx = comptroller
                    .connect(user)
                    .setMintPaused(
                        clWstETHAddr,
                        state
                    );

                await expect(setMintPausedTx).to.emit(
                    comptroller, "ActionPaused"
                ).withArgs(clWstETHAddr, "Mint", state);
            });

            it.skip("Should be able to pause mint by admin", async () => {
                const state = true;

                const setMintPausedTx = comptroller
                    .connect(deployer)
                    .setMintPaused(
                        clWstETHAddr,
                        state
                    );

                await expect(setMintPausedTx).to.emit(
                    comptroller, "ActionPaused"
                ).withArgs(clWstETHAddr, "Mint", state);
            });

            it.skip("Should be able to unpause mint by admin", async () => {
                const state = false;

                const setMintPausedTx = comptroller
                    .connect(deployer)
                    .setMintPaused(
                        clWstETHAddr,
                        state
                    );

                await expect(setMintPausedTx).to.emit(
                    comptroller, "ActionPaused"
                ).withArgs(clWstETHAddr, "Mint", state);
            });
        });
    });
});
