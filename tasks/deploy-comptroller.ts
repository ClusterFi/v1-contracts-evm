import { task } from 'hardhat/config';

task('deploy-comptroller', 'Deploy Comptroller')
    .setAction(async ({}, { ethers, upgrades, run }) => {
        // Deploy proxy contract
        const Comptroller = await ethers.getContractFactory("Comptroller");
        const proxy = await upgrades.deployProxy(Comptroller, []);
        await proxy.waitForDeployment();

        console.log("Proxy deployed to:", proxy.target);

        // verify
        await run('verify:verify', {
            address: await proxy.getAddress()
        });

        console.log('>>>>> Comptroller Contract verified.');

        return proxy.target;
    });
