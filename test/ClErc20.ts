import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import {
    ClErc20,
    ERC20Mock,
    JumpRateModel,
    WstETHMock
} from "../typechain-types";

describe("ClToken", function () {
    let deployer: HardhatEthersSigner, account1: HardhatEthersSigner;
    
    let clErc20: ClErc20;
    let comptroller: any;
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

        const Comptroller = await ethers.getContractFactory("Comptroller");
        comptroller = await upgrades.deployProxy(Comptroller);
        comptroller.waitForDeployment();

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

        // ClErc20 contract instance
        clErc20 = await ethers.deployContract("ClErc20", [
            await underlyingToken.getAddress(),
            await comptroller.getAddress(),
            await jumpRateModel.getAddress(),
            initialExchangeRate,
            name,
            symbol,
            decimals,
            deployer.address
        ]);

        // Mints underlying asset to Admin
        underlyingToken.mint(deployer.address, ethers.parseEther("10"));
    });

    context("Deployment", () => {
        it("Should return isClToken as true", async () => {
            expect(await clErc20.isClToken()).to.equal(true);
        });

        it("Should return correct name", async () => {
            expect(await clErc20.name()).to.equal(name);
        });

        it("Should return correct symbol", async () => {
            expect(await clErc20.symbol()).to.equal(symbol);
        });

        it("Should return correct decimals", async () => {
            expect(await clErc20.decimals()).to.equal(decimals);
        });

        it("Should return correct admin", async () => {
            expect(await clErc20.admin()).to.equal(deployer.address);
        });

        it("Should return unset pendingAdmin", async () => {
            expect(await clErc20.pendingAdmin()).to.equal(ethers.ZeroAddress);
        });

        it("Should return correct comptroller address", async () => {
            expect(await clErc20.comptroller()).to.equal(await comptroller.getAddress());
        });

        it("Should return correct interestRateModel address", async () => {
            expect(await clErc20.interestRateModel()).to.equal(
                await jumpRateModel.getAddress()
            );
        });

        it("Should return correct underlying asset address", async () => {
            expect(await clErc20.underlying()).to.equal(await underlyingToken.getAddress());
        });
    });

    context("Admin Functions", () => {
        context("Set pendingAdmin", () => {
            it("Should revert if caller is not admin", async () => {
                const setPendingAdminTx = clErc20
                    .connect(account1)
                    .setPendingAdmin(
                        account1.address
                    );

                await expect(setPendingAdminTx).to.be.revertedWithCustomError(
                    clErc20, "SetPendingAdminOwnerCheck"
                );
            });

            it("Should be able to set if caller is admin", async () => {
                const oldPendingAdmin = await clErc20.pendingAdmin();

                const setPendingAdminTx = clErc20
                    .connect(deployer)
                    .setPendingAdmin(
                        account1.address
                    );

                await expect(setPendingAdminTx).to.emit(
                    clErc20, "NewPendingAdmin"
                ).withArgs(oldPendingAdmin, account1.address);
            });
        });

        context("Set Comptroller", () => {
            it("Should revert if caller is not admin", async () => {
                const setComptrollerTx = clErc20
                    .connect(account1)
                    .setComptroller(
                        await comptroller.getAddress()
                    );

                await expect(setComptrollerTx).to.be.revertedWithCustomError(
                    clErc20, "SetComptrollerOwnerCheck"
                );
            });

            it("Should be able to set if caller is admin", async () => {
                const oldComptroller = await clErc20.comptroller();
                const NewComptroller = oldComptroller;

                const setComptrollerTx = clErc20
                    .connect(deployer)
                    .setComptroller(
                        await comptroller.getAddress()
                    );

                await expect(setComptrollerTx).to.emit(
                    clErc20, "NewComptroller"
                ).withArgs(oldComptroller, NewComptroller);
            });
        });

        context("Set Reserve Factor", () => {
            it("Should revert if caller is not admin", async () => {
                const newReserveFactorMantissa = ethers.WeiPerEther;
                const setReserveFactorTx = clErc20
                    .connect(account1)
                    .setReserveFactor(
                        newReserveFactorMantissa
                    );

                await expect(setReserveFactorTx).to.be.revertedWithCustomError(
                    clErc20, "SetReserveFactorAdminCheck"
                );
            });

            it("Should be able to set if caller is admin", async () => {
                const oldReserveFactorMantissa = await clErc20.reserveFactorMantissa();
                const newReserveFactorMantissa = ethers.WeiPerEther;

                const setReserveFactorTx = clErc20
                    .connect(deployer)
                    .setReserveFactor(
                        newReserveFactorMantissa
                    );

                await expect(setReserveFactorTx).to.emit(
                    clErc20, "NewReserveFactor"
                ).withArgs(oldReserveFactorMantissa, newReserveFactorMantissa);
            });
        });

        context("Set InterestRateModel", () => {
            it("Should revert if caller is not admin", async () => {
                const setIrmTx = clErc20
                    .connect(account1)
                    .setInterestRateModel(
                        await jumpRateModel.getAddress()
                    );

                await expect(setIrmTx).to.be.revertedWithCustomError(
                    clErc20, "SetInterestRateModelOwnerCheck"
                );
            });

            it("Should be able to set if caller is admin", async () => {
                const oldInterestRateModel = await clErc20.interestRateModel();
                const newInterestRateModel = oldInterestRateModel;

                const setIrmTx = clErc20
                    .connect(deployer)
                    .setInterestRateModel(
                        await jumpRateModel.getAddress()
                    );

                await expect(setIrmTx).to.emit(
                    clErc20, "NewMarketInterestRateModel"
                ).withArgs(oldInterestRateModel, newInterestRateModel);
            });
        });

        context("Accept New Admin", () => {
            beforeEach(async () => {
                // first set PendingAdmin
                await clErc20.connect(deployer).setPendingAdmin(
                    account1.address
                );
            });

            it("Should revert if caller is not pendingAdmin", async () => {
                const acceptAdminTx = clErc20
                    .connect(deployer)
                    .acceptAdmin();

                await expect(acceptAdminTx).to.be.revertedWithCustomError(
                    clErc20, "AcceptAdminPendingAdminCheck"
                );
            });

            it("Should be able to accept if caller is pendingAdmin", async () => {
                const oldAdmin = await clErc20.admin();
                // First set PendingAdmin
                const acceptAdminTx = clErc20
                    .connect(account1)
                    .acceptAdmin();

                await expect(acceptAdminTx).to.emit(
                    clErc20, "NewAdmin"
                ).withArgs(oldAdmin, account1.address);
            });
        });

        context("Add Reserves", () => {
            const amountToAdd = ethers.WeiPerEther;
            beforeEach(async () => {
                // Approve
                await underlyingToken.approve(clErc20, amountToAdd);
            });

            it("Should be able to add reserves", async () => {
                const totalReserves = await clErc20.totalReserves();
                const totalReservesNew = totalReserves + amountToAdd;

                const addReservesTx = clErc20
                    .connect(deployer)
                    .addReserves(
                        amountToAdd
                    );

                await expect(addReservesTx).to.emit(
                    clErc20, "ReservesAdded"
                ).withArgs(deployer.address, amountToAdd, totalReservesNew);
            });
        });

        context("Reduce Reserves", () => {
            const amount = ethers.WeiPerEther;
            beforeEach(async () => {
                await underlyingToken.approve(clErc20, amount);
                await clErc20.connect(deployer).addReserves(
                    amount
                );
            });

            it("Should revert if caller is not admin", async () => {
                const reduceReservesTx = clErc20
                    .connect(account1)
                    .reduceReserves(
                        amount
                    );

                await expect(reduceReservesTx).to.revertedWithCustomError(
                    clErc20, "ReduceReservesAdminCheck"
                );
            });

            it("Should be able to reduce reserves", async () => {
                const totalReserves = await clErc20.totalReserves();
                const totalReservesNew = totalReserves - amount;

                const reduceReservesTx = clErc20
                    .connect(deployer)
                    .reduceReserves(
                        amount
                    );

                await expect(reduceReservesTx).to.emit(
                    clErc20, "ReservesReduced"
                ).withArgs(deployer.address, amount, totalReservesNew);
            });
        });

        context("Sweep accidental ERC20 transfers", () => {
            const amountToSweep = ethers.parseUnits("1000", 18);
            let erc20Mock: ERC20Mock;

            beforeEach(async () => {
                // Mock accidental ERC20 transfer
                erc20Mock = await ethers.deployContract("ERC20Mock");
                await erc20Mock.mint(
                    await clErc20.getAddress(),
                    amountToSweep
                );
            });

            it("Should revert if caller is not admin", async () => {
                const sweepTokenTx = clErc20
                    .connect(account1)
                    .sweepToken(
                        await erc20Mock.getAddress()
                    );

                await expect(sweepTokenTx).to.revertedWithCustomError(
                    clErc20, "NotAdmin"
                );
            });

            it("Should revert if sweep token is underlying", async () => {
                const sweepTokenTx = clErc20
                    .connect(deployer)
                    .sweepToken(
                        await underlyingToken.getAddress()
                    );

                await expect(sweepTokenTx).to.revertedWithCustomError(
                    clErc20, "CanNotSweepUnderlyingToken"
                );
            });

            it("Should be able to sweep accidental ERC20 tokens", async () => {
                await clErc20.connect(deployer).sweepToken(
                    await erc20Mock.getAddress()
                );

                expect(
                    await erc20Mock.balanceOf(await clErc20.getAddress())
                ).to.equal(0n);

                expect(
                    await erc20Mock.balanceOf(deployer.address)
                ).to.equal(amountToSweep);
            });
        });
    });
});
