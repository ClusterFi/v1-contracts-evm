import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@openzeppelin/hardhat-upgrades";
import "dotenv/config";
import './tasks';

const config: HardhatUserConfig = {
  solidity: {
    compilers: [{
      version: '0.8.20',
      settings: {
        evmVersion: 'paris',
        optimizer: {
          enabled: true,
          runs: 200
        }
      }
    }]
  },
  networks: {
    hardhat: {
      forking: {
        enabled: true,
        url: `https://eth-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`,
        blockNumber: 19879247
      }
    },
    sepolia: {
      url: `https://eth-sepolia.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`,
      chainId: 11_155_111,
      accounts: [process.env.PRIVATE_KEY as string]
    },
    mainnet: {
      url: `https://eth-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`,
      chainId: 1,
      accounts: [process.env.PRIVATE_KEY as string]
    }
  },
  gasReporter: {
    enabled: true,
    currency: 'USD',
  },
  sourcify: {
    enabled: false
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  }
};

export default config;
