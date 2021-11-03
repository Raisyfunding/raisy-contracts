const {
	BN,
	constants,
	expectEvent,
	expectRevert,
	balance,
} = require("@openzeppelin/test-helpers");
const { ZERO_ADDRESS } = constants;

const { expect } = require("chai");

const { ethers } = require("hardhat");

contract("RaisyCampaigns", function([owner, projectowner, feeRecipient]) {
	const ZERO = new BN("0");
	const AMOUNT = new BN("100000000000");
	const EX_MAX_DUR = new BN("1000");

	beforeEach(async function() {
		this.RaisyCampaigns = await ethers.getContractFactory("RaisyCampaigns");
		this.raisyCampaigns = await this.RaisyCampaigns.deploy();
		await this.raisyCampaigns.deployed();
	});

	describe("Add campaign", async function() {
		it("Reverts when max duration is exceeded", async function() {
			await expectRevert(
				this.raisyCampaigns["addCampaign(uint256,uint256)"]("100", "20000", {
					from: owner,
				}),
				"duration too long"
			);
		});
	});
});
