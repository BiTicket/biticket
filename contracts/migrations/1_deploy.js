const TokenStable = artifacts.require("TokenStable");
const Factory = artifacts.require("Factory");
const Platform = artifacts.require("Platform");
const Events = artifacts.require("Events");
const Users = artifacts.require("Users");

module.exports = async function(deployer) {
  await deployer.deploy(TokenStable);
  const tokenStable = await TokenStable.deployed()
  await deployer.deploy(Factory);
  const factory = await Factory.deployed()
  await deployer.deploy(Platform, tokenStable.address);
  const platform = await Platform.deployed()
  await deployer.deploy(Events, platform.address, factory.address);
  await deployer.deploy(Users, platform.address);

};