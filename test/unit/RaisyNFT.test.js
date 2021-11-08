const { expect } = require("chai");

const {
	BN,
	constants,
	expectEvent,
	expectRevert,
	balance,
	ether,
} = require("@openzeppelin/test-helpers");

const RaisyNFT = artifacts.require("RaisyNFT");
const RaisyToken = artifacts.require("RaisyToken");

contract("RaisyNFT", ([owner, user, projectowner]) => {
	let donation;
	const MAX_SUPPLY = new BN(ether("10000000"));

	beforeEach(async () => {
		this.raisyNFT = await RaisyNFT.new("RaisyNFT", "POD", { from: owner });
		this.raisyToken = await RaisyToken.new("RaisyToken", "RSY", MAX_SUPPLY, {
			from: owner,
		});

		donation = {
			amount: 100,
			tokenUsed: this.raisyToken.address,
			campaignId: 0,
			recipient: projectowner,
			creationTimestamp: 1636344552,
		};
	});

	describe("mint()", async () => {
		it("reverts if caller is not the owner", async () => {
			await expectRevert(
				this.raisyNFT.mint(donation, { from: user }),
				"Ownable: caller is not the owner"
			);
		});

		it("successfuly mints a proof of donation", async () => {
			const receipt = await this.raisyNFT.mint(donation, { from: owner });

			expectEvent(receipt, "Minted", {
				tokenId: "0",
				// param: donation,
			});

			expect(await this.raisyNFT.totalSupply.call()).to.be.bignumber.equal("1");
			expect(await this.raisyNFT.ownerOf(0)).to.be.equal(projectowner);
		});
	});

	describe("burn()", async () => {
		beforeEach(async () => {
			await this.raisyNFT.mint(donation, { from: owner });
		});

		it("reverts if caller is not the owner of the nft", async () => {
			await expectRevert(
				this.raisyNFT.burn(0, { from: user }),
				"Not owner or approved sender."
			);
		});

		it("successfuly burns the nft when caller is the owner of the nft", async () => {
			await this.raisyNFT.burn(0, { from: projectowner });
		});
	});

	describe("getDonationInfo()", async () => {
		beforeEach(async () => {
			await this.raisyNFT.mint(donation, { from: owner });
		});

		it("returns the correct donation info", async () => {
			const donationInfo = await this.raisyNFT.getDonationInfo(0);
			expect(donationInfo.amount).to.be.bignumber.equal("100");
			expect(donationInfo.tokenUsed).to.be.equal(this.raisyToken.address);
			expect(donationInfo.campaignId).to.be.bignumber.equal("0");
			expect(donationInfo.recipient).to.be.equal(projectowner);
			expect(donationInfo.creationTimestamp).to.be.bignumber.equal(
				"1636344552"
			);
		});
	});
});
