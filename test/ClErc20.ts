import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import {
    ClErc20,
    ERC20Mock,
    PriceOracle,
    JumpRateModel,
    WstETHMock,
    CompositeChainlinkOracle,
    RETHMock
} from "../typechain-types";

const { parseEther, parseUnits } = ethers;

describe("ClToken", function () {
    let deployer: HardhatEthersSigner, account1: HardhatEthersSigner;
    
    let clWstETH: ClErc20, clRETH: ClErc20;
    let clWstETHAddr: string, clRETHAddr: string;
    let comptroller: any;
    let leverage: any;
    let priceOracle: PriceOracle;
    let jumpRateModel: JumpRateModel;
    let wstETH: WstETHMock, rETH: RETHMock;
    let wstETHCompositeOracle: CompositeChainlinkOracle;
    let rETHCompositeOracle: CompositeChainlinkOracle;

    const baseRatePerYear = parseEther("0.1");
    const multiplierPerYear = parseEther("0.45");
    const jumpMultiplierPerYear = parseEther("5");
    const kink = parseEther("0.9");

    // Base oracle addresses
    const ETH_USD_FEED = "0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419";
    const STETH_USD_FEED = "0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8";

    // Multiplier(Quote) oracle addresses
    const RETH_ETH_FEED = "0x536218f9E9Eb48863970252233c8F271f554C2d0";
    const STETHAddr = "0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84";

    const collateralFactor = parseEther("0.8");
    const closeFactor = parseEther("0.6");

    beforeEach(async () => {
        // Contracts are deployed using the first signer/account by default
        [deployer, account1] = await ethers.getSigners();
        
        const stETHMock = await ethers.deployContract("StETHMock");
        wstETH = await ethers.deployContract("WstETHMock", [
            await stETHMock.getAddress()
        ]);
        rETH = await ethers.deployContract("RETHMock");

        const Comptroller = await ethers.getContractFactory("Comptroller");
        comptroller = await upgrades.deployProxy(Comptroller);
        comptroller.waitForDeployment();

        const Leverage = await ethers.getContractFactory("Leverage");
        leverage = await upgrades.deployProxy(Leverage, [
            await comptroller.getAddress()
        ]);
        leverage.waitForDeployment();

        // set price oracle in Comptroller
        priceOracle = await ethers.deployContract("PriceOracle");
        
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

        const blocksPerYear = 2102400n;
        jumpRateModel = await ethers.deployContract("JumpRateModel", [
            blocksPerYear,
            baseRatePerYear,
            multiplierPerYear,
            jumpMultiplierPerYear,
            kink,
            deployer.address
        ]);
        // Exchange rate is 1:1 for tests
        const initialExchangeRate = parseUnits("1", 18);

        // ClErc20 contract instances
        clWstETH = await ethers.deployContract("ClErc20", [
            await wstETH.getAddress(),
            await comptroller.getAddress(),
            await jumpRateModel.getAddress(),
            initialExchangeRate,
            "Cluster WstETH Token",
            "clWstETH",
            8,
            deployer.address
        ]);

        clRETH = await ethers.deployContract("ClErc20", [
            await rETH.getAddress(),
            await comptroller.getAddress(),
            await jumpRateModel.getAddress(),
            initialExchangeRate,
            "Cluster RETH Token",
            "clRETH",
            8,
            deployer.address
        ]);

        clWstETHAddr = await clWstETH.getAddress();
        clRETHAddr = await clRETH.getAddress();

        // Mints underlying asset to Admin
        await wstETH.mint(deployer.address, parseEther("1000"));
        await rETH.mint(parseEther("1000"), deployer.address);

        // set price oracle
        await comptroller.connect(deployer).setPriceOracle(await priceOracle.getAddress());
        // set underlying price feeds
        await priceOracle.setFeed(
            await wstETH.symbol(),
            await wstETHCompositeOracle.getAddress()
        );
        await priceOracle.setFeed(
            await rETH.symbol(),
            await rETHCompositeOracle.getAddress()
        );
        // list markets
        await comptroller.connect(deployer).supportMarket(clWstETHAddr);
        await comptroller.connect(deployer).supportMarket(clRETHAddr);
        // set collateral factor
        await comptroller.connect(deployer).setCollateralFactor(
            clWstETHAddr,
            collateralFactor
        );
        // set collateral factor
        await comptroller.connect(deployer).setCollateralFactor(
            clRETHAddr,
            collateralFactor
        );
    });

    context("Deployment", () => {
        it("Should return isClToken as true", async () => {
            expect(await clWstETH.isClToken()).to.equal(true);
        });

        it("Should return correct name", async () => {
            expect(await clWstETH.name()).to.equal("Cluster WstETH Token");
        });

        it("Should return correct symbol", async () => {
            expect(await clWstETH.symbol()).to.equal("clWstETH");
        });

        it("Should return correct decimals", async () => {
            expect(await clWstETH.decimals()).to.equal(8);
        });

        it("Should return correct admin", async () => {
            expect(await clWstETH.admin()).to.equal(deployer.address);
        });

        it("Should return unset pendingAdmin", async () => {
            expect(await clWstETH.pendingAdmin()).to.equal(ethers.ZeroAddress);
        });

        it("Should return correct comptroller address", async () => {
            expect(await clWstETH.comptroller()).to.equal(await comptroller.getAddress());
        });

        it("Should return correct interestRateModel address", async () => {
            expect(await clWstETH.interestRateModel()).to.equal(
                await jumpRateModel.getAddress()
            );
        });

        it("Should return correct underlying asset address", async () => {
            expect(await clWstETH.underlying()).to.equal(await wstETH.getAddress());
        });
    });

    context("Admin functions", () => {
        context("Set pendingAdmin", () => {
            it("Should revert if caller is not admin", async () => {
                const setPendingAdminTx = clWstETH
                    .connect(account1)
                    .setPendingAdmin(
                        account1.address
                    );

                await expect(setPendingAdminTx).to.be.revertedWithCustomError(
                    clWstETH, "SetPendingAdminOwnerCheck"
                );
            });

            it("Should be able to set if caller is admin", async () => {
                const oldPendingAdmin = await clWstETH.pendingAdmin();

                const setPendingAdminTx = clWstETH
                    .connect(deployer)
                    .setPendingAdmin(
                        account1.address
                    );

                await expect(setPendingAdminTx).to.emit(
                    clWstETH, "NewPendingAdmin"
                ).withArgs(oldPendingAdmin, account1.address);
            });
        });

        context("Set Comptroller", () => {
            it("Should revert if caller is not admin", async () => {
                const setComptrollerTx = clWstETH
                    .connect(account1)
                    .setComptroller(
                        await comptroller.getAddress()
                    );

                await expect(setComptrollerTx).to.be.revertedWithCustomError(
                    clWstETH, "SetComptrollerOwnerCheck"
                );
            });

            it("Should be able to set if caller is admin", async () => {
                const oldComptroller = await clWstETH.comptroller();
                const NewComptroller = oldComptroller;

                const setComptrollerTx = clWstETH
                    .connect(deployer)
                    .setComptroller(
                        await comptroller.getAddress()
                    );

                await expect(setComptrollerTx).to.emit(
                    clWstETH, "NewComptroller"
                ).withArgs(oldComptroller, NewComptroller);
            });
        });

        context("Set Reserve Factor", () => {
            it("Should revert if caller is not admin", async () => {
                const newReserveFactorMantissa = ethers.WeiPerEther;
                const setReserveFactorTx = clWstETH
                    .connect(account1)
                    .setReserveFactor(
                        newReserveFactorMantissa
                    );

                await expect(setReserveFactorTx).to.be.revertedWithCustomError(
                    clWstETH, "SetReserveFactorAdminCheck"
                );
            });

            it("Should be able to set if caller is admin", async () => {
                const oldReserveFactorMantissa = await clWstETH.reserveFactorMantissa();
                const newReserveFactorMantissa = ethers.WeiPerEther;

                const setReserveFactorTx = clWstETH
                    .connect(deployer)
                    .setReserveFactor(
                        newReserveFactorMantissa
                    );

                await expect(setReserveFactorTx).to.emit(
                    clWstETH, "NewReserveFactor"
                ).withArgs(oldReserveFactorMantissa, newReserveFactorMantissa);
            });
        });

        context("Set InterestRateModel", () => {
            it("Should revert if caller is not admin", async () => {
                const setIrmTx = clWstETH
                    .connect(account1)
                    .setInterestRateModel(
                        await jumpRateModel.getAddress()
                    );

                await expect(setIrmTx).to.be.revertedWithCustomError(
                    clWstETH, "SetInterestRateModelOwnerCheck"
                );
            });

            it("Should be able to set if caller is admin", async () => {
                const oldInterestRateModel = await clWstETH.interestRateModel();
                const newInterestRateModel = oldInterestRateModel;

                const setIrmTx = clWstETH
                    .connect(deployer)
                    .setInterestRateModel(
                        await jumpRateModel.getAddress()
                    );

                await expect(setIrmTx).to.emit(
                    clWstETH, "NewMarketInterestRateModel"
                ).withArgs(oldInterestRateModel, newInterestRateModel);
            });
        });

        context("Accept New Admin", () => {
            beforeEach(async () => {
                // first set PendingAdmin
                await clWstETH.connect(deployer).setPendingAdmin(
                    account1.address
                );
            });

            it("Should revert if caller is not pendingAdmin", async () => {
                const acceptAdminTx = clWstETH
                    .connect(deployer)
                    .acceptAdmin();

                await expect(acceptAdminTx).to.be.revertedWithCustomError(
                    clWstETH, "AcceptAdminPendingAdminCheck"
                );
            });

            it("Should be able to accept if caller is pendingAdmin", async () => {
                const oldAdmin = await clWstETH.admin();
                // First set PendingAdmin
                const acceptAdminTx = clWstETH
                    .connect(account1)
                    .acceptAdmin();

                await expect(acceptAdminTx).to.emit(
                    clWstETH, "NewAdmin"
                ).withArgs(oldAdmin, account1.address);
            });
        });

        context("Add Reserves", () => {
            const amountToAdd = ethers.WeiPerEther;
            beforeEach(async () => {
                // Approve
                await wstETH.approve(clWstETH, amountToAdd);
            });

            it("Should be able to add reserves", async () => {
                const totalReserves = await clWstETH.totalReserves();
                const totalReservesNew = totalReserves + amountToAdd;

                const addReservesTx = clWstETH
                    .connect(deployer)
                    .addReserves(
                        amountToAdd
                    );

                await expect(addReservesTx).to.emit(
                    clWstETH, "ReservesAdded"
                ).withArgs(deployer.address, amountToAdd, totalReservesNew);
            });
        });

        context("Reduce Reserves", () => {
            const amount = ethers.WeiPerEther;
            beforeEach(async () => {
                await wstETH.approve(clWstETH, amount);
                await clWstETH.connect(deployer).addReserves(
                    amount
                );
            });

            it("Should revert if caller is not admin", async () => {
                const reduceReservesTx = clWstETH
                    .connect(account1)
                    .reduceReserves(
                        amount
                    );

                await expect(reduceReservesTx).to.revertedWithCustomError(
                    clWstETH, "ReduceReservesAdminCheck"
                );
            });

            it("Should be able to reduce reserves", async () => {
                const totalReserves = await clWstETH.totalReserves();
                const totalReservesNew = totalReserves - amount;

                const reduceReservesTx = clWstETH
                    .connect(deployer)
                    .reduceReserves(
                        amount
                    );

                await expect(reduceReservesTx).to.emit(
                    clWstETH, "ReservesReduced"
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
                    await clWstETH.getAddress(),
                    amountToSweep
                );
            });

            it("Should revert if caller is not admin", async () => {
                const sweepTokenTx = clWstETH
                    .connect(account1)
                    .sweepToken(
                        await erc20Mock.getAddress()
                    );

                await expect(sweepTokenTx).to.revertedWithCustomError(
                    clWstETH, "NotAdmin"
                );
            });

            it("Should revert if sweep token is underlying", async () => {
                const sweepTokenTx = clWstETH
                    .connect(deployer)
                    .sweepToken(
                        await wstETH.getAddress()
                    );

                await expect(sweepTokenTx).to.revertedWithCustomError(
                    clWstETH, "CanNotSweepUnderlyingToken"
                );
            });

            it("Should be able to sweep accidental ERC20 tokens", async () => {
                await clWstETH.connect(deployer).sweepToken(
                    await erc20Mock.getAddress()
                );

                expect(
                    await erc20Mock.balanceOf(await clWstETH.getAddress())
                ).to.equal(0n);

                expect(
                    await erc20Mock.balanceOf(deployer.address)
                ).to.equal(amountToSweep);
            });
        });
    });

    context("User functions", () => {
        const amount = parseUnits("100", 18);
        beforeEach(async () => {
            // mint `amount` of underlying tokens
            await wstETH.mint(account1.address, amount);
            await wstETH.connect(account1).approve(
                clWstETHAddr, amount
            );
        });

        context("Mint cTokens", () => {
            it("Should supply underlying assets and receive clTokens in exchange", async () => {
                const mintAmount = amount; // initial exchange rate 1:1
                const mintTx = clWstETH.connect(account1).mint(amount);
                
                await expect(mintTx).to.emit(
                    clWstETH, "Mint"
                ).withArgs(account1.address, amount, mintAmount);

                expect(await clWstETH.getCash()).to.equal(amount);
                // total supply of clTokens
                expect(await clWstETH.totalSupply()).to.equal(mintAmount);
            });
        });

        context("Redeem cTokens", () => {
            beforeEach(async () => {
                // supply assets to the market
                await clWstETH.connect(account1).mint(amount);
            });

            it("Should revert if the amount to redeem is greater than balance", async () => {
                const redeemTx = clWstETH.connect(account1).redeem(amount + 1n);

                await expect(redeemTx).to.revertedWithCustomError(
                    clWstETH, "RedeemTransferOutNotPossible"
                );
            });

            it("Should redeem clTokens in exchange for underlying asset", async () => {
                const redeemAmount = amount; // initial exchange rate 1:1
                const totalSupply = await clWstETH.totalSupply();
                const redeemTx = clWstETH.connect(account1).redeem(amount);
                
                await expect(redeemTx).to.emit(
                    clWstETH, "Redeem"
                ).withArgs(account1.address, redeemAmount, amount);

                expect(await clWstETH.getCash()).to.equal(amount - redeemAmount);
                // total supply of clTokens
                expect(await clWstETH.totalSupply()).to.equal(totalSupply - amount);
            });
        });

        context("Redeem underlying assets", () => {
            beforeEach(async () => {
                // supply assets to the market
                await clWstETH.connect(account1).mint(amount);
            });

            it("Should revert if the amount to redeem is greater than balance", async () => {
                const redeemAmount = amount + 1n;
                const redeemTx = clWstETH.connect(account1).redeemUnderlying(redeemAmount);

                await expect(redeemTx).to.revertedWithCustomError(
                    clWstETH, "RedeemTransferOutNotPossible"
                );
            });

            it("Should redeem clTokens in exchange for a specified amount of underlying asset", async () => {
                const redeemTokens = amount; // initial exchange rate 1:1
                const totalSupply = await clWstETH.totalSupply();
                const redeemTx = clWstETH.connect(account1).redeemUnderlying(amount);
                
                await expect(redeemTx).to.emit(
                    clWstETH, "Redeem"
                ).withArgs(account1.address, amount, redeemTokens);

                expect(await clWstETH.getCash()).to.equal(0n);
                // total supply of clTokens
                expect(await clWstETH.totalSupply()).to.equal(totalSupply - redeemTokens);
            });
        });

        context("Borrow underlying assets", () => {
            const amountToBorrow = parseUnits("80", 18);
            beforeEach(async () => {
                // Make some liquidity for a borrow market
                await rETH.connect(deployer).approve(clRETHAddr, amount);
                await clRETH.connect(deployer).mint(amount);

                // supply assets to the market
                await clWstETH.connect(account1).mint(amount);
            });

            it("Should revert if users explicitly do not list which assets they would like included", async () => {
                const borrowTx = clRETH.connect(account1).borrow(amountToBorrow);

                await expect(borrowTx).to.revertedWithCustomError(
                    comptroller, "InsufficientLiquidity"
                );
            });

            it("Should revert if users try to borrow more amount of worth than collateral value", async () => {
                await comptroller.connect(account1).enterMarkets(
                    [clWstETHAddr, clRETHAddr]
                );

                const borrowTx = clRETH.connect(account1).borrow(amount);

                await expect(borrowTx).to.revertedWithCustomError(
                    comptroller, "InsufficientLiquidity"
                );
            });

            it("Should borrow underlying assets from the protocol", async () => {
                await comptroller.connect(account1).enterMarkets(
                    [clWstETHAddr, clRETHAddr]
                );
                await clRETH.connect(account1).borrow(amountToBorrow);

                expect(await clRETH.totalBorrows()).to.equal(amountToBorrow);
            });
        });

        context("Borrow on behalf of another user", () => {
            const amountToBorrow = parseUnits("80", 18);

            beforeEach(async () => {
                // Make some liquidity for a borrow market
                await rETH.connect(deployer).approve(clRETHAddr, amount);
                await clRETH.connect(deployer).mint(amount);

                // supply assets to the market
                await clWstETH.connect(account1).mint(amount);

                // set leverage address in Comptroller
                await comptroller.connect(deployer).setLeverageAddress(
                    await leverage.getAddress()
                );
            });
            
            it("Should revert if caller is not leverage contract", async () => {
                const borrowBehalfTx = clRETH
                    .connect(account1)
                    .borrowBehalf(
                        deployer.address, amountToBorrow
                    );

                await expect(borrowBehalfTx).to.revertedWithCustomError(
                    comptroller, "SenderMustBeLeverage"
                );
            });
        });

        context("Repay underlying assets", () => {
            const amountToBorrow = parseUnits("80", 18);

            beforeEach(async () => {
                await comptroller.connect(account1).enterMarkets(
                    [clWstETHAddr, clRETHAddr]
                );

                // Make some liquidity for a borrow market
                await rETH.connect(deployer).approve(clRETHAddr, amount);
                await clRETH.connect(deployer).mint(amount);

                // supply assets to the market
                await clWstETH.connect(account1).mint(amount);
                await clRETH.connect(account1).borrow(amountToBorrow);
            });

            it("Should repay full outstanding amount", async () => {
                await rETH.connect(account1).approve(clRETHAddr, amountToBorrow);
                const repayTx = clRETH.connect(account1).repayBorrow(amountToBorrow);

                await expect(repayTx).to.emit(
                    clRETH, "RepayBorrow"
                );
            });

            it("Should repay partial outstanding amount", async () => {
                await rETH.connect(account1).approve(clRETHAddr, amountToBorrow / 2n);
                const repayTx = clRETH.connect(account1).repayBorrow(amountToBorrow / 2n);

                await expect(repayTx).to.emit(
                    clRETH, "RepayBorrow"
                );
            });

            it("Should repay on behalf of borrower", async () => {
                await rETH.connect(deployer).approve(clRETHAddr, amountToBorrow / 2n);
                const repayBehalfTx = clRETH.connect(deployer).repayBorrowBehalf(
                    account1.address,
                    amountToBorrow / 2n
                );

                await expect(repayBehalfTx).to.emit(
                    clRETH, "RepayBorrow"
                );
            });
        });

        context("Liquidate borrow", () => {
            const amountToBorrow = parseUnits("80", 18);
            const amountToRepay = parseUnits("40", 18);

            beforeEach(async () => {
                // mint amount for repayment, use deployer as liquidator
                await wstETH.mint(deployer.address, amount);

                await comptroller.connect(account1).enterMarkets(
                    [clWstETHAddr, clRETHAddr]
                );
                
                // Make some liquidity for a borrow market
                await rETH.connect(deployer).approve(clRETHAddr, amount);
                await clRETH.connect(deployer).mint(amount);

                // supply collateral to the WstETH market
                await clWstETH.connect(account1).mint(amount);
                // borrow from rETH market
                await clRETH.connect(account1).borrow(amountToBorrow);

                // should set close factor to set max liquidatable borrow
                // that can be repaid in a single txn
                await comptroller.connect(deployer).setCloseFactor(
                    closeFactor
                );
            });

            it("Should revert if borrower does not have shortfall", async () => {
                const liquidateBorrowTx = clRETH
                    .connect(deployer)
                    .liquidateBorrow(
                        account1.address,
                        amountToBorrow,
                        clWstETHAddr
                    );

                await expect(liquidateBorrowTx).to.revertedWithCustomError(
                    comptroller, "InsufficientShortfall"
                );
            });

            it("Should revert if repay amount is greater than max close", async () => {
                // set direct price to make shortfall
                await priceOracle.connect(deployer).setDirectPrice(
                    await wstETH.getAddress(), parseEther("1000")
                );

                const liquidateBorrowTx = clRETH
                    .connect(deployer)
                    .liquidateBorrow(
                        account1.address,
                        amountToBorrow,
                        clWstETHAddr
                    );

                await expect(liquidateBorrowTx).to.revertedWithCustomError(
                    comptroller, "TooMuchRepay"
                );
            });

            it("Should revert if seize amount is greater than borrower's collateral", async () => {
                // low price
                await priceOracle.connect(deployer).setDirectPrice(
                    await wstETH.getAddress(), parseEther("1000")
                );

                // set liquidation incentive as 0.9 ether
                await comptroller.setLiquidationIncentive(parseEther("0.9"));

                await rETH.connect(deployer).approve(clRETHAddr, amountToRepay);

                const liquidateBorrowTx = clRETH.connect(deployer).liquidateBorrow(
                    account1.address, amountToRepay, clWstETHAddr
                );

                await expect(liquidateBorrowTx).to.revertedWithCustomError(
                    clRETH, "LiquidateSeizeTooMuch"
                );
            });

            it("Should liquidate borrow", async () => {
                await priceOracle.connect(deployer).setDirectPrice(
                    await wstETH.getAddress(), parseEther("2000")
                );

                // set liquidation incentive as 1 ether
                await comptroller.setLiquidationIncentive(parseEther("0.9"));

                await rETH.connect(deployer).approve(clRETHAddr, amountToRepay);
                const liquidateBorrowTx = clRETH.connect(deployer).liquidateBorrow(
                    account1.address, amountToRepay, clWstETHAddr
                );

                await expect(liquidateBorrowTx).to.emit(
                    clRETH, "LiquidateBorrow"
                );
            });
        });
    });
});
