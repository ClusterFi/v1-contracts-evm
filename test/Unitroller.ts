import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { Unitroller } from "../typechain-types";
  
describe("Comptroller", function () {
    let deployer: HardhatEthersSigner, user: HardhatEthersSigner;
    let unitroller: Unitroller;
    
    beforeEach(async () => {
        [deployer, user] = await ethers.getSigners();
        // Unitroller contract instance
        unitroller = await ethers.deployContract("Unitroller");
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
});
