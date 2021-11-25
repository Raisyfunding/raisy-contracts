// to deploy locally
// run: npx hardhat node on a terminal
// then run: npx hardhat run --network localhost scripts/deploy_all.js
async function main(network) {

  console.log('network: ', network.name);

  const [deployer] = await ethers.getSigners();
  const deployerAddress = await deployer.getAddress();
  console.log(`Deployer's address: `, deployerAddress);

  const { TREASURY_ADDRESS, PLATFORM_FEE, WRAPPED_MATIC_MAINNET, WRAPPED_MATIC_TESTNET } = require('../constants');

  /////////
  const RaisyCampaigns = await ethers.getContractFactory('RaisyCampaigns');
  const raisyCampaigns = await upgrades.deployProxy(RaisyCampaigns, []);

  await raisyCampaigns.deployed();

  console.log('RaisyCampaigns deployed to:', raisyCampaigns.address);
  
  /////////

  /////////
  const BundleMarketplace = await ethers.getContractFactory(
      'RaisyBundleMarketplace'
    );
  const bundleMarketplaceImpl = await BundleMarketplace.deploy();
  await bundleMarketplaceImpl.deployed();
  console.log('RaisyBundleMarketplace deployed to:', bundleMarketplaceImpl.address);
  
  const bundleMarketplaceProxy = await AdminUpgradeabilityProxyFactory.deploy(
      bundleMarketplaceImpl.address,
      PROXY_ADDRESS,
      []
    );
  await bundleMarketplaceProxy.deployed();
  console.log('Bundle Marketplace Proxy deployed at ', bundleMarketplaceProxy.address);  
  const BUNDLE_MARKETPLACE_PROXY_ADDRESS = bundleMarketplaceProxy.address;
  const bundleMarketplace = await ethers.getContractAt('RaisyBundleMarketplace', bundleMarketplaceProxy.address);
  
  await bundleMarketplace.initialize(TREASURY_ADDRESS, PLATFORM_FEE);
  console.log('Bundle Marketplace Proxy initialized');
  
  ////////

  ////////
  const Auction = await ethers.getContractFactory('RaisyAuction');
  const auctionImpl = await Auction.deploy();
  await auctionImpl.deployed();
  console.log('RaisyAuction deployed to:', auctionImpl.address);

  const auctionProxy = await AdminUpgradeabilityProxyFactory.deploy(
      auctionImpl.address,
      PROXY_ADDRESS,
      []
    );

  await auctionProxy.deployed();
  console.log('Auction Proxy deployed at ', auctionProxy.address);
  const AUCTION_PROXY_ADDRESS = auctionProxy.address;
  const auction = await ethers.getContractAt('RaisyAuction', auctionProxy.address);
  
  await auction.initialize(TREASURY_ADDRESS);
  console.log('Auction Proxy initialized');
 
  ////////

  ////////
  const Factory = await ethers.getContractFactory('RaisyNFTFactory');
  const factory = await Factory.deploy(
      AUCTION_PROXY_ADDRESS,
      MARKETPLACE_PROXY_ADDRESS,
      BUNDLE_MARKETPLACE_PROXY_ADDRESS,
      '10000000000000000000',
      TREASURY_ADDRESS,
      '50000000000000000000'
  );
  await factory.deployed();
  console.log('RaisyNFTFactory deployed to:', factory.address);

  const PrivateFactory = await ethers.getContractFactory(
      'RaisyNFTFactoryPrivate'
  );
  const privateFactory = await PrivateFactory.deploy(
      AUCTION_PROXY_ADDRESS,
      MARKETPLACE_PROXY_ADDRESS,
      BUNDLE_MARKETPLACE_PROXY_ADDRESS,
      '10000000000000000000',
      TREASURY_ADDRESS,
      '50000000000000000000'
  );
  await privateFactory.deployed();
  console.log('RaisyNFTFactoryPrivate deployed to:', privateFactory.address);
  ////////    

  ////////
  const RaisyNFT = await ethers.getContractFactory('RaisyNFTTradable');
  const nft = await NFTTradable.deploy(
      'Artion',
      'ART',
      AUCTION_PROXY_ADDRESS,
      MARKETPLACE_PROXY_ADDRESS,
      BUNDLE_MARKETPLACE_PROXY_ADDRESS,
      '10000000000000000000',
      TREASURY_ADDRESS
  );
  await nft.deployed();
  console.log('RaisyNFTTradable deployed to:', nft.address);

  const NFTTradablePrivate = await ethers.getContractFactory(
      'RaisyNFTTradablePrivate'
  );
  const nftPrivate = await NFTTradablePrivate.deploy(
      'IArtion',
      'IART',
      AUCTION_PROXY_ADDRESS,
      MARKETPLACE_PROXY_ADDRESS,
      BUNDLE_MARKETPLACE_PROXY_ADDRESS,
      '10000000000000000000',
      TREASURY_ADDRESS
  );
  await nftPrivate.deployed();
  console.log('RaisyNFTTradablePrivate deployed to:', nftPrivate.address);
  ////////

  ////////
  const TokenRegistry = await ethers.getContractFactory('RaisyTokenRegistry');
  const tokenRegistry = await TokenRegistry.deploy();

  await tokenRegistry.deployed();

  console.log('RaisyTokenRegistry deployed to', tokenRegistry.address);
  ////////

  ////////
  const AddressRegistry = await ethers.getContractFactory('RaisyAddressRegistry');
  const addressRegistry = await AddressRegistry.deploy();

  await addressRegistry.deployed();

  console.log('RaisyAddressRegistry deployed to', addressRegistry.address);
  const RAISY_ADDRESS_REGISTRY = addressRegistry.address;
  ////////

  ////////
  const PriceFeed = await ethers.getContractFactory('RaisyPriceFeed');
  const WRAPPED_MATIC = network.name === 'mainnet' ? WRAPPED_MATIC_MAINNET : WRAPPED_MATIC_TESTNET;
  const priceFeed = await PriceFeed.deploy(
    RAISY_ADDRESS_REGISTRY,
    WRAPPED_MATIC
  );

  await priceFeed.deployed();

  console.log('RaisyPriceFeed deployed to', priceFeed.address);
  ////////

 


  
  await marketplace.updateAddressRegistry(RAISY_ADDRESS_REGISTRY);   
  await bundleMarketplace.updateAddressRegistry(RAISY_ADDRESS_REGISTRY);
  
  await auction.updateAddressRegistry(RAISY_ADDRESS_REGISTRY);
  
  await addressRegistry.updateArtion(artion.address);
  await addressRegistry.updateAuction(auction.address);
  await addressRegistry.updateMarketplace(marketplace.address);
  await addressRegistry.updateBundleMarketplace(bundleMarketplace.address);
  await addressRegistry.updateNFTFactory(factory.address);
  await addressRegistry.updateTokenRegistry(tokenRegistry.address);
  await addressRegistry.updatePriceFeed(priceFeed.address);
  await addressRegistry.updateArtFactory(artFactory.address);   

  await tokenRegistry.add(WRAPPED_MATIC);

}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main(network)
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });


