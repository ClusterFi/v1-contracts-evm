import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import {
    ClErc20Delegate,
    ClErc20Delegator,
    Comptroller
} from "../typechain-types";

describe("Comptroller", function () {
    let deployer: HardhatEthersSigner, user: HardhatEthersSigner;
    
    let clErc20Delegator: ClErc20Delegator;
    let clErc20Delegate: ClErc20Delegate;
    let comptroller: Comptroller;
    
    const baseRatePerYear = ethers.parseEther("0.1");
    const multiplierPerYear = ethers.parseEther("0.45");
    const jumpMultiplierPerYear = ethers.parseEther("5");
    const kink = ethers.parseEther("0.9");

    const name = "Cluster WstETH Token";
    const symbol = "clWstETH";
    const decimals = 8;

    beforeEach(async () => {
        // Contracts are deployed using the first signer/account by default
        [deployer, user] = await ethers.getSigners();
        
        const stETHMock = await ethers.deployContract("StETHMock");
        const underlyingToken = await ethers.deployContract("WstETHMock", [
            await stETHMock.getAddress()
        ]);

        comptroller = await ethers.deployContract("Comptroller");
        const jumpRateModel = await ethers.deployContract("JumpRateModel", [
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
});
