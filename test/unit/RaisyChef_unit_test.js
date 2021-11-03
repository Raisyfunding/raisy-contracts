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
const RaisyChef = artifacts.require("RaisyChef");

contract("RaisyChef", ([owner, projectowner, daotreasuryadd]) => {
  const MAX_SUPPLY = new BN(ether("10000000"));
  const REW_PER_BLOCK = new BN("10");
  const LOCK = new BN("100");
  const START_BLOCK = new BN("1");
  const END_BLOCK = new BN("15000");
  const ONE_THOUSAND = new BN(ether("1000"));

  beforeEach(async () => {
    this.raisyToken = await RaisyToken.new("RaisyToken", "RSY", MAX_SUPPLY, {
      from: owner,
    });
    this.raisyToken.mint(owner, ONE_THOUSAND, { from: owner });

    this.chef = await RaisyChef.new(
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
    this.chef.add("1", END_BLOCK);
  });
  describe("Test views", () => {
    it("Returns poollength", async () => {
      expect(await this.chef.poolLength()).to.be.bignumber.equal("1");
    });
  });
});
