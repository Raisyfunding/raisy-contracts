const {
    BN,
    constants,
    expectEvent,
    expectRevert,
    balance,
} = require('@openzeppelin/test-helpers');
const { ZERO_ADDRESS } = constants;

const { expect } = require('chai');

const RaisyToken = artifacts.require('RaisyToken');

contract('Unit tests for the Raisytoken contract', function ([
    owner,
    projectowner,
    feeRecipient,
]) {
    const minttoken = new BN('10000000000000000000000');


    beforeEach(async function () {
        this.value = new BN(1);
        this.token = await RaisyToken.new("RaisyToken","RSY","10000000000000000000000000",{ from: owner });
      });

    describe('Mint tokens', function () {
        it('reverts when not owner', async function() {
            await expectRevert(
                this.token.mint(
                    owner,
                    "1000",
                    { from: projectowner }
                ),
                "Ownable: caller is not the owner"
            );
        });
    });
})