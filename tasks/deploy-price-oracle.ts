import { task } from 'hardhat/config';

task('deploy-price-oracle', 'Deploy PriceOracle')
    .setAction(async ({}, { ethers, run }) => {
        // Deploy proxy contract
        const PriceOracle = await ethers.getContractFactory("PriceOracle");
        const priceOracle = await PriceOracle.deploy();
        await priceOracle.waitForDeployment();

        console.log("PriceOracle deployed to:", priceOracle.target);

        // verify
        await run('verify:verify', {
            address: await priceOracle.getAddress()
        });

        console.log('>>>>> PriceOracle Contract verified.');

        return priceOracle.target;
    });
