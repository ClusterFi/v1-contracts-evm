import { ethers } from "hardhat";

async function main() {
    const underlying = "0xB82381A3fBD3FaFA77B3a7bE693342618240067b";
    const comptroller = "0x12129Aaf6a9B067C9AD7e34117C9b7723E04c541";
    const interestRateModel = "0x810F98442c3349553031d70F8E510841104bd857";
    const initialExchangeRate = ethers.parseEther("1");

    const [deployer] = await ethers.getSigners();

    const ClErc20 = await ethers.getContractFactory("ClErc20");
    const clWstETH = await ClErc20.deploy(
        underlying,
        comptroller,
        interestRateModel,
        initialExchangeRate,
        "Cluster WstETH",
        "clWstETH",
        8,
        deployer.address
    );

    await clWstETH.waitForDeployment();

    console.log(
        `Cluster WstETH deployed to ${clWstETH.target}`
    );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
