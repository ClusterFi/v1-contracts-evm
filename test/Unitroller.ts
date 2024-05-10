import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { Comptroller, Unitroller } from "../typechain-types";
  
describe("Unitroller", function () {
    let deployer: HardhatEthersSigner, account1: HardhatEthersSigner;
    let unitroller: Unitroller, comptroller: Comptroller;
    
    beforeEach(async () => {
        [deployer, account1] = await ethers.getSigners();
        // Unitroller contract instance
        unitroller = await ethers.deployContract("Unitroller");
        comptroller = await ethers.deployContract("Comptroller");
    });

    context("Deployment", () => {
        it("Should set deployer as admin", async () => {
            expect(await unitroller.admin()).to.equal(deployer.address);
        });

        it("Should return unset pending admin", async () => {
            expect(await unitroller.pendingAdmin()).to.equal(ethers.ZeroAddress);
        });

        it("Should return unset comptroller implementation", async () => {
            expect(await unitroller.comptrollerImplementation()).to.equal(ethers.ZeroAddress);
        });

        it("Should return unset pending comptroller implementation", async () => {
            expect(await unitroller.pendingComptrollerImplementation()).to.equal(ethers.ZeroAddress);
        });
    });

    context("Admin Functions", () => {
        context("Sets pending comptroller implementation", () => {
            it("Should revert if caller is not admin", async () => {
                const setPendingImplTx = unitroller
                    .connect(account1)
                    .setPendingImplementation(
                        await comptroller.getAddress()
                    );

                await expect(setPendingImplTx).to.be.revertedWithCustomError(
                    unitroller, "NotAdmin"
                );
            });

            it("Should revert if zero address is passed", async () => {
                const setPendingImplTx = unitroller
                    .connect(deployer)
                    .setPendingImplementation(
                        ethers.ZeroAddress
                    );

                await expect(setPendingImplTx).to.be.revertedWithCustomError(
                    unitroller, "ZeroAddress"
                );
            });

            it("Should be able to set new pending implementation", async () => {
                const oldPendingImplementation = await unitroller.pendingComptrollerImplementation();
                const newPendingImplementation = await comptroller.getAddress();

                const setPendingImplTx = unitroller
                    .connect(deployer)
                    .setPendingImplementation(
                        newPendingImplementation
                    );

                await expect(setPendingImplTx).to.emit(
                    unitroller, "NewPendingImplementation"
                ).withArgs(oldPendingImplementation, newPendingImplementation);
            });
        });

        context("Accepts new comptroller implementation", () => {
            beforeEach(async () => {
                // To accept new implementation, the pending impl should be set first.
                await unitroller.connect(deployer).setPendingImplementation(
                    await comptroller.getAddress()
                );
            });

            it("Should revert if caller is not pending implementation", async () => {
                const acceptImplTx = unitroller
                    .connect(deployer)
                    .acceptImplementation();

                await expect(acceptImplTx).to.be.revertedWithCustomError(
                    unitroller, "NotPendingImplementation"
                );
            });

            it("Should be able to accept if caller is pending implementation", async () => {
                const oldImplementation = await unitroller.comptrollerImplementation();
                const newImplementation = await comptroller.getAddress();

                const comptrollerBecomeTx = comptroller
                    .connect(deployer)
                    ._become(unitroller);

                await expect(comptrollerBecomeTx).to.emit(
                    unitroller, "NewImplementation"
                ).withArgs(oldImplementation, newImplementation);
            });
        });

        context("Sets pending admin", () => {
            it("Should revert if caller is not admin", async () => {
                const setPendingAdminTx = unitroller
                    .connect(account1)
                    .setPendingAdmin(
                        account1.address
                    );

                await expect(setPendingAdminTx).to.be.revertedWithCustomError(
                    unitroller, "NotAdmin"
                );
            });

            it("Should revert if zero address is passed", async () => {
                const setPendingAdminTx = unitroller
                    .connect(deployer)
                    .setPendingAdmin(
                        ethers.ZeroAddress
                    );

                await expect(setPendingAdminTx).to.be.revertedWithCustomError(
                    unitroller, "ZeroAddress"
                );
            });

            it("Should be able to set if caller is admin", async () => {
                const oldPendingAdmin = await unitroller.pendingAdmin();

                const setPendingAdminTx = unitroller
                    .connect(deployer)
                    .setPendingAdmin(
                        account1.address
                    );

                await expect(setPendingAdminTx).to.emit(
                    unitroller, "NewPendingAdmin"
                ).withArgs(oldPendingAdmin, account1.address);
            });
        });

        context("Accepts new admin", () => {
            beforeEach(async () => {
                // To accept new admin, the pending admin should be set first.
                await unitroller.connect(deployer).setPendingAdmin(
                    account1.address
                );
            });

            it("Should revert if caller is not pending admin", async () => {
                const acceptAdminTx = unitroller
                    .connect(deployer)
                    .acceptAdmin();

                await expect(acceptAdminTx).to.be.revertedWithCustomError(
                    unitroller, "NotPendingAdmin"
                );
            });

            it("Should be able to accept if caller is pending admin", async () => {
                const oldAdmin = await unitroller.admin();

                const acceptAdminTx = unitroller
                    .connect(account1)
                    .acceptAdmin();

                await expect(acceptAdminTx).to.emit(
                    unitroller, "NewAdmin"
                ).withArgs(oldAdmin, account1.address);
            });
        });
    });
});
