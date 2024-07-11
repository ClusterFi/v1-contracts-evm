import { ethers } from "hardhat";

async function main() {
    const blocksPerYear = 2102400;
    const baseRatePerYear = ethers.parseEther("0.1");
    const multiplierPerYear = ethers.parseEther("0.45");
    const jumpMultiplierPerYear = ethers.parseEther("5");
    const kink = ethers.parseEther("0.9");

    const [deployer] = await ethers.getSigners();

    const JumpRateModel = await ethers.getContractFactory("JumpRateModel");
    const jumpRateModel = await JumpRateModel.deploy(
        blocksPerYear,
        baseRatePerYear,
        multiplierPerYear,
        jumpMultiplierPerYear,
        kink,
        deployer.address
    );

    await jumpRateModel.waitForDeployment();

    console.log(
        `JumpRateModel deployed to ${jumpRateModel.target}`
    );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
