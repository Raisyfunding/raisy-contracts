// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../RaisyChef.sol";

contract MockRaisyChef is RaisyChef {
    uint256 public blockOverride;

    constructor(
        RaisyToken _Raisy,
        address _daotreasuryaddr,
        uint256 _rewardPerBlock,
        uint256 _lockDuration,
        uint256 _startBlock
    )
        RaisyChef(
            _Raisy,
            _daotreasuryaddr,
            _rewardPerBlock,
            _lockDuration,
            _startBlock
        )
    {}

    function setBlockOverride(uint256 _block) external {
        blockOverride = _block;
    }

    function _getBlock() internal view override returns (uint256) {
        return blockOverride;
    }
}
