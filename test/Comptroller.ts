import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { ClErc20Delegator, Comptroller } from "../typechain-types";
  
describe("Comptroller", function () {
    let deployer: HardhatEthersSigner, user: HardhatEthersSigner;
    let comptroller: Comptroller;
    let clErc20Delegator: ClErc20Delegator;

    const baseRatePerYear = ethers.parseEther("0.1");
    const multiplierPerYear = ethers.parseEther("0.45");
    const jumpMultiplierPerYear = ethers.parseEther("5");
    const kink = ethers.parseEther("0.9");

    const initialExchangeRate = ethers.parseEther("1");

    beforeEach(async () => {
        // Contracts are deployed using the first signer/account by default
        [deployer, user] = await ethers.getSigners();
        // Comptroller contract instance
        comptroller = await ethers.deployContract("Comptroller");

        // ClToken contract instance (ClErc20Delegator as proxy)
        const stETHMock = await ethers.deployContract("StETHMock");
        const underlyingToken = await ethers.deployContract("WstETHMock", [
            await stETHMock.getAddress()
        ]);

        const blocksPerYear = 2102400n;
        const jumpRateModel = await ethers.deployContract("JumpRateModel", [
            blocksPerYear,
            baseRatePerYear,
            multiplierPerYear,
            jumpMultiplierPerYear,
            kink,
            deployer.address
        ]);
        
        const clErc20Delegate = await ethers.deployContract("ClErc20Delegate");

        // ClErc20Delegator contract instance
        clErc20Delegator = await ethers.deployContract("ClErc20Delegator", [
            await underlyingToken.getAddress(),
            await comptroller.getAddress(),
            await jumpRateModel.getAddress(),
            initialExchangeRate,
            "Cluster WstETH Token",
            "clWstETH",
            8,
            deployer.address,
            await clErc20Delegate.getAddress(),
            "0x"
        ]);
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
                    ._supportMarket(
                        await clErc20Delegator.getAddress()
                    );

                await expect(supportMarketTx).to.be.revertedWithCustomError(
                    comptroller, "NotAdmin"
                );
            });

            it("Should be able to list a market", async () => {
                const marketAddr = await clErc20Delegator.getAddress();
                const supportMarketTx = comptroller
                    .connect(deployer)
                    ._supportMarket(
                        marketAddr
                    );

                await expect(supportMarketTx).to.emit(
                    comptroller, "MarketListed"
                ).withArgs(marketAddr);
            });

            it("Should revert if a market is already listed", async () => {
                const marketAddr = await clErc20Delegator.getAddress();

                await comptroller.connect(deployer)._supportMarket(
                    marketAddr
                );
                
                const secondTx = comptroller
                    .connect(deployer)
                    ._supportMarket(
                        marketAddr
                    );

                await expect(secondTx).to.be.revertedWithCustomError(
                    comptroller, "MarketIsAlreadyListed"
                );
            });
        });

        context("Set close factor", () => {
            const newCloseFactor = ethers.parseEther("0.05");
            it("Should revert if caller is not admin", async () => {
                await expect(
                    comptroller.connect(user)._setCloseFactor(newCloseFactor)
                ).to.be.revertedWithCustomError(comptroller, "NotAdmin");
            });

            it("Should set new close factor and emit NewCloseFactor event", async () => {
                const oldCloseFactor = await comptroller.closeFactorMantissa();

                await expect(
                    comptroller._setCloseFactor(newCloseFactor)
                ).to.emit(comptroller, "NewCloseFactor")
                .withArgs(oldCloseFactor, newCloseFactor);
            });
        });

        context("Set collateral factor", () => {
            const newCollateralFactor = ethers.parseEther("0.8");
            it("Should revert if caller is not admin", async () => {
                const marketAddr = await clErc20Delegator.getAddress();
                const setCollateralTx = comptroller
                    .connect(user)
                    ._setCollateralFactor(
                        marketAddr,
                        newCollateralFactor
                    )
                await expect(setCollateralTx).to.be.revertedWithCustomError(
                    comptroller, "NotAdmin"
                );
            });

            it("Should revert if a market is not listed", async () => {
                const marketAddr = await clErc20Delegator.getAddress();
                const setCollateralTx = comptroller
                    .connect(deployer)
                    ._setCollateralFactor(
                        marketAddr,
                        newCollateralFactor
                    )
                await expect(setCollateralTx).to.be.revertedWithCustomError(
                    comptroller, "MarketIsNotListed"
                );
            });
        });
    });
});
