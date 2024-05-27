import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { PriceOracle } from "../typechain-types";

describe("PriceOracle", function () {
    let deployer: HardhatEthersSigner, account1: HardhatEthersSigner;
    let priceOracle: PriceOracle;

    // USDC/USD Chainlink price feed.
    const USDC_Feed = "0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6";

    const USDCAddr = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";

    beforeEach(async () => {
        [deployer, account1] = await ethers.getSigners();
        // PriceOracle contract instance
        priceOracle = await ethers.deployContract("PriceOracle");
    });

    context("Deployment", () => {
        it("Should be a PriceOracle contract", async () => {
            expect(await priceOracle.isPriceOracle()).to.equal(true);
        });

        it("Should set deployer as owner", async () => {
            expect(await priceOracle.owner()).to.equal(deployer.address);
        });
    });

    context("Owner Functions", () => {
        context("Set price feed", () => {
            it("Should revert if caller is not owner", async () => {
                const setFeedTx = priceOracle
                    .connect(account1)
                    .setFeed("USDC", USDC_Feed);

                await expect(setFeedTx).to.be.revertedWithCustomError(
                    priceOracle, "OwnableUnauthorizedAccount"
                ).withArgs(account1.address);
            });

            it("Should be able to set feed address", async () => {
                const setFeedTx = priceOracle
                    .connect(deployer).setFeed("USDC", USDC_Feed);
                
                await expect(setFeedTx).to.emit(
                    priceOracle, "FeedSet"
                ).withArgs(USDC_Feed, "USDC");
            });
        });

        context("Set direct price", () => {
            it("Should revert if caller is not owner", async () => {
                const setDirectPriceTx = priceOracle
                    .connect(account1)
                    .setDirectPrice(USDCAddr, ethers.WeiPerEther);

                await expect(setDirectPriceTx).to.be.revertedWithCustomError(
                    priceOracle, "OwnableUnauthorizedAccount"
                ).withArgs(account1.address);
            });

            it("Should be able to set feed address", async () => {
                const directPrice = ethers.WeiPerEther;

                const setDirectPriceTx = priceOracle
                    .connect(deployer)
                    .setDirectPrice(USDCAddr, directPrice);
                
                await expect(setDirectPriceTx).to.emit(
                    priceOracle, "PricePosted"
                ).withArgs(USDCAddr, 0n, directPrice, directPrice);
            });
        });
    });

    context("View Functions", () => {
        context("get chainlink feed", () => {
            beforeEach(async () => {
                await priceOracle
                    .connect(deployer)
                    .setFeed("USDC", USDC_Feed);
            });

            it("Should return zero address for unknown symbol", async () => {
                const usdcFeed = await priceOracle.getFeed("USDT");
                expect(usdcFeed).to.equal(ethers.ZeroAddress);
            });

            it("Should return correct feed for known symbol", async () => {
                const usdcFeed = await priceOracle.getFeed("USDC");
                expect(usdcFeed).to.equal(USDC_Feed);
            });
        });

        context("get direct price", () => {
            const directPrice = ethers.WeiPerEther;

            beforeEach(async () => {
                await priceOracle
                .connect(deployer)
                .setDirectPrice(USDCAddr, directPrice);
            });

            it("Should return zero for unknown asset", async () => {
                const assetPrice = await priceOracle.assetPrices(account1.address);
                expect(assetPrice).to.equal(0n);
            });

            it("Should return correct feed for known symbol", async () => {
                const assetPrice = await priceOracle.assetPrices(USDCAddr);
                expect(assetPrice).to.equal(directPrice);
            });
        });
    });
});
