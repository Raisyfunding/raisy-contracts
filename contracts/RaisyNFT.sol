// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title RaisyNFT
 * @author Raisyfunding
 * RaisyNFT - ERC721 contract that whitelists a trading address, and has minting functionality.
 */
contract RaisyNFT is ERC721, ERC721Enumerable, Ownable {
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIdCounter;

    /// @notice tokenId -> Donation Info
    mapping(uint256 => DonationInfo) private _donationInfo;

    struct DonationInfo {
        uint256 amount;
        address tokenUsed;
        uint256 campaignId;
        address recipient;
        uint256 creationTimestamp;
    }

    event Minted(uint256 tokenId, DonationInfo param);

    constructor(string memory _name, string memory _symbol)
        ERC721(_name, _symbol)
    {}

    /**
     * @notice Mints a new Proof Of Donation
     * @param params Info of the donation
     */
    function mint(DonationInfo calldata params)
        external
        onlyOwner
        returns (uint256)
    {
        uint256 newTokenId = _tokenIdCounter.current();
        _safeMint(params.recipient, newTokenId);

        _donationInfo[newTokenId] = params;

        emit Minted(newTokenId, params);

        return newTokenId;
    }

    /// @notice Returns the donation info of a given Token
    /// @param _tokenId Id of the token
    function getDonationInfo(uint256 _tokenId)
        external
        view
        returns (DonationInfo memory)
    {
        return _donationInfo[_tokenId];
    }

    /**
    @notice Burns a NFT
    @dev Only the owner or an approved sender can call this method
    @param _tokenId the token ID to burn and the mapping too
    */
    function burn(uint256 _tokenId) external {
        address operator = _msgSender();
        require(ownerOf(_tokenId) == operator, "Not owner or approved sender.");

        // Destroy token mappings
        _burn(_tokenId);
        delete _donationInfo[_tokenId];
    }

    // The following functions are overrides required by Solidity.

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
