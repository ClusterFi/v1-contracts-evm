import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { CompositeChainlinkOracle } from "../typechain-types";

describe("CompositeChainlinkOracle", () => {
    let wstETHCompositeOracle: CompositeChainlinkOracle;
    let rETHCompositeOracle: CompositeChainlinkOracle;

    // Base oracle addresses
    const ETH_USD_FEED = "0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419";
    const STETH_USD_FEED = "0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8";

    // Multiplier(Quote) oracle addresses
    const RETH_ETH_FEED = "0x536218f9E9Eb48863970252233c8F271f554C2d0";
    const STETHAddr = "0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84";

    beforeEach(async () => {
        wstETHCompositeOracle = await ethers.deployContract("CompositeChainlinkOracle", [
            STETH_USD_FEED,
            STETHAddr,
            ethers.ZeroAddress
        ]);

        rETHCompositeOracle = await ethers.deployContract("CompositeChainlinkOracle", [
            ETH_USD_FEED,
            RETH_ETH_FEED,
            ethers.ZeroAddress
        ]);
    });

    context("Deployment", () => {
        it("Should return correct base oracle address", async () => {
            expect(await rETHCompositeOracle.base()).to.equal(ETH_USD_FEED);
            expect(await wstETHCompositeOracle.base()).to.equal(STETH_USD_FEED);
        });

        it("Should return correct multiplier oracle address", async () => {
            expect(await rETHCompositeOracle.multiplier()).to.equal(RETH_ETH_FEED);
            expect(await wstETHCompositeOracle.multiplier()).to.equal(STETHAddr);
        });

        it("Should return correct second multiplier oracle address", async () => {
            expect(await rETHCompositeOracle.secondMultiplier()).to.equal(ethers.ZeroAddress);
            expect(await wstETHCompositeOracle.secondMultiplier()).to.equal(ethers.ZeroAddress);
        });

        it("Should return correct decimals", async () => {
            expect(await rETHCompositeOracle.decimals()).to.equal(18n);
            expect(await wstETHCompositeOracle.decimals()).to.equal(18n);
        });
    });

    context("Get derived price", () => {
        context("wstETH price", () => {
            it("get stETH/USD price", async () => {
                const [basePrice, decimals] = await wstETHCompositeOracle.getPriceAndDecimals(STETH_USD_FEED);
                expect(decimals).to.equal(8n);

                const scaledPrice = await wstETHCompositeOracle.getPriceAndScale(STETH_USD_FEED, 18n);
                expect(scaledPrice).to.equal(ethers.parseUnits(basePrice.toString(), 10));
            });

            it("get wstETH/USD price", async () => {
                const derivedPrice = await wstETHCompositeOracle.getDerivedPrice(
                    STETH_USD_FEED, STETHAddr, 18n
                );

                const roundData = await wstETHCompositeOracle.latestRoundData();
                expect(derivedPrice).to.equal(roundData[1]);
            });
        });

        context("rETH price", () => {
            it("get rETH/ETH price", async () => {
                const [quotePrice, decimals] = await rETHCompositeOracle.getPriceAndDecimals(RETH_ETH_FEED);
                expect(decimals).to.equal(18n);

                const scaledQuotePrice = await rETHCompositeOracle.getPriceAndScale(RETH_ETH_FEED, 18);
                // if decimals is 18, the price is not scaled.
                expect(scaledQuotePrice).to.equal(quotePrice);
            });

            it("get rETH/USD price", async () => {
                const derivedPrice = await rETHCompositeOracle.getDerivedPrice(
                    ETH_USD_FEED, RETH_ETH_FEED, 18n
                );

                const roundData = await rETHCompositeOracle.latestRoundData();
                expect(derivedPrice).to.equal(roundData[1]);
            });
        });
    });
});
