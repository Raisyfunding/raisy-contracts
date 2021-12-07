## `RaisyNFT`






### `constructor(string _name, string _symbol)` (public)





### `mint(struct RaisyNFT.DonationInfo params) → uint256` (external)

Mints a new Proof Of Donation




### `getDonationInfo(uint256 _tokenId) → struct RaisyNFT.DonationInfo` (external)

Returns the donation info of a given Token




### `burn(uint256 _tokenId)` (external)

Burns a NFT
    @dev Only the owner or an approved sender can call this method
    @param _tokenId the token ID to burn and the mapping too



### `_beforeTokenTransfer(address from, address to, uint256 tokenId)` (internal)





### `supportsInterface(bytes4 interfaceId) → bool` (public)






### `Minted(uint256 tokenId, struct RaisyNFT.DonationInfo param)`






### `DonationInfo`


uint256 amount


address tokenUsed


uint256 campaignId


address recipient


uint256 creationTimestamp



