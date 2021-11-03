const {
    BN,
    constants,
    expectEvent,
    expectRevert,
    balance,
} = require('@openzeppelin/test-helpers');
const { ZERO_ADDRESS } = constants;

const { expect } = require('chai');

const raisyCampaigns = artifacts.require('RaisyCampaigns');

contract('RaisyCampaigns', function ([
    owner,
    projectowner,
    feeRecipient,
]) {
    const ZERO = new BN('0');
    const AMOUNT = new BN("100000000000");
    const EX_MAX_DUR = new BN("1000");

    beforeEach(async function () {
        this.campaign = await raisyCampaigns.new({ from: owner });
      });
    describe('Add campaign', async function () {
        it('Reverts when max duration is exceeded', async function() {
            await expectRevert(
                this.campaign.addCampaign(
                    "100",
                    "20000",
                    { from: owner },
                ),
                "duration too long"
            );
        });

    });
})