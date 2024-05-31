import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
  
describe("Cluster Token", function () {
    const TOTAL_SUPPLY = 10_000_000;
    // We define a fixture to reuse the same setup in every test.
    // We use loadFixture to run this setup once, snapshot that state,
    // and reset Hardhat Network to that snapshot in every test.
    async function deployClusterTokenFixture() {
      // Contracts are deployed using the first signer/account by default
      const [deployer] = await ethers.getSigners();
  
      const clusterToken = await ethers.deployContract("ClusterToken", [deployer.address]);
  
      return { clusterToken, deployer };
    }
  
    describe("Deployment", function () {
      it("Should set the right name", async function () {
        const { clusterToken } = await loadFixture(deployClusterTokenFixture);
  
        expect(await clusterToken.name()).to.equal("Cluster");
      });
  
      it("Should set the right symbol", async function () {
        const { clusterToken } = await loadFixture(deployClusterTokenFixture);
  
        expect(await clusterToken.symbol()).to.equal("CLR");
      });
  
      it("Should set the right decimal", async function () {
        const { clusterToken } = await loadFixture(deployClusterTokenFixture);
  
        expect(await clusterToken.decimals()).to.equal(18);
      });
  
      it("Should set the right total supply", async function () {
        const { clusterToken, deployer } = await loadFixture(deployClusterTokenFixture);
        
        const decimals = await clusterToken.decimals();
        const totalSupplyInDecimals = ethers.parseUnits(TOTAL_SUPPLY.toString(), decimals);
        
        expect(await clusterToken.totalSupply()).to.equal(totalSupplyInDecimals);

        const deployerBalance = await clusterToken.balanceOf(deployer.address);
        expect(deployerBalance).to.equal(totalSupplyInDecimals);
      });
    });
});
