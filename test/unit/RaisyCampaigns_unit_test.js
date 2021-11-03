const {
	BN,
	constants,
	expectEvent,
	expectRevert,
	balance,
	ether,
} = require("@openzeppelin/test-helpers");
const { ZERO_ADDRESS } = constants;

const { expect } = require("chai");

const RaisyCampaigns = artifacts.require("RaisyCampaigns");
const RaisyToken = artifacts.require("RaisyToken");
const RaisyChef = artifacts.require("RaisyChef");
const RaisyAddressRegistry = artifacts.require("RaisyAddressRegistry");

contract("RaisyCampaigns", ([owner, projectowner, daotreasuryadd]) => {
	const AMOUNT_TO_RAISE = new BN(ether("10000"));
	const MAX_SUPPLY = new BN(ether("10000000"));
	const REW_PER_BLOCK = new BN("10");
	const LOCK = new BN("100");
	const START_BLOCK = new BN("1");
	const ONE_HUNDRED_THOUSAND = new BN(ether("100000"));
	const END_BLOCK = new BN("15000");

	beforeEach(async () => {
		// Deploy the contracts
		this.raisyCampaigns = await RaisyCampaigns.new({ from: owner });
		this.raisyCampaigns.initialize({ from: owner });

		this.raisyToken = await RaisyToken.new("RaisyToken", "RSY", MAX_SUPPLY, {
			from: owner,
		});
		this.raisyChef = await RaisyChef.new(
			this.raisyToken.address,
			owner,
			daotreasuryadd,
			REW_PER_BLOCK,
			LOCK,
			START_BLOCK,
			{
				from: owner,
			}
		);

		// Mint 1000 $RSY
		this.raisyToken.mint(owner, ONE_HUNDRED_THOUSAND, { from: owner });

		// Transfer ownerships
		this.raisyToken.transferOwnership(this.raisyChef.address, { from: owner });
		this.raisyChef.transferOwnership(this.raisyCampaigns.address, {
			from: owner,
		});

		// Setup the Address Registry
		this.raisyAddressRegistry = await RaisyAddressRegistry.new({ from: owner });
		this.raisyAddressRegistry.updateRaisyChef(this.raisyChef.address, {
			from: owner,
		});
		this.raisyAddressRegistry.updateRaisyToken(this.raisyToken.address, {
			from: owner,
		});

		// Update the Address Registry address
		this.raisyCampaigns.updateAddressRegistry(
			this.raisyAddressRegistry.address,
			{ from: owner }
		);
	});

	describe("addCampaign()", async () => {
		it("reverts when maxDuration is exceeded", async () => {
			await expectRevert(
				this.raisyCampaigns.methods["addCampaign(uint256,uint256)"](
					"300",
					"20000",
					{
						from: owner,
					}
				),
				"duration too long"
			);
		});

		it("reverts when duration is lower than minDuration", async () => {
			await expectRevert(
				this.raisyCampaigns.methods["addCampaign(uint256,uint256)"](
					"10",
					AMOUNT_TO_RAISE,
					{
						from: owner,
					}
				),
				"duration too short"
			);
		});

		it("reverts when amount is null", async () => {
			await expectRevert(
				this.raisyCampaigns.methods["addCampaign(uint256,uint256)"](
					"100",
					"0",
					{
						from: owner,
					}
				),
				"amount to raise null"
			);
		});

		it("successfuly adds a campaign without a release schedule", async () => {
			await this.raisyCampaigns.methods["addCampaign(uint256,uint256)"](
				"100",
				AMOUNT_TO_RAISE,
				{
					from: projectowner,
				}
			);
		});
	});
});
