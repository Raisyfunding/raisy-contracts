// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "openzeppelin-solidity/contracts/utils/math/SafeMath.sol";

/// @author Raisyfunding
/// @title RaisyToken
contract RaisyToken is ERC20, Ownable {
    using SafeMath for uint256;

    /// Variable declarations

    uint256 private _maxsupplycap;

    /// @notice Constructor of RaisyToken.
    /// @param _name Token's name
    /// @param _symbol Token's symbol
    /// @param maxsupplycap_ Token's max supply
    constructor(
        string memory _name,
        string memory _symbol,
        uint256 maxsupplycap_
    ) ERC20(_name, _symbol) {
        _maxsupplycap = maxsupplycap_;
    }

    /// @dev View returns the maxcap on the token's total supply.
    /// @return maxSupplyCap
    function maxsupplycap() public view returns (uint256) {
        return _maxsupplycap;
    }

    /// @dev View returns the circulating supply
    /// @return totalSupply
    function circulatingSupply() public view returns (uint256) {
        return totalSupply();
    }

    /// @dev See {ERC20-_beforeTokenTransfer}
    /// @dev minted tokens must not cause the total supply to go over the cap.
    /// @param from Sender
    /// @param to Reciever
    /// @param amount Amount sent
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, amount);
        if (from == address(0)) {
            // When minting tokens
            require(
                totalSupply().add(amount) <= _maxsupplycap,
                "ERC20Capped: cap exceeded"
            );
        }
    }

    /// @dev Creates `_amount` token to `_to`. Must only be called by the owner.
    /// @param _to Reciever
    /// @param _amount Amount sent
    function mint(address _to, uint256 _amount) public onlyOwner {
        _mint(_to, _amount);
    }

    /// @dev View returns the total balance of an address.
    /// @param _holder Address of the account
    function totalBalanceOf(address _holder) public view returns (uint256) {
        return balanceOf(_holder);
    }
}
