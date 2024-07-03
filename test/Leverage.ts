import { expect } from "chai";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { ethers, network, upgrades } from "hardhat";
import { 
    ClErc20,
    CompositeChainlinkOracle,
    IERC20,
    PriceOracle
} from "../typechain-types";

const { parseEther } = ethers;

describe("Leverage", function () {
    let deployer: HardhatEthersSigner, user1: HardhatEthersSigner;
    let comptroller: any;
    let leverage: any;
    let clWstETH: ClErc20;
    let wstETH: IERC20;
    let clWstETHAddr: string;
    let priceOracle: PriceOracle;
    let wstETHCompositeOracle: CompositeChainlinkOracle;
    
    const baseRatePerYear = parseEther("0.1");
    const multiplierPerYear = parseEther("0.45");
    const jumpMultiplierPerYear = parseEther("5");
    const kink = parseEther("0.9");

    const initialExchangeRate = parseEther("1");

    const wstETHAddr = "0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0";
    // wstETH holder
    const user1Addr = "0x0E774BBed46B477538f5b34c8618858d3d86e530";

    // Base oracle address
    const STETH_USD_FEED = "0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8";
    // Multiplier(Quote) oracle address
    const STETHAddr = "0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84";

    beforeEach(async () => {
        [deployer] = await ethers.getSigners();

        const Comptroller = await ethers.getContractFactory("Comptroller");
        comptroller = await upgrades.deployProxy(Comptroller);
        comptroller.waitForDeployment();

        const Leverage = await ethers.getContractFactory("Leverage");
        leverage = await upgrades.deployProxy(Leverage, [
            await comptroller.getAddress()
        ]);
        leverage.waitForDeployment();

        const blocksPerYear = 2102400n;
        const jumpRateModel = await ethers.deployContract("JumpRateModel", [
            blocksPerYear,
            baseRatePerYear,
            multiplierPerYear,
            jumpMultiplierPerYear,
            kink,
            deployer.address
        ]);

        wstETH = await ethers.getContractAt("IERC20", wstETHAddr);

        clWstETH = await ethers.deployContract("ClErc20", [
            wstETHAddr,
            await comptroller.getAddress(),
            await jumpRateModel.getAddress(),
            initialExchangeRate,
            "Cluster WstETH Token",
            "clWstETH",
            8,
            deployer.address
        ]);
        clWstETHAddr = await clWstETH.getAddress();

        wstETHCompositeOracle = await ethers.deployContract("CompositeChainlinkOracle", [
            STETH_USD_FEED,
            STETHAddr,
            ethers.ZeroAddress
        ]);

        priceOracle = await ethers.deployContract("PriceOracle");
        
        // set price oracle
        await comptroller.connect(deployer).setPriceOracle(
            await priceOracle.getAddress()
        );

        // set underlying price feeds
        await priceOracle.setFeed(
            "wstETH",
            await wstETHCompositeOracle.getAddress()
        );

        // impersonating
        await network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [user1Addr],
        });

        // get signer
        user1 = await ethers.getSigner(user1Addr);
    });

    context("Deployment", () => {
        it("Should set deployer as initial owner", async () => {
            expect(await leverage.owner()).to.equal(deployer.address);
        });

        it("Should return correct comptroller address", async () => {
            expect(await leverage.comptroller()).to.equal(
                await comptroller.getAddress()
            );
        });
    });

    context("Ownable Functions", () => {
        context("Add market", () => {
            it("should revert if caller is not owner", async () => {
                const addMarketTx = leverage.connect(user1).addMarket(
                    clWstETHAddr
                );

                await expect(addMarketTx).to.revertedWithCustomError(
                    leverage, "OwnableUnauthorizedAccount"
                ).withArgs(user1.address);
            });

            it("should revert if invalid market address is passed", async () => {
                const addMarketTx = leverage.connect(deployer).addMarket(
                    ethers.ZeroAddress
                );

                await expect(addMarketTx).to.revertedWithCustomError(
                    leverage, "InvalidMarket"
                );
            });

            it("should revert if market is not listed", async () => {
                const addMarketTx = leverage.connect(deployer).addMarket(
                    clWstETHAddr
                );

                await expect(addMarketTx).to.revertedWithCustomError(
                    leverage, "MarketIsNotListed"
                );
            });

            it("should be able to add market for leverage", async () => {
                await comptroller.supportMarket(clWstETHAddr);

                const addMarketTx = leverage.connect(deployer).addMarket(
                    clWstETHAddr
                );

                await expect(addMarketTx).to.emit(
                    leverage, "AddMarket"
                ).withArgs(clWstETHAddr, wstETHAddr);

                expect(await leverage.allowedTokens(wstETHAddr)).to.equal(true);
                expect(await leverage.clTokenMapping(wstETHAddr)).to.equal(clWstETHAddr);
            });

            it("should revert if market is already allowed", async () => {
                await comptroller.supportMarket(clWstETHAddr);
                await leverage.addMarket(clWstETHAddr);
                const addMarketTx = leverage.connect(deployer).addMarket(
                    clWstETHAddr
                );

                await expect(addMarketTx).to.revertedWithCustomError(
                    leverage, "AlreadyAllowedMarket"
                );
            });
        });

        context("Remove market", () => {
            it("should revert if caller is not owner", async () => {
                const removeMarketTx = leverage.connect(user1).removeMarket(
                    clWstETHAddr
                );

                await expect(removeMarketTx).to.revertedWithCustomError(
                    leverage, "OwnableUnauthorizedAccount"
                ).withArgs(user1.address);
            });

            it("should revert if invalid market address is passed", async () => {
                const removeMarketTx = leverage.connect(deployer).removeMarket(
                    ethers.ZeroAddress
                );

                await expect(removeMarketTx).to.revertedWithCustomError(
                    leverage, "InvalidMarket"
                );
            });

            it("should revert if passed market is not allowed", async () => {
                const removeMarketTx = leverage.connect(deployer).removeMarket(
                    clWstETHAddr
                );

                await expect(removeMarketTx).to.revertedWithCustomError(
                    leverage, "NotAllowedMarket"
                );
            });

            it("should be able to remove existing market", async () => {
                await comptroller.supportMarket(clWstETHAddr);
                await leverage.addMarket(clWstETHAddr);

                const removeMarketTx = leverage.connect(deployer).removeMarket(
                    clWstETHAddr
                );

                await expect(removeMarketTx).to.emit(
                    leverage, "RemoveMarket"
                ).withArgs(clWstETHAddr, wstETHAddr);

                expect(await leverage.allowedTokens(wstETHAddr)).to.equal(false);
                expect(await leverage.clTokenMapping(wstETHAddr)).to.equal(ethers.ZeroAddress);
            });
        });
    });

    context("Leverage Function", () => {
        const divisor = 10000n;
        const amount = parseEther("1");
        const collateralFactor = parseEther("0.8");

        beforeEach(async () => {
            await comptroller.supportMarket(clWstETHAddr);
            // set collateral factor
            await comptroller.connect(deployer).setCollateralFactor(
                clWstETHAddr,
                collateralFactor
            );
            await comptroller.setLeverageAddress(await leverage.getAddress());
            await comptroller.connect(user1).enterMarkets([clWstETHAddr]);
        });

        context("Add market", () => {
            it("Should revert if market is not allowed", async () => {
                const loopTx = leverage.connect(user1).loop(
                    wstETHAddr,
                    amount,
                    amount
                );

                await expect(loopTx).to.revertedWithCustomError(
                    leverage, "NotAllowedMarket"
                );
            });
        });

        context("User has no supply position", () => {
            beforeEach(async () => {
                await leverage.connect(deployer).addMarket(clWstETHAddr);
            });

            it("Should only supply without flashloan if borrow amount is 0 (i.e. 1x)", async () => {
                await wstETH.connect(user1).approve(await leverage.getAddress(), amount);
                await leverage.connect(user1).loop(wstETHAddr, amount, 0);

                expect(await clWstETH.balanceOf(user1.address)).to.equal(amount);
                expect(await clWstETH.borrowBalanceStored(user1.address));
            });

            it("Should have both supply and borrow positions if leverage ratio > 1x", async () => {
                const leverageRatio = 15000n; // 1.5x
                // collateral * (LR - 1) / LR
                const borrowAmount = amount * (leverageRatio - divisor) / leverageRatio;
                await wstETH.connect(user1).approve(await leverage.getAddress(), amount + borrowAmount);
                await leverage.connect(user1).loop(wstETHAddr, amount, borrowAmount);
            });
        });
    });
});
