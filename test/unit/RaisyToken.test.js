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

contract("RaisyToken", ([owner, projectowner, feeRecipient]) => {
	const MAX_SUPPLY = new BN(ether("10000000"));
	const OVER_MAX_SUPPLY = new BN(ether("10000001"));
	const ONE_THOUSAND = new BN(ether("1000"));
	const WRONG_MAXCAP = new BN("0");

	describe("Constructor", () => {
		it("reverts when wrong maxcap", async () => {
			await expectRevert(
				RaisyToken.new("RaisyToken", "RSY", WRONG_MAXCAP, { from: owner }),
				"ERC20Capped: cap is 0"
			);
		});
	});

	beforeEach(async () => {
		this.raisyToken = await RaisyToken.new("RaisyToken", "RSY", MAX_SUPPLY, {
			from: owner,
		});
	});

	describe("Mint tokens", () => {
		it("reverts when caller is not owner", async () => {
			await expectRevert(
				this.raisyToken.mint(owner, ONE_THOUSAND, { from: projectowner }),
				"Ownable: caller is not the owner"
			);
		});
		it("successfully mints 1000 token", async () => {
			await this.raisyToken.mint(owner, ONE_THOUSAND, { from: owner });

			expect(await this.raisyToken.circulatingSupply()).to.be.bignumber.equal(
				ONE_THOUSAND
			);
		});
		it("reverts when exceed cap", async () => {
			await expectRevert(
				this.raisyToken.mint(owner, OVER_MAX_SUPPLY, { from: owner }),
				"ERC20Capped: cap exceeded"
			);
		});
		describe("View functions", () => {
			it("Returns maxcap", async () => {
				expect(
					await this.raisyToken.maxsupplycap({ from: owner })
				).to.be.bignumber.equal(MAX_SUPPLY);
			});
		});
	});
});
