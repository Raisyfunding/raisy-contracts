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

const RaisyCampaigns = artifacts.require("MockRaisyCampaigns");
const RaisyToken = artifacts.require("RaisyToken");
const RaisyNFT = artifacts.require("RaisyNFT");
const RaisyChef = artifacts.require("MockRaisyChef");
const RaisyAddressRegistry = artifacts.require("RaisyAddressRegistry");
const RaisyTokenRegistry = artifacts.require("RaisyTokenRegistry");
const RaisyPriceFeed = artifacts.require("RaisyPriceFeed");
const MockERC20 = artifacts.require("MockERC20");

contract("RaisyCampaigns", ([owner, projectowner, daotreasuryadd, user]) => {
	const AMOUNT_TO_RAISE = new BN(ether("10000"));
	const MAX_SUPPLY = new BN(ether("10000000"));
	const REW_PER_BLOCK = new BN("10");
	const LOCK = new BN("100");
	const START_BLOCK = new BN("1");
	const ONE_HUNDRED_THOUSAND = new BN(ether("100000"));
	const FIVE_HUNDRED = new BN(ether("500"));
	const END_BLOCK = new BN("15000");

	beforeEach(async () => {
		// Deploy the contracts
		this.raisyCampaigns = await RaisyCampaigns.new({ from: owner });
		this.raisyCampaigns.initialize({ from: owner });

		this.raisyNFT = await RaisyNFT.new("RaisyNFT", "POD", { from: owner });

		this.raisyToken = await RaisyToken.new("RaisyToken", "RSY", MAX_SUPPLY, {
			from: owner,
		});
		this.raisyChef = await RaisyChef.new(
			this.raisyToken.address,
			daotreasuryadd,
			REW_PER_BLOCK,
			LOCK,
			START_BLOCK,
			{
				from: owner,
			}
		);
		this.raisyTokenRegistry = await RaisyTokenRegistry.new({ from: owner });
		this.mockERC20 = await MockERC20.new("wAVAX", "wAVAX", ether("1000000"));
		this.raisyAddressRegistry = await RaisyAddressRegistry.new({ from: owner });
		this.raisyPriceFeed = await RaisyPriceFeed.new(
			this.raisyAddressRegistry.address,
			this.mockERC20.address,
			{ from: owner }
		);

		// Mint 100000 $RSY
		await this.raisyToken.mint(owner, ONE_HUNDRED_THOUSAND, { from: owner });

		// Transfer ownerships
		await this.raisyToken.transferOwnership(this.raisyChef.address, {
			from: owner,
		});
		await this.raisyChef.transferOwnership(this.raisyCampaigns.address, {
			from: owner,
		});
		await this.raisyNFT.transferOwnership(this.raisyCampaigns.address, {
			from: owner,
		});

		// Setup the Address Registry
		await this.raisyAddressRegistry.updateRaisyChef(this.raisyChef.address, {
			from: owner,
		});
		await this.raisyAddressRegistry.updateRaisyToken(this.raisyToken.address, {
			from: owner,
		});
		await this.raisyAddressRegistry.updateRaisyNFT(this.raisyNFT.address, {
			from: owner,
		});
		await this.raisyAddressRegistry.updateTokenRegistry(
			this.raisyTokenRegistry.address,
			{
				from: owner,
			}
		);
		await this.raisyAddressRegistry.updatePriceFeed(
			this.raisyPriceFeed.address,
			{
				from: owner,
			}
		);

		// Update the Address Registry address
		await this.raisyCampaigns.updateAddressRegistry(
			this.raisyAddressRegistry.address,
			{ from: owner }
		);

		// Enable payment with $RSY
		await this.raisyTokenRegistry.add(this.raisyToken.address, { from: owner });
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
			await this.raisyCampaigns.setBlockOverride(50);

			const receipt = await this.raisyCampaigns.methods[
				"addCampaign(uint256,uint256)"
			]("100", AMOUNT_TO_RAISE, {
				from: projectowner,
			});

			console.log(`
            *Event CampaignCreated should be emitted with correct values: 
            id = 0, 
            creator = ${projectowner}, 
            duration = 100,
            startBlock = ${receipt.logs[0].blockNumber.toString()},
            amountToRaise = ${AMOUNT_TO_RAISE},
            hasReleaseSchedule = true`);
			expectEvent(receipt, "CampaignCreated", {
				id: "0",
				creator: projectowner,
				duration: "100",
				startBlock: "50",
				amountToRaise: AMOUNT_TO_RAISE,
				hasReleaseSchedule: false,
			});
		});

		it("successfuly adds a campaign with a release schedule", async () => {
			await this.raisyCampaigns.setBlockOverride(50);

			const receipt = await this.raisyCampaigns.methods[
				"addCampaign(uint256,uint256,uint256,uint256[])"
			]("100", AMOUNT_TO_RAISE, new BN("2"), [5000, 5000], {
				from: projectowner,
			});

			console.log(`
            *Event CampaignCreated should be emitted with correct values: 
            id = 0, 
            creator = ${projectowner}, 
            duration = 100,
            startBlock = ${receipt.logs[0].blockNumber.toString()},
            amountToRaise = ${AMOUNT_TO_RAISE},
            hasReleaseSchedule = true`);
			expectEvent(receipt, "CampaignCreated", {
				id: "0",
				creator: projectowner,
				duration: "100",
				startBlock: "50",
				amountToRaise: AMOUNT_TO_RAISE,
				hasReleaseSchedule: true,
			});

			console.log(`
            *Event ScheduleRegistered should be emitted with correct values: 
            id = 0, 
            nbMilestones = 2, 
            pctReleasePerMilestone = [5000, 5000],
            `);
			const e = expectEvent(receipt, "ScheduleRegistered", {
				campaignId: "0",
				nbMilestones: "2",
			});

			// Here we should be able to test equality between arrays of big numbers
			// https://github.com/OpenZeppelin/chai-bn/issues/5
			// expect(e.args.pctReleasePerMilestone).to.have.bignumber.members([
			// 	new BN("5000"),
			// 	new BN("5000"),
			// ]);

			expect(await this.raisyCampaigns.scheduleExistence.call(0)).to.be.equal(
				true
			);
		});

		it("reverts if nbMilestones is null", async () => {
			await expectRevert(
				this.raisyCampaigns.methods[
					"addCampaign(uint256,uint256,uint256,uint256[])"
				]("100", AMOUNT_TO_RAISE, new BN("0"), [5000, 5000], {
					from: projectowner,
				}),
				"Needs at least 1 milestone."
			);
		});

		it("reverts if nbMilestones is > 5", async () => {
			await expectRevert(
				this.raisyCampaigns.methods[
					"addCampaign(uint256,uint256,uint256,uint256[])"
				]("100", AMOUNT_TO_RAISE, new BN("6"), [5000, 5000], {
					from: projectowner,
				}),
				"Too many milestones."
			);
		});

		it("reverts when there isn't a percent per milestone", async () => {
			await expectRevert(
				this.raisyCampaigns.methods[
					"addCampaign(uint256,uint256,uint256,uint256[])"
				]("100", AMOUNT_TO_RAISE, new BN("3"), [5000, 5000], {
					from: projectowner,
				}),
				"Only one percent per milestone."
			);
		});

		it("reverts when the first release pct is too low", async () => {
			await expectRevert(
				this.raisyCampaigns.methods[
					"addCampaign(uint256,uint256,uint256,uint256[])"
				]("100", AMOUNT_TO_RAISE, new BN("2"), [1000, 9000], {
					from: projectowner,
				}),
				"Start release pct too low."
			);
		});

		it("reverts when the first release pct is too high", async () => {
			await expectRevert(
				this.raisyCampaigns.methods[
					"addCampaign(uint256,uint256,uint256,uint256[])"
				]("100", AMOUNT_TO_RAISE, new BN("2"), [11000, 9000], {
					from: projectowner,
				}),
				"Start release pct too high."
			);
		});

		it("reverts when the percentages don't add up", async () => {
			await expectRevert(
				this.raisyCampaigns.methods[
					"addCampaign(uint256,uint256,uint256,uint256[])"
				]("100", AMOUNT_TO_RAISE, new BN("3"), [2500, 4000, 3000], {
					from: projectowner,
				}),
				"Pcts should add up to 100%"
			);
		});
	});

	describe("donate()", async () => {
		const ADD_BLOCK = 50;
		const BLOCK_DURATION = 100;

		beforeEach(async () => {
			await this.raisyCampaigns.setBlockOverride(ADD_BLOCK);

			await this.raisyCampaigns.methods[
				"addCampaign(uint256,uint256,uint256,uint256[])"
			](BLOCK_DURATION, AMOUNT_TO_RAISE, new BN("2"), [5000, 5000], {
				from: projectowner,
			});
		});

		it("reverts if campaign doesn't exist", async () => {
			await expectRevert(
				this.raisyCampaigns.donate(1, FIVE_HUNDRED, this.raisyToken.address, {
					from: owner,
				}),
				"Campaign does not exist."
			);
		});

		it("reverts if amount is null", async () => {
			await expectRevert(
				this.raisyCampaigns.donate(0, 0, this.raisyToken.address),
				"Donation must be positive."
			);
		});

		it("reverts if the campaign is over", async () => {
			await this.raisyCampaigns.setBlockOverride(
				ADD_BLOCK + BLOCK_DURATION + 1
			);

			await expectRevert(
				this.raisyCampaigns.donate(0, FIVE_HUNDRED, this.raisyToken.address, {
					from: owner,
				}),
				"Campaign is over."
			);
		});

		it("reverts if payToken is not valid", async () => {
			await expectRevert(
				this.raisyCampaigns.donate(0, FIVE_HUNDRED, this.mockERC20.address),
				"invalid pay token"
			);
		});

		it("successfuly donates to the campaign in $RSY", async () => {
			// Approves the contract to use $RSY
			await this.raisyToken.approve(this.raisyCampaigns.address, FIVE_HUNDRED, {
				from: owner,
			});

			const receipt = await this.raisyCampaigns.donate(
				0,
				FIVE_HUNDRED,
				this.raisyToken.address,
				{ from: owner }
			);

			console.log(`
            *Event NewDonation should be emitted with correct values: 
            id = 0, 
            donor = ${owner}, 
            amount = ${FIVE_HUNDRED.toString()},
						payToken: ${this.raisyToken.address}
            `);
			expectEvent(receipt, "NewDonation", {
				campaignId: "0",
				donor: owner,
				amount: "0",
				payToken: this.raisyToken.address,
			});

			expect(
				await this.raisyCampaigns.getAmountDonated(
					owner,
					0,
					this.raisyToken.address
				)
			).to.be.bignumber.equal(FIVE_HUNDRED);

			const raisyBalance = await this.raisyToken.balanceOf(
				this.raisyCampaigns.address
			);

			console.log(
				`*There is ${raisyBalance} $RSY on the RaisyCampaigns contract.`
			);
			expect(raisyBalance).to.be.bignumber.equal(FIVE_HUNDRED);
		});
	});

	describe("claimInitialFunds()", async () => {
		const ADD_BLOCK = 50;
		const BLOCK_DURATION = 100;

		const AMOUNT_RAISED = new BN(ether("15000"));

		beforeEach(async () => {
			await this.raisyCampaigns.setBlockOverride(ADD_BLOCK);

			await this.raisyCampaigns.methods[
				"addCampaign(uint256,uint256,uint256,uint256[])"
			](BLOCK_DURATION, AMOUNT_TO_RAISE, new BN("2"), [5000, 5000], {
				from: projectowner,
			});
		});

		it("reverts if the campaign doesn't exist", async () => {
			await expectRevert(
				this.raisyCampaigns.claimInitialFunds(1, { from: projectowner }),
				"Campaign does not exist."
			);
		});

		it("reverts if the campaign is not over", async () => {
			// BLOCK NUMBER = 100 AND ENB BLOCK = 150
			await this.raisyCampaigns.setBlockOverride(BLOCK_DURATION);

			await expectRevert(
				this.raisyCampaigns.claimInitialFunds(0, { from: projectowner }),
				"Campaign is not over."
			);
		});

		it("reverts if the campaign has not been a success", async () => {
			// BLOCK NUMBER = 151 AND ENB BLOCK = 150
			await this.raisyCampaigns.setBlockOverride(
				ADD_BLOCK + BLOCK_DURATION + 1
			);

			await expectRevert(
				this.raisyCampaigns.claimInitialFunds(0, { from: projectowner }),
				"Campaign hasn't been successful."
			);
		});

		it("reverts if caller is not the campaign creator", async () => {
			// BLOCK NUMBER = 151 AND ENB BLOCK = 150
			await this.raisyCampaigns.setBlockOverride(
				ADD_BLOCK + BLOCK_DURATION + 1
			);

			await this.raisyCampaigns.updateAmountRaised(0, AMOUNT_RAISED, {
				from: owner,
			});

			await expectRevert(
				this.raisyCampaigns.claimInitialFunds(0, { from: owner }),
				"You're not the creator ."
			);
		});

		it("successfuly claim initial funds", async () => {
			await this.raisyToken.approve(
				this.raisyCampaigns.address,
				AMOUNT_RAISED,
				{ from: owner }
			);

			await this.raisyCampaigns.donate(
				0,
				AMOUNT_RAISED,
				this.raisyToken.address,
				{ from: owner }
			);

			// BLOCK NUMBER = 151 AND ENB BLOCK = 150
			await this.raisyCampaigns.setBlockOverride(
				ADD_BLOCK + BLOCK_DURATION + 1
			);

			await this.raisyCampaigns.updateAmountRaised(0, AMOUNT_RAISED, {
				from: owner,
			});

			const balanceBefore = await this.raisyToken.balanceOf(projectowner);
			await this.raisyCampaigns.claimInitialFunds(0, { from: projectowner });
			const balanceAfter = await this.raisyToken.balanceOf(projectowner);

			console.log("Balance before claim : ", balanceBefore.toString());
			console.log("Balance after claim : ", balanceAfter.toString());

			expect(balanceAfter).to.be.bignumber.equal(ether("7500"));
		});
	});

	describe("withdrawFunds()", async () => {
		const ADD_BLOCK = 50;
		const BLOCK_DURATION = 100;

		const AMOUNT_RAISED = new BN(ether("15000"));

		beforeEach(async () => {
			// Go to block 50
			await this.raisyCampaigns.setBlockOverride(ADD_BLOCK);
			await this.raisyChef.setBlockOverride(ADD_BLOCK);

			// Add the campaign
			await this.raisyCampaigns.methods[
				"addCampaign(uint256,uint256,uint256,uint256[])"
			](BLOCK_DURATION, AMOUNT_TO_RAISE, new BN("2"), [5000, 5000], {
				from: projectowner,
			});

			// Approves the contract to use $RSY
			await this.raisyToken.approve(this.raisyCampaigns.address, FIVE_HUNDRED, {
				from: owner,
			});

			// Donate 500 $RSY
			await this.raisyCampaigns.donate(
				0,
				FIVE_HUNDRED,
				this.raisyToken.address,
				{ from: owner }
			);
		});

		it("reverts if the campaign doesn't exist", async () => {
			await expectRevert(
				this.raisyCampaigns.withdrawFunds(1, this.raisyToken.address, {
					from: owner,
				}),
				"Campaign does not exist."
			);
		});

		it("reverts if the campaign is not over", async () => {
			await expectRevert(
				this.raisyCampaigns.withdrawFunds(0, this.raisyToken.address, {
					from: owner,
				}),
				"Campaign is not over."
			);
		});

		it("reverts if the campaign has been successful", async () => {
			// Go to block 151 -> the campaign is finished
			await this.raisyCampaigns.setBlockOverride(
				ADD_BLOCK + BLOCK_DURATION + 1
			);

			await this.raisyCampaigns.updateAmountRaised(0, AMOUNT_RAISED, {
				from: owner,
			});

			await expectRevert(
				this.raisyCampaigns.withdrawFunds(0, this.raisyToken.address, {
					from: owner,
				}),
				"Campaign has been successful."
			);
		});

		it("reverts if there are no funds to withdraw", async () => {
			// Go to block 151 -> the campaign is finished
			await this.raisyCampaigns.setBlockOverride(
				ADD_BLOCK + BLOCK_DURATION + 1
			);

			await expectRevert(
				this.raisyCampaigns.withdrawFunds(0, this.raisyToken.address, {
					from: user,
				}),
				"No more funds to withdraw."
			);
		});

		it("reverts if the pay token is not valid", async () => {
			// Go to block 151 -> the campaign is finished
			await this.raisyCampaigns.setBlockOverride(
				ADD_BLOCK + BLOCK_DURATION + 1
			);

			await expectRevert(
				this.raisyCampaigns.withdrawFunds(0, this.mockERC20.address, {
					from: owner,
				}),
				"invalid pay token"
			);
		});

		it("successfuly whithdraws funds", async () => {
			// Go to block 151 -> the campaign is finished
			await this.raisyCampaigns.setBlockOverride(
				ADD_BLOCK + BLOCK_DURATION + 1
			);
			await this.raisyChef.setBlockOverride(5000);

			const balanceBefore = await this.raisyToken.balanceOf(owner);
			console.log(`Balance before withdrawing = ${balanceBefore.toString()}`);

			await this.raisyCampaigns.withdrawFunds(0, this.raisyToken.address, {
				from: owner,
			});

			const balanceAfter = await this.raisyToken.balanceOf(owner);
			console.log(`Balance after withdrawing = ${balanceAfter.toString()}`);
		});
	});

	describe("claimNextFunds()", async () => {
		const ADD_BLOCK = 50;
		const BLOCK_DURATION = 100;

		const AMOUNT_RAISED = new BN(ether("15000"));

		const claimInitialFunds = async () => {
			await this.raisyToken.approve(
				this.raisyCampaigns.address,
				AMOUNT_RAISED,
				{ from: owner }
			);

			await this.raisyCampaigns.donate(
				0,
				AMOUNT_RAISED,
				this.raisyToken.address,
				{ from: owner }
			);

			// BLOCK NUMBER = 151 AND ENB BLOCK = 150
			await this.raisyCampaigns.setBlockOverride(
				ADD_BLOCK + BLOCK_DURATION + 1
			);

			await this.raisyCampaigns.updateAmountRaised(0, AMOUNT_RAISED, {
				from: owner,
			});

			await this.raisyCampaigns.claimInitialFunds(0, { from: projectowner });
		};

		beforeEach(async () => {
			await this.raisyCampaigns.setBlockOverride(ADD_BLOCK);

			await this.raisyCampaigns.methods[
				"addCampaign(uint256,uint256,uint256,uint256[])"
			](BLOCK_DURATION, AMOUNT_TO_RAISE, new BN("2"), [5000, 5000], {
				from: projectowner,
			});
		});

		it("reverts if the campaign doesn't exist", async () => {
			await expectRevert(
				this.raisyCampaigns.claimNextFunds(1, { from: projectowner }),
				"Campaign does not exist."
			);
		});

		it("reverts if the campaign is not over", async () => {
			// BLOCK NUMBER = 100 AND ENB BLOCK = 150
			await this.raisyCampaigns.setBlockOverride(BLOCK_DURATION);

			await expectRevert(
				this.raisyCampaigns.claimNextFunds(0, { from: projectowner }),
				"Campaign is not over."
			);
		});

		it("reverts if the campaign has not been a success", async () => {
			// BLOCK NUMBER = 151 AND ENB BLOCK = 150
			await this.raisyCampaigns.setBlockOverride(
				ADD_BLOCK + BLOCK_DURATION + 1
			);

			await expectRevert(
				this.raisyCampaigns.claimNextFunds(0, { from: projectowner }),
				"Campaign hasn't been successful."
			);
		});

		// TODO
		// it("reverts if there isn't anymore funds to claim", async () => {

		// })

		it("reverts if the initial funds haven't been claimed", async () => {
			await this.raisyCampaigns.setBlockOverride(
				ADD_BLOCK + BLOCK_DURATION + 1
			);

			await this.raisyCampaigns.updateAmountRaised(0, AMOUNT_RAISED, {
				from: owner,
			});

			await expectRevert(
				this.raisyCampaigns.claimNextFunds(0, { from: projectowner }),
				"Initial funds not claimed."
			);
		});

		it("successfuly claims next funds", async () => {
			await claimInitialFunds();

			// Init vote session
			await this.raisyCampaigns.askMoreFunds(0, { from: projectowner });

			// Claim PoD
			await this.raisyCampaigns.claimProofOfDonation(0, { from: owner });

			// Vote YES
			await this.raisyCampaigns.vote(0, true, { from: owner });

			// Claim Next Funds
			// BLOCK NUMBER = 151 + 84200 +1  AND ENB BLOCK = 151+84200
			await this.raisyCampaigns.setBlockOverride(151 + 84200 + 1);
			const balanceBefore = await this.raisyToken.balanceOf(projectowner);
			await this.raisyCampaigns.claimNextFunds(0, { from: projectowner });
			const balanceAfter = await this.raisyToken.balanceOf(projectowner);

			console.log(
				"Balance before claim next funds : ",
				balanceBefore.toString()
			);
			console.log("Balance after claim next funds : ", balanceAfter.toString());
			expect(balanceAfter).to.be.bignumber.equal(ether("15000"));
		});
	});
});
