import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import {
    ClErc20Delegate,
    ClErc20Delegator,
    Comptroller,
    JumpRateModel,
    Unitroller,
    WstETHMock
} from "../typechain-types";

describe("ClToken", function () {
    let deployer: HardhatEthersSigner, account1: HardhatEthersSigner;
    
    let clErc20Delegator: ClErc20Delegator;
    let clErc20Delegate: ClErc20Delegate;
    let unitroller: Unitroller;
    let comptroller: Comptroller;
    let jumpRateModel: JumpRateModel;
    let underlyingToken: WstETHMock;

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
        underlyingToken = await ethers.deployContract("WstETHMock", [
            await stETHMock.getAddress()
        ]);

        comptroller = await ethers.deployContract("Comptroller");
        unitroller = await ethers.deployContract("Unitroller");
        // set pending comptroller implementation in Unitroller and accept it in Comptroller.
        // only after that, we can pass unitroller into ClErc20Delegator initialize().
        await unitroller.setPendingImplementation(await comptroller.getAddress());
        await comptroller._become(await unitroller.getAddress());

        const blocksPerYear = 2102400n;
        jumpRateModel = await ethers.deployContract("JumpRateModel", [
            blocksPerYear,
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
            await unitroller.getAddress(),
            await jumpRateModel.getAddress(),
            initialExchangeRate,
            name,
            symbol,
            decimals,
            deployer.address,
            await clErc20Delegate.getAddress(),
            "0x"
        ]);

        // Mints underlying asset to Admin
        underlyingToken.mint(deployer.address, ethers.parseEther("10"));
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
            expect(await clErc20Delegator.comptroller()).to.equal(await unitroller.getAddress());
        });

        it("Should return correct implementation address", async () => {
            expect(await clErc20Delegator.implementation()).to.equal(await clErc20Delegate.getAddress());
        });
    });

    context("Admin Functions", () => {
        context("Set implementation", () => {
            it("Should revert if caller is not admin", async () => {
                const setImplementationTx = clErc20Delegator
                    .connect(account1)
                    .setImplementation(
                        await clErc20Delegate.getAddress(),
                        false,
                        "0x"
                    );

                await expect(setImplementationTx).to.be.revertedWithCustomError(
                    clErc20Delegator, "NotAdmin"
                );
            });

            it("Should be able to set new implementation", async () => {
                const oldImplementation = await clErc20Delegate.getAddress();
                const newImplementation = oldImplementation;

                const setImplementationTx = clErc20Delegator
                    .connect(deployer)
                    .setImplementation(
                        await clErc20Delegate.getAddress(),
                        true,
                        "0x"
                    );

                await expect(setImplementationTx).to.emit(
                    clErc20Delegator, "NewImplementation"
                ).withArgs(oldImplementation, newImplementation);
            });
        });

        context("Set pendingAdmin", () => {
            it("Should revert if caller is not admin", async () => {
                const setPendingAdminTx = clErc20Delegator
                    .connect(account1)
                    .setPendingAdmin(
                        account1.address
                    );

                await expect(setPendingAdminTx).to.be.revertedWithCustomError(
                    clErc20Delegate, "SetPendingAdminOwnerCheck"
                );
            });

            it("Should be able to set if caller is admin", async () => {
                const oldPendingAdmin = await clErc20Delegator.pendingAdmin();

                const setPendingAdminTx = clErc20Delegator
                    .connect(deployer)
                    .setPendingAdmin(
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
                    .setComptroller(
                        await unitroller.getAddress()
                    );

                await expect(setComptrollerTx).to.be.revertedWithCustomError(
                    clErc20Delegate, "SetComptrollerOwnerCheck"
                );
            });

            it("Should be able to set if caller is admin", async () => {
                const oldComptroller = await clErc20Delegator.comptroller();
                const NewComptroller = oldComptroller;

                const setComptrollerTx = clErc20Delegator
                    .connect(deployer)
                    .setComptroller(
                        await unitroller.getAddress()
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
                    .setReserveFactor(
                        newReserveFactorMantissa
                    );

                await expect(setReserveFactorTx).to.be.revertedWithCustomError(
                    clErc20Delegate, "SetReserveFactorAdminCheck"
                );
            });

            it("Should be able to set if caller is admin", async () => {
                const oldReserveFactorMantissa = await clErc20Delegator.reserveFactorMantissa();
                const newReserveFactorMantissa = ethers.WeiPerEther;

                const setReserveFactorTx = clErc20Delegator
                    .connect(deployer)
                    .setReserveFactor(
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
                    .setInterestRateModel(
                        await jumpRateModel.getAddress()
                    );

                await expect(setIrmTx).to.be.revertedWithCustomError(
                    clErc20Delegate, "SetInterestRateModelOwnerCheck"
                );
            });

            it("Should be able to set if caller is admin", async () => {
                const oldInterestRateModel = await clErc20Delegator.interestRateModel();
                const newInterestRateModel = oldInterestRateModel;

                const setIrmTx = clErc20Delegator
                    .connect(deployer)
                    .setInterestRateModel(
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
                await clErc20Delegator.connect(deployer).setPendingAdmin(
                    account1.address
                );
            });

            it("Should revert if caller is not pendingAdmin", async () => {
                const acceptAdminTx = clErc20Delegator
                    .connect(deployer)
                    .acceptAdmin();

                await expect(acceptAdminTx).to.be.revertedWithCustomError(
                    clErc20Delegate, "AcceptAdminPendingAdminCheck"
                );
            });

            it("Should be able to accept if caller is pendingAdmin", async () => {
                const oldAdmin = await clErc20Delegator.admin();
                // First set PendingAdmin
                const acceptAdminTx = clErc20Delegator
                    .connect(account1)
                    .acceptAdmin();

                await expect(acceptAdminTx).to.emit(
                    clErc20Delegator, "NewAdmin"
                ).withArgs(oldAdmin, account1.address);
            });
        });

        context("Add Reserves", () => {
            const amountToAdd = ethers.WeiPerEther;
            beforeEach(async () => {
                // Approve
                await underlyingToken.approve(clErc20Delegator, amountToAdd);
            });

            it("Should be able to add reserves", async () => {
                const totalReserves = await clErc20Delegator.totalReserves();
                const totalReservesNew = totalReserves + amountToAdd;

                const addReservesTx = clErc20Delegator
                    .connect(deployer)
                    .addReserves(
                        amountToAdd
                    );

                await expect(addReservesTx).to.emit(
                    clErc20Delegator, "ReservesAdded"
                ).withArgs(deployer.address, amountToAdd, totalReservesNew);
            });
        });

        context("Reduce Reserves", () => {
            const amount = ethers.WeiPerEther;
            beforeEach(async () => {
                await underlyingToken.approve(clErc20Delegator, amount);
                await clErc20Delegator.connect(deployer).addReserves(
                    amount
                );
            });

            it("Should revert if caller is not admin", async () => {
                const reduceReservesTx = clErc20Delegator
                    .connect(account1)
                    .reduceReserves(
                        amount
                    );

                await expect(reduceReservesTx).to.revertedWithCustomError(
                    clErc20Delegate, "ReduceReservesAdminCheck"
                );
            });

            it("Should be able to reduce reserves", async () => {
                const totalReserves = await clErc20Delegator.totalReserves();
                const totalReservesNew = totalReserves - amount;

                const reduceReservesTx = clErc20Delegator
                    .connect(deployer)
                    .reduceReserves(
                        amount
                    );

                await expect(reduceReservesTx).to.emit(
                    clErc20Delegator, "ReservesReduced"
                ).withArgs(deployer.address, amount, totalReservesNew);
            });
        });
    });
});
