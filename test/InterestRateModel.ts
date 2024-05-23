import { expect } from "chai";
import { ethers } from "hardhat";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { JumpRateModel } from "../typechain-types";

const blocksPerYear = 2102400n;

function utilizationRate(cash: bigint, borrows: bigint, reserves: bigint): bigint {
    return borrows ? borrows * ethers.WeiPerEther / (cash + borrows - reserves) : 0n;
}

function getBorrowRate(
    utilRate: bigint,
    base: bigint,
    slope: bigint,
    jump: bigint,
    kink: bigint
): bigint {
    if (utilRate <= kink) {
      return utilRate * slope / ethers.WeiPerEther + base;
    } else {
      const excessUtil = utilRate - kink;
      return ((excessUtil * jump) + (kink * slope) + base) / ethers.WeiPerEther;
    }
}

function getSupplyRate(
    utilRate: bigint,
    reserveFactor: bigint,
    base: bigint,
    slope: bigint,
    jump: bigint,
    kink: bigint
): bigint {
    const oneMinusReserveFactor = ethers.WeiPerEther - reserveFactor;
    const borrowRate = getBorrowRate(utilRate, base, slope, jump, kink);
    const rateToPool = borrowRate * oneMinusReserveFactor / ethers.WeiPerEther;
    return utilRate * rateToPool / ethers.WeiPerEther;
}

describe("InterestRateModel", function () {
    let deployer: HardhatEthersSigner, user: HardhatEthersSigner;
    let jumpRateModel: JumpRateModel;

    const baseRatePerYear = ethers.parseEther("0.1");
    const multiplierPerYear = ethers.parseEther("0.45");
    const jumpMultiplierPerYear = ethers.parseEther("5");
    const kink = ethers.parseEther("0.9");

    const rateInputs = [
        [500, 100],
        [3e18, 5e18],
        [5e18, 3e18],
        [500, 3e18],
        [0, 500],
        [500, 0],
        [0, 0],
        [3e18, 500]
    ].map(vs => vs.map(BigInt));
    
    beforeEach(async () => {
        // Contracts are deployed using the first signer/account by default
        [deployer, user] = await ethers.getSigners();
        // Comptroller contract instance
        jumpRateModel = await ethers.deployContract("JumpRateModel", [
            blocksPerYear,
            baseRatePerYear,
            multiplierPerYear,
            jumpMultiplierPerYear,
            kink,
            deployer.address
        ]);
    });

    context("Deployment", () => {
        it("isInterestRateModel should be true", async () => {
            expect(await jumpRateModel.isInterestRateModel()).to.equal(true);
        });

        it("Should set deployer as owner", async () => {
            expect(await jumpRateModel.owner()).to.equal(deployer.address);
        });

        it("Should return correct blocks per year", async () => {
            expect(await jumpRateModel.blocksPerYear()).to.equal(blocksPerYear);
        });

        it("Should return correct kink", async () => {
            expect(await jumpRateModel.kink()).to.equal(kink);
        });
    });

    context("View Functions", () => {
        it("get utilization rate", async () => {
            await Promise.all(rateInputs.map(async ([cash, borrows, reserves = 0n]) => {
                const expected = utilizationRate(cash, borrows, reserves);
                expect(
                    await jumpRateModel.utilizationRate(cash, borrows, reserves)
                ).to.be.closeTo(expected, 1e7);
                }));
        });

        it("get borrow rate", async () => {
            const multiplierPerBlock = await jumpRateModel.multiplierPerBlock();
            const baseRatePerBlock = await jumpRateModel.baseRatePerBlock();
            const jumpMultiplierPerBlock = await jumpRateModel.jumpMultiplierPerBlock();
            const kink = await jumpRateModel.kink();

            await Promise.all(rateInputs.map(async ([cash, borrows, reserves = 0n]) => {
                const expectedUtil = utilizationRate(cash, borrows, reserves);
                const expectedBorrowRate = getBorrowRate(
                    expectedUtil, baseRatePerBlock, multiplierPerBlock, jumpMultiplierPerBlock, kink
                );
                expect(
                    await jumpRateModel.getBorrowRate(cash, borrows, reserves)
                ).to.be.closeTo(expectedBorrowRate, 1e12);
                }));
        });

        it("get supply rate", async () => {
            const multiplierPerBlock = await jumpRateModel.multiplierPerBlock();
            const baseRatePerBlock = await jumpRateModel.baseRatePerBlock();
            const jumpMultiplierPerBlock = await jumpRateModel.jumpMultiplierPerBlock();
            const kink = await jumpRateModel.kink();

            const reserveFactor = ethers.WeiPerEther / 2n;

            await Promise.all(rateInputs.map(async ([cash, borrows, reserves = 0n]) => {
                const expectedUtil = utilizationRate(cash, borrows, reserves);
                const expectedSupplyRate = getSupplyRate(
                    expectedUtil,
                    reserveFactor,
                    baseRatePerBlock,
                    multiplierPerBlock,
                    jumpMultiplierPerBlock,
                    kink
                );

                expect(
                    await jumpRateModel.getSupplyRate(cash, borrows, reserves, reserveFactor)
                ).to.be.closeTo(expectedSupplyRate, 1e12);
            }));
        });
    });

    context("Owner Functions", () => {
        it("Should be able to update the blocks per year", async () => {
            const newBlocksPerYear = blocksPerYear + 10n;
            await jumpRateModel.updateBlocksPerYear(newBlocksPerYear);
            expect(await jumpRateModel.blocksPerYear()).to.equal(newBlocksPerYear);
        });

        it("Should be able to update the interest rate parameters", async () => {
            const newBaseRatePerYear = ethers.parseEther("0.1");
            const newMultiplierPerYear = ethers.parseEther("0.2");
            const newJumpMultiplierPerYear = ethers.parseEther("10");
            const newKink = ethers.parseEther("1.1");

            const updateJumpRateModelTx = jumpRateModel
                .connect(deployer)
                .updateJumpRateModel(
                    newBaseRatePerYear,
                    newMultiplierPerYear,
                    newJumpMultiplierPerYear,
                    newKink
                );

            await expect(updateJumpRateModelTx).to.emit(
                jumpRateModel, "NewInterestParams"
            );
        });

        it("Should revert if the caller is not owner", async () => {
            const updateBlocksPerYearTx = jumpRateModel
                .connect(user)
                .updateBlocksPerYear(
                    blocksPerYear
                );

            await expect(updateBlocksPerYearTx).to.be.revertedWithCustomError(
                jumpRateModel, "OwnableUnauthorizedAccount"
            ).withArgs(user.address);
        });
    });
});
