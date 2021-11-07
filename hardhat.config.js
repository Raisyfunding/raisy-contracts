require("dotenv").config();

require("@openzeppelin/hardhat-upgrades");
require("@nomiclabs/hardhat-etherscan");
require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-solhint");
require("@nomiclabs/hardhat-truffle5");
require("@nomiclabs/hardhat-web3");
require("hardhat-gas-reporter");
require("solidity-coverage");
require("hardhat-contract-sizer");

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
	const accounts = await hre.ethers.getSigners();

	for (const account of accounts) {
		console.log(account.address);
	}
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
	solidity: {
		version: "0.8.4",
		settings: {
			optimizer: {
				enabled: true,
				runs: 1,
			},
		},
	},
	networks: {
		coverage: {
			url: "http://localhost:8555",
		},

		localhost: {
			url: `http://127.0.0.1:8545`,
		},
		// ropsten: {
		//   url: process.env.ROPSTEN_URL || "",
		//   accounts:
		//     process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
		// },
	},
	gasReporter: {
		enabled: process.env.REPORT_GAS !== undefined,
		currency: "USD",
	},
	etherscan: {
		apiKey: process.env.ETHERSCAN_API_KEY,
	},
};
