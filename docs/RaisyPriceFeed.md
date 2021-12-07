## `RaisyPriceFeed`






### `constructor(address _addressRegistry, address _wMATIC)` (public)





### `registerOracle(address _token, address _oracle)` (external)

Register oracle contract to token
     @dev Only owner can register oracle
     @param _token ERC20 token address
     @param _oracle Oracle address



### `updateOracle(address _token, address _oracle)` (external)

Update oracle address for token
     @dev Only owner can update oracle
     @param _token ERC20 token address
     @param _oracle Oracle address



### `getPrice(address _token) → int256, uint8` (external)

Get current price for token
     @dev return current price or if oracle is not registered returns 0
     @param _token ERC20 token address



### `updateAddressRegistry(address _addressRegistry)` (external)

Update address registry contract
     @dev Only admin






