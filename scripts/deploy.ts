import { ethers, upgrades } from "hardhat";

async function main() {
  const ClusterToken = await ethers.getContractFactory("Cluster");
  const clusterToken = await upgrades.deployProxy(ClusterToken);

  await clusterToken.waitForDeployment();

  console.log(
    `CLR deployed to ${clusterToken.target}`
  );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
