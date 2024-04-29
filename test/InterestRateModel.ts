import { expect } from "chai";
import { ethers } from "hardhat";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { JumpRateModel, WhitePaperInterestRateModel } from "../typechain-types";

const blocksPerYear = 2102400n;

function utilizationRate(cash: bigint, borrows: bigint, reserves: bigint): bigint {
    return borrows ? borrows * ethers.WeiPerEther / (cash + borrows - reserves) : 0n;
}

function borrowRate(
    utilRate: bigint,
    base: bigint,
    slope: bigint,
    jump: bigint,
    kink: bigint
): bigint {
    if (utilRate <= kink) {
      return (utilRate * slope / ethers.WeiPerEther + base) / blocksPerYear;
    } else {
      const excessUtil = utilRate - kink;
      return (((excessUtil * jump) + (kink * slope) + base) / blocksPerYear) / ethers.WeiPerEther;
    }
}

describe("InterestRateModel", function () {
    let deployer: HardhatEthersSigner, user: HardhatEthersSigner;
    let jumpRateModel: JumpRateModel, whitePaperInterestRateModel: WhitePaperInterestRateModel;

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
            ethers.parseEther("0.1"), ethers.parseEther("0.45"), jumpMultiplierPerYear, kink, deployer.address
        ]);

        whitePaperInterestRateModel = await ethers.deployContract("WhitePaperInterestRateModel", [
            ethers.parseEther("0.025"), ethers.parseEther("0.2")
        ]);
    });

    context("WhitePaperInterestRateModel", () => {
        it("isInterestRateModel should be true", async () => {
            expect(await whitePaperInterestRateModel.isInterestRateModel()).to.equal(true);
        });

        it("get utilization rate", async () => {
            await Promise.all(rateInputs.map(async ([cash, borrows, reserves = 0n]) => {
                const expected = utilizationRate(cash, borrows, reserves);
                expect(
                    await whitePaperInterestRateModel.utilizationRate(cash, borrows, reserves)
                ).to.be.closeTo(expected, 1e7);
              }));
        });
    });

    context("JumpRateModel", () => {
        it("isInterestRateModel should be true", async () => {
            expect(await jumpRateModel.isInterestRateModel()).to.equal(true);
        });

        it("get utilization rate", async () => {
            await Promise.all(rateInputs.map(async ([cash, borrows, reserves = 0n]) => {
                const expected = utilizationRate(cash, borrows, reserves);
                expect(
                    await jumpRateModel.utilizationRate(cash, borrows, reserves)
                ).to.be.closeTo(expected, 1e7);
              }));
        });

        it("get borrow rate", async () => {
            await Promise.all(rateInputs.map(async ([cash, borrows, reserves = 0n]) => {
                const expectedUtil = utilizationRate(cash, borrows, reserves);
                const expectedBorrowRate = borrowRate(
                    expectedUtil, ethers.parseEther("0.1"), ethers.parseEther("0.45"), jumpMultiplierPerYear, kink
                );
                expect(
                    await jumpRateModel.getBorrowRate(cash, borrows, reserves)
                ).to.be.closeTo(expectedBorrowRate, 1e12);
              }));
        })
    });
});
