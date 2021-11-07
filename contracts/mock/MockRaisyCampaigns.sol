// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../RaisyCampaigns.sol";

contract MockRaisyCampaigns is RaisyCampaigns {
    uint256 public blockOverride;

    function setBlockOverride(uint256 _block) external {
        blockOverride = _block;
    }

    function _getBlock() internal view override returns (uint256) {
        return blockOverride;
    }
}
