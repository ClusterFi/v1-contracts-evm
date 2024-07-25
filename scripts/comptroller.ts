import { ethers, upgrades } from "hardhat";

async function main() {
  const Comptroller = await ethers.getContractFactory("Comptroller");
  const comptroller = await upgrades.deployProxy(Comptroller);

  await comptroller.waitForDeployment();

  console.log(
    `Comptroller deployed to ${comptroller.target}`
  );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
