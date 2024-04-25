import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { Comptroller } from "../typechain-types";
  
describe("Comptroller", function () {
    let deployer: HardhatEthersSigner, user: HardhatEthersSigner;
    let comptroller: Comptroller;
    
    const newCloseFactor = ethers.parseEther("0.05");

    beforeEach(async () => {
        // Contracts are deployed using the first signer/account by default
        [deployer, user] = await ethers.getSigners();
        // Comptroller contract instance
        comptroller = await ethers.deployContract("Comptroller");
    });

    context("Deployment", () => {
        it("Should set deployer as admin", async () => {
            expect(await comptroller.admin()).to.equal(deployer.address);
        });

        it("Should return unset close factor", async () => {
            expect(await comptroller.closeFactorMantissa()).to.equal(0n);
        });
    });

    context("Set close factor", function () {
        it("should revert if caller is not admin", async () => {
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
});
