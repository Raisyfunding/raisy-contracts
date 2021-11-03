const { expect } = require("chai");

const {
	BN,
	constants,
	expectEvent,
	expectRevert,
	balance,
	ether,
} = require("@openzeppelin/test-helpers");

const RaisyToken = artifacts.require("RaisyToken");

contract("RaisyToken", function([owner, projectowner, feeRecipient]) {
	const MAX_SUPPLY = new BN(ether("10000000"));
	const OVER_MAX_SUPPLY = new BN(ether("10000001"));
	const ONE_THOUSAND = new BN(ether("1000"));

	beforeEach(async function() {
		this.raisyToken = await RaisyToken.new("RaisyToken", "RSY", MAX_SUPPLY, {
			from: owner,
		});
	});

	describe("Mint tokens", function() {
		it("reverts when caller is not owner", async function() {
			await expectRevert(
				this.raisyToken.mint(owner, ONE_THOUSAND, { from: projectowner }),
				"Ownable: caller is not the owner"
			);
		});
		it("successfully mints 1000 token", async function() {
			await this.raisyToken.mint(owner, ONE_THOUSAND, { from: owner });

			expect(await this.raisyToken.circulatingSupply()).to.be.bignumber.equal(
				ONE_THOUSAND
			);
		});
		it("reverts when exceed cap", async function() {
			await expectRevert(
				this.raisyToken.mint(owner, OVER_MAX_SUPPLY, { from: owner }),
				"ERC20Capped: cap exceeded"
			);
		});
	});
});
