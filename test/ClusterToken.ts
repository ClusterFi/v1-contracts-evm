import { expect } from "chai";
import { ethers } from "hardhat";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { ClusterToken } from "../typechain-types";

describe("ClusterToken", function () {
  let clusterToken: ClusterToken;

  let deployer: HardhatEthersSigner;
  let minter: HardhatEthersSigner;
  let user: HardhatEthersSigner;
  
  beforeEach(async () => {
    [deployer, minter, user] = await ethers.getSigners();

    clusterToken = await ethers.deployContract("ClusterToken", [deployer.address]);
  });
  
  context("Deployment", () => {
    it("Should return correct name", async () => {
      expect(await clusterToken.name()).to.equal("ClusterToken");
    });

    it("Should return correct symbol", async () => {
        expect(await clusterToken.symbol()).to.equal("CLR");
    });

    it("Should return correct decimals", async () => {
        expect(await clusterToken.decimals()).to.equal(18);
    });

    it("Should return correct owner", async () => {
      expect(await clusterToken.owner()).to.equal(deployer.address);
    });
  });

  context("Initial mint", () => {
    // Initial supply: 5M
    const initialSupply = ethers.parseUnits("5000000", 18);

    it("Should revert if caller is not owner", async () => {
      const initialMintTx = clusterToken
        .connect(minter)
        .initialMint(
          deployer.address,
          initialSupply
        );

      await expect(initialMintTx).to.be.revertedWithCustomError(
        clusterToken, "OwnableUnauthorizedAccount"
      ).withArgs(minter.address);
    });

    it("Should be able to call if caller is owner", async () => {
      await clusterToken.connect(deployer).initialMint(
        deployer.address,
        initialSupply
      );

      expect(await clusterToken.initialMinted()).to.equal(true);
      expect(await clusterToken.balanceOf(deployer.address)).to.equal(initialSupply);
    });

    it("Should revert if it is called more than twice", async () => {
      await clusterToken.connect(deployer).initialMint(
        deployer.address,
        initialSupply
      );

      const secondTx = clusterToken.connect(deployer).initialMint(
        deployer.address,
        initialSupply
      );

      await expect(secondTx).to.be.revertedWithCustomError(
        clusterToken, "AlreadyInitialMinted"
      );
    });
  });

  context("Mint", () => {
    const amountToMint = ethers.parseUnits("1000", 18);
    beforeEach(async () => {
      // set minter
      await clusterToken.connect(deployer).setMinter(minter.address);
    });

    it("Shound revert if caller is not minter", async () => {
      const mintTx = clusterToken
        .connect(user)
        .mint(
          user.address,
          amountToMint
        );

      await expect(mintTx).to.be.revertedWithCustomError(
        clusterToken, "OnlyMinter"
      ).withArgs(user.address);
    });

    it("Shound emit `Minted` event if caller is minter", async () => {
      const mintTx = clusterToken
        .connect(minter)
        .mint(
          user.address,
          amountToMint
        );

      await expect(mintTx).to.emit(
        clusterToken, "Minted"
      ).withArgs(minter.address, user.address, amountToMint);
    });
  });
});
