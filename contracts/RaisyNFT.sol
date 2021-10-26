// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title RaisyNFT
 * RaisyNFT - ERC721 contract that whitelists a trading address, and has minting functionality.
 */
contract RaisyNFT is ERC721, Ownable {
    mapping(uint256 => DonationInfo) private _donationInfo;

    struct DonationInfo {
        uint256 amount;
        address tokenUsed;
        uint256 campaignId;
        address recipient;
        uint256 creationTimestamp;
    }

    event Minted(uint256 tokenId, donationInfo param);

    uint256 private _currentTokenId = 0;

    constructor(string memory _name, string memory _symbol)
        ERC721(_name, _symbol)
    {}

    /**
     * @dev Mints a token to an address with a tokenURI.
     */

    function mint(DonationInfo calldata params)
        external
        onlyOwner
        returns (uint256)
    {
        uint256 newTokenId = _getNextTokenId();
        _safeMint(params.recipient, newTokenId);
        _donationInfo[newTokenId] = params;
        emit Minted(newTokenId, params);

        return newTokenId;
    }

    /**
    @notice Burns a tNFT
    @dev Only the owner or an approved sender can call this method
    @param _tokenId the token ID to burn and the mapping too
    */
    function burn(uint256 _tokenId) external {
        address operator = _msgSender();
        require(ownerOf(_tokenId) == operator);

        // Destroy token mappings
        _burn(_tokenId);
        delete _donationInfo[_tokenId];
    }

    /**
     * @dev calculates the next token ID based on value of _currentTokenId
     * @return uint256 for the next token ID
     */
    function _getNextTokenId() internal returns (uint256) {
        return _currentTokenId++;
    }
}
