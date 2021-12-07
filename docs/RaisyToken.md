## `RaisyToken`

Token used in the Raisy protocol for both governance and donations (staking)


Owner is the RaisyChef contract, implements the ERC20Permit standard (OZ) for easy approvals
Max supply cap is also ensured thanks to the ERC20Capped standard (OZ)


### `constructor(string _name, string _symbol, uint256 maxsupplycap_)` (public)

Constructor of RaisyToken.




### `maxsupplycap() → uint256` (public)



View returns the maxcap on the token's total supply.


### `circulatingSupply() → uint256` (public)



View returns the circulating supply


### `_beforeTokenTransfer(address from, address to, uint256 amount)` (internal)



See {ERC20-_beforeTokenTransfer}
minted tokens must not cause the total supply to go over the cap.


### `mint(address _to, uint256 _amount)` (public)



Creates `_amount` token to `_to`. Must only be called by the owner.





