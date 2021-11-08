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
  const NEW_REW = new BN("5");
  const LOCK = new BN("100");
  const START_BLOCK = new BN("1");
  const BLOCK = new BN("1000");
  const END_BLOCK = new BN("15000");
  const ONE_THOUSAND = new BN(ether("1000"));
  const TWO_THOUSAND = new BN(ether("2000"));
  const DAO_BONUS = new BN("2");

  beforeEach(async () => {
    this.raisyToken = await RaisyToken.new("RaisyToken", "RSY", MAX_SUPPLY, {
      from: owner,
    });
    await this.raisyToken.mint(owner, ONE_THOUSAND, { from: owner });
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
    await this.chef.add("1", END_BLOCK);
    await this.chef.deposit(owner, "0", ONE_THOUSAND);
    await this.raisyToken.transferOwnership(this.chef.address);
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
        "RaisyChef::duplicated"
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
  describe("Test claimRewards", () => {
    it("reverts when campaign not ended", async () => {
      await this.chef.setBlockOverride(END_BLOCK - 1);
      await expectRevert(
        this.chef.claimRewards(owner, "0"),
        "Campaign is not over yet."
      );
    });
    it("Successfully claims rewards", async () => {
      await this.chef.setBlockOverride(END_BLOCK + 1000);
      const _balancee = await this.raisyToken.balanceOf(owner);
      await this.chef.claimRewards(owner, "0");
      const _balance = await this.raisyToken.balanceOf(owner);
      expect(_balance).to.be.bignumber.greaterThan(ONE_THOUSAND);
    });
  });
  describe("Tests deposit", () => {
    it("Reverts when not owner", async () => {
      await expectRevert(
        this.chef.deposit(projectowner, "0", ONE_THOUSAND, {
          from: projectowner,
        }),
        "Ownable: caller is not the owner"
      );
    });
    it("Reverts when wrong amount", async () => {
      await expectRevert(
        this.chef.deposit(owner, "0", "0"),
        "Amount must be greater than 0"
      );
    });
    it("successfully deposit", async () => {
      await this.chef.deposit(owner, "0", ONE_THOUSAND, { from: owner });
      const poolinfo = await this.chef.poolInfo.call(0);
      expect(poolinfo.amountStaked).to.be.bignumber.equal(TWO_THOUSAND);
    });
  });
  describe("Test daoTreasuryUpdate", () => {
    it("reverts when not Authorized", async () => {
      await expectRevert(
        this.chef.daoTreasuryUpdate(owner, { from: projectowner }),
        "caller is not authorized"
      );
    });
    it("successfully change the address", async () => {
      await this.chef.daoTreasuryUpdate(this.raisyToken.address, {
        from: owner,
      });
      const dao = await this.chef.daotreasuryaddr.call();
      await expect(dao).to.be.equal(this.raisyToken.address);
    });
  });
  describe("Test rewardUpdate", () => {
    it("reverts when not Authorized", async () => {
      await expectRevert(
        this.chef.rewardUpdate(owner, { from: projectowner }),
        "caller is not authorized"
      );
    });
    it("successfully change the address", async () => {
      await this.chef.rewardUpdate(NEW_REW, {
        from: owner,
      });
      const reward = await this.chef.rewardPerBlock.call();
      await expect(reward).to.be.bignumber.equal(NEW_REW);
    });
  });
  describe("Test starblockUpdate", () => {
    it("reverts when not Owner", async () => {
      await expectRevert(
        this.chef.starblockUpdate(owner, { from: projectowner }),
        "Ownable: caller is not the owner"
      );
    });
    it("successfully change the address", async () => {
      await this.chef.starblockUpdate(NEW_REW, {
        from: owner,
      });
      const block = await this.chef.startBlock.call();
      await expect(block).to.be.bignumber.equal(NEW_REW);
    });
  });
  describe("Test daoRewardsUpdate", () => {
    it("reverts when not Authorized", async () => {
      await expectRevert(
        this.chef.daoRewardsUpdate(owner, { from: projectowner }),
        "caller is not authorized"
      );
    });
    it("successfully change the dao percent", async () => {
      await this.chef.daoRewardsUpdate(NEW_REW, {
        from: owner,
      });
      const daorew = await this.chef.percentForDao.call();
      await expect(daorew).to.be.bignumber.equal(NEW_REW);
    });
  });
});
