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
const RaisyChef = artifacts.require("MockRaisyChef");

contract("RaisyChef", ([owner, projectowner, daotreasuryadd]) => {
  const MAX_SUPPLY = new BN(ether("10000000"));
  const REW_PER_BLOCK = new BN("10");
  const LOCK = new BN("100");
  const START_BLOCK = new BN("1");
  const BLOCK = new BN("1000");
  const END_BLOCK = new BN("15000");
  const ONE_THOUSAND = new BN(ether("1000"));
  const DAO_BONUS = new BN("2");

  beforeEach(async () => {
    this.raisyToken = await RaisyToken.new("RaisyToken", "RSY", MAX_SUPPLY, {
      from: owner,
    });
    this.raisyToken.mint(owner, ONE_THOUSAND, { from: owner });

    this.chef = await RaisyChef.new(
      this.raisyToken.address,
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
    it("Test getPoolReward", async () => {
      expect(await this.chef.getPoolReward(START_BLOCK, BLOCK, DAO_BONUS));
    });
  });
  describe("Test addPool", () => {
    it("Reverts when pool already exists", async () => {
      await expectRevert(
        this.chef.add("1", END_BLOCK),
        "RaisyChef::nonDuplicated: duplicated"
      );
    });
    it("Successfully adds a pool", async () => {
      await this.chef.add("2", END_BLOCK);
      expect(await this.chef.poolLength()).to.be.bignumber.equal("2");
    });
  });
  describe("Test setPool", () => {
    it("reverts when not owner", async () => {
      await expectRevert(
        this.chef.set("0", END_BLOCK, DAO_BONUS, {
          from: projectowner,
        }),
        "Ownable: caller is not the owner"
      );
    });

    it("Successfully change the pool", async () => {
      await this.chef.set("0", BLOCK, DAO_BONUS, {
        from: owner,
      });
      const poolinfo = await this.chef.poolInfo.call(0);
      expect(poolinfo.endBlock).to.be.bignumber.equal(BLOCK);
    });

    //Check enblock>block.number with mock contract
    it("reverts when enblock in the past", async () => {
      await this.chef.setBlockOverride(END_BLOCK);
      await expectRevert(
        this.chef.set("0", BLOCK, DAO_BONUS, {
          from: owner,
        }),
        "End block in the past"
      );
    });
  });
  describe("Test updatepool" () => {

  })
});
