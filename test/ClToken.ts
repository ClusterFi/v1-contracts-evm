import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import {
    ClErc20Delegate,
    ClErc20Delegator,
    Comptroller,
    JumpRateModel
} from "../typechain-types";

describe("ClToken", function () {
    let deployer: HardhatEthersSigner, account1: HardhatEthersSigner;
    
    let clErc20Delegator: ClErc20Delegator;
    let clErc20Delegate: ClErc20Delegate;
    let comptroller: Comptroller;
    let jumpRateModel: JumpRateModel;

    const baseRatePerYear = ethers.parseEther("0.1");
    const multiplierPerYear = ethers.parseEther("0.45");
    const jumpMultiplierPerYear = ethers.parseEther("5");
    const kink = ethers.parseEther("0.9");

    const name = "Cluster WstETH Token";
    const symbol = "clWstETH";
    const decimals = 8;

    beforeEach(async () => {
        // Contracts are deployed using the first signer/account by default
        [deployer, account1] = await ethers.getSigners();
        
        const stETHMock = await ethers.deployContract("StETHMock");
        const underlyingToken = await ethers.deployContract("WstETHMock", [
            await stETHMock.getAddress()
        ]);

        comptroller = await ethers.deployContract("Comptroller");
        jumpRateModel = await ethers.deployContract("JumpRateModel", [
            baseRatePerYear,
            multiplierPerYear,
            jumpMultiplierPerYear,
            kink,
            deployer.address
        ]);
        const initialExchangeRate = ethers.parseEther("1");
        clErc20Delegate = await ethers.deployContract("ClErc20Delegate");

        // ClErc20Delegator contract instance
        clErc20Delegator = await ethers.deployContract("ClErc20Delegator", [
            await underlyingToken.getAddress(),
            await comptroller.getAddress(),
            await jumpRateModel.getAddress(),
            initialExchangeRate,
            name,
            symbol,
            decimals,
            deployer.address,
            await clErc20Delegate.getAddress(),
            "0x"
        ]);
    });

    context("Deployment", () => {
        it("Should return isClToken as true", async () => {
            expect(await clErc20Delegator.isClToken()).to.equal(true);
        });

        it("Should return correct name", async () => {
            expect(await clErc20Delegator.name()).to.equal(name);
        });

        it("Should return correct symbol", async () => {
            expect(await clErc20Delegator.symbol()).to.equal(symbol);
        });

        it("Should return correct decimals", async () => {
            expect(await clErc20Delegator.decimals()).to.equal(decimals);
        });

        it("Should return correct admin", async () => {
            expect(await clErc20Delegator.admin()).to.equal(deployer.address);
        });

        it("Should return unset pendingAdmin", async () => {
            expect(await clErc20Delegator.pendingAdmin()).to.equal(ethers.ZeroAddress);
        });

        it("Should return correct comptroller address", async () => {
            expect(await clErc20Delegator.comptroller()).to.equal(await comptroller.getAddress());
        });

        it("Should return correct implementation address", async () => {
            expect(await clErc20Delegator.implementation()).to.equal(await clErc20Delegate.getAddress());
        });
    });

    context("Admin Functions", () => {
        context("Set pendingAdmin", () => {
            it("Should revert if caller is not admin", async () => {
                const setPendingAdminTx = clErc20Delegator
                    .connect(account1)
                    ._setPendingAdmin(
                        account1.address
                    );

                await expect(setPendingAdminTx).to.be.reverted;
            });

            it("Should be able to set if caller is admin", async () => {
                const oldPendingAdmin = await clErc20Delegator.pendingAdmin();

                const setPendingAdminTx = clErc20Delegator
                    .connect(deployer)
                    ._setPendingAdmin(
                        account1.address
                    );

                await expect(setPendingAdminTx).to.emit(
                    clErc20Delegator, "NewPendingAdmin"
                ).withArgs(oldPendingAdmin, account1.address);
            });
        });

        context("Set Comptroller", () => {
            it("Should revert if caller is not admin", async () => {
                const setComptrollerTx = clErc20Delegator
                    .connect(account1)
                    ._setComptroller(
                        await comptroller.getAddress()
                    );

                await expect(setComptrollerTx).to.be.reverted;
            });

            it("Should be able to set if caller is admin", async () => {
                const oldComptroller = await clErc20Delegator.comptroller();
                const NewComptroller = oldComptroller;

                const setComptrollerTx = clErc20Delegator
                    .connect(deployer)
                    ._setComptroller(
                        await comptroller.getAddress()
                    );

                await expect(setComptrollerTx).to.emit(
                    clErc20Delegator, "NewComptroller"
                ).withArgs(oldComptroller, NewComptroller);
            });
        });

        context("Set Reserve Factor", () => {
            it("Should revert if caller is not admin", async () => {
                const newReserveFactorMantissa = ethers.WeiPerEther;
                const setReserveFactorTx = clErc20Delegator
                    .connect(account1)
                    ._setReserveFactor(
                        newReserveFactorMantissa
                    );

                await expect(setReserveFactorTx).to.be.reverted;
            });

            it("Should be able to set if caller is admin", async () => {
                const oldReserveFactorMantissa = await clErc20Delegator.reserveFactorMantissa();
                const newReserveFactorMantissa = ethers.WeiPerEther;

                const setReserveFactorTx = clErc20Delegator
                    .connect(deployer)
                    ._setReserveFactor(
                        newReserveFactorMantissa
                    );

                await expect(setReserveFactorTx).to.emit(
                    clErc20Delegator, "NewReserveFactor"
                ).withArgs(oldReserveFactorMantissa, newReserveFactorMantissa);
            });
        });

        context("Set InterestRateModel", () => {
            it("Should revert if caller is not admin", async () => {
                const setIrmTx = clErc20Delegator
                    .connect(account1)
                    ._setInterestRateModel(
                        await jumpRateModel.getAddress()
                    );

                await expect(setIrmTx).to.be.reverted;
            });

            it("Should be able to set if caller is admin", async () => {
                const oldInterestRateModel = await clErc20Delegator.interestRateModel();
                const newInterestRateModel = oldInterestRateModel;

                const setIrmTx = clErc20Delegator
                    .connect(deployer)
                    ._setInterestRateModel(
                        await jumpRateModel.getAddress()
                    );

                await expect(setIrmTx).to.emit(
                    clErc20Delegator, "NewMarketInterestRateModel"
                ).withArgs(oldInterestRateModel, newInterestRateModel);
            });
        });

        context("Accept New Admin", () => {
            beforeEach(async () => {
                // first set PendingAdmin
                await clErc20Delegator.connect(deployer)._setPendingAdmin(
                    account1.address
                );
            });

            it("Should revert if caller is not pendingAdmin", async () => {
                const acceptAdminTx = clErc20Delegator
                    .connect(deployer)
                    ._acceptAdmin();

                await expect(acceptAdminTx).to.be.reverted;
            });

            it("Should be able to accept if caller is pendingAdmin", async () => {
                const oldAdmin = await clErc20Delegator.admin();
                // First set PendingAdmin
                const acceptAdminTx = clErc20Delegator
                    .connect(account1)
                    ._acceptAdmin();

                await expect(acceptAdminTx).to.emit(
                    clErc20Delegator, "NewAdmin"
                ).withArgs(oldAdmin, account1.address);
            });
        });
    });
});
