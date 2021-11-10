const { expect } = require("chai");

const {
	BN,
	constants,
	expectEvent,
	expectRevert,
	balance,
	ether,
} = require("@openzeppelin/test-helpers");

const RaisyFundsRelease = artifacts.require("RaisyFundsRelease");
const RaisyNFT = artifacts.require("RaisyNFT");

contract("RaisyFundsRelease", ([owner, projectowner, user1, user2]) => {

	


})