const Web3 = require('web3');
const truffleAssert = require('truffle-assertions');
require('@openzeppelin/test-helpers/configure')({
  provider: web3.eth.currentProvider.host,
})
const { time } = require('@openzeppelin/test-helpers')

const { toBN, toHex, padLeft, hexToBytes, bytesToHex } = web3.utils;
const { getBalance } = web3.eth

const TokenStable = artifacts.require("TokenStable");
const Events = artifacts.require("Events");
const Platform = artifacts.require("Platform");
const Users = artifacts.require("Users");
const Factory = artifacts.require("Factory");
const ticketsABI = require("../build/contracts/Tickets.json")
const escrowABI = require("../build/contracts/Escrow.json")

function getUseTicketParams(contract, eventId, ticketType) {
  const eventIdBytes = hexToBytes(padLeft(toHex(eventId), 8))
  const ticketTypeBytes = hexToBytes(padLeft(toHex(ticketType), 8))
  const nonce = Math.floor(Math.random() * 4294967295)
  const nonceBytes = hexToBytes(padLeft(toHex(nonce), 8))
  return bytesToHex(hexToBytes(contract).concat(eventIdBytes).concat(ticketTypeBytes).concat(nonceBytes))
}

contract("General", function ([deployer, creator, buyer, platformWallet]) {
  let tokenStable, events, platform, users, factory
  before(async function() {
    tokenStable = await TokenStable.deployed()
    events = await Events.deployed()
    platform = await Platform.deployed()
    users = await Users.deployed()
    factory = await Factory.deployed()

    await factory.transferOwnership(events.address);
    await platform.setEventsContract(events.address);
    await platform.setUsersContract(users.address);
    await platform.setPlatformWallet(platformWallet);
    platformFee = 1000
    await platform.setPlatformFee(platformFee);

    await tokenStable.transfer(buyer, Web3.utils.toWei("1000000"))
    await tokenStable.approve(platform.address, Web3.utils.toWei("1000000"), {from: buyer})
  })

  it("Should Not Create User Without Data", async function () {
    await truffleAssert.fails(platform.upsertUser("", {from: creator}))
  });  

  it("Should Create User", async function () {
    await platform.upsertUser("ipfs://creatorMetadata", {from: creator})
    expect(await users.users(creator)).to.be.equal("ipfs://creatorMetadata")
    await platform.upsertUser("ipfs://buyerMetadata", {from: buyer})
    expect(await users.users(buyer)).to.be.equal("ipfs://buyerMetadata")
  });  

  it("Should Create Event", async function () {
    await platform.createEvent({
      creator,
      eventMetadataUri: "ipfs://eventMetadata", 
      NFTMetadataUri: "ipfs://NFTMetadata", 
      ticketsMetadataUris: ["ipfs://TicketMetadata1","ipfs://TicketMetadata2"], 
      ticketsNFTMetadataUris: ["ipfs://TicketNFTMetadata1","ipfs://TicketNFTMetadata2"], 
      prices: [100,1000, 200,2000], 
      maxSupplies: [100, 200], 
      deadline: Math.floor(new Date().getTime() / 1000) + 100,
      percentageWithdraw: 5000
    }, {from: creator})
    expect((await events.totalEvents()).toString()).to.be.equal('1');
    expect((await events.balanceOf(creator)).toString()).to.be.equal('1');
    const event = await events.getEventByRange(0, 0)
    expect(event[0].creator).to.be.equal(creator)
    expect(event[0].eventMetadataUri).to.be.equal("ipfs://eventMetadata")
    expect(event[0].NFTMetadataUri).to.be.equal("ipfs://NFTMetadata")
  });  

  it("Should Buy Ticket With StableCoin", async function () {
    const event = await events.getEventByRange(0, 0)
    const balanceBuyerBefore = await tokenStable.balanceOf(buyer)
    const balanceCreatorBefore = await tokenStable.balanceOf(creator)
    const balanceEscrowBefore = await tokenStable.balanceOf(event[0].escrow)
    const balancePlatformBefore = await tokenStable.balanceOf(platformWallet)
    const ticketType = 0
    const tokenUsed = 0
    const amount = 1

    await tokenStable.approve(event[0].escrow, Web3.utils.toWei("1000000"), {from: buyer})
    await platform.buyTicket(buyer, 0, ticketType, tokenUsed, amount, {from: buyer})
    const tickets = new web3.eth.Contract(ticketsABI.abi, event[0].tickets)
    expect(await tickets.methods.balanceOf(buyer, 0).call()).to.be.equal(amount.toString())
    const ticketInfo = await tickets.methods.getTicketByType(ticketType).call();
    const ticketPrice = ticketInfo.prices[tokenUsed]
    const fee = ticketPrice * platformFee / 10000
    expect((await tokenStable.balanceOf(buyer)).toString()).to.be.equal(
      balanceBuyerBefore.sub(toBN(ticketPrice)).sub(toBN(fee)).toString()
    )
    expect((await tokenStable.balanceOf(creator)).toString()).to.be.equal(balanceCreatorBefore.toString())
    expect((await tokenStable.balanceOf(event[0].escrow)).toString()).to.be.equal(balanceEscrowBefore.add(toBN(ticketPrice)).toString())
    expect((await tokenStable.balanceOf(platformWallet)).toString()).to.be.equal(balancePlatformBefore.add(toBN(fee)).toString())
  });  

  it("Should Buy Ticket With Native", async function () {
    const event = await events.getEventByRange(0, 0)
    const balanceBuyerBefore = await getBalance(buyer)
    const balanceCreatorBefore = await getBalance(creator)
    const balanceEscrowBefore = await getBalance(event[0].escrow)
    const balancePlatformBefore = await getBalance(platformWallet)
    const ticketType = 1
    const tokenUsed = 1
    const amount = 1
    const tickets = new web3.eth.Contract(ticketsABI.abi, event[0].tickets)
    const ticketInfo = await tickets.methods.getTicketByType(ticketType).call();
    const ticketPrice = ticketInfo.prices[tokenUsed]
    const fee = ticketPrice * platformFee / 10000
    const receipt = await platform.buyTicket(buyer, 0, ticketType, tokenUsed, amount, {value: toBN(ticketPrice).add(toBN(fee)).toString(), from: buyer})
    const tx = await web3.eth.getTransaction(receipt.tx);
    const gasSpent = receipt.receipt.gasUsed * tx.gasPrice
    expect((await tickets.methods.balanceOf(buyer, 0).call()).toString()).to.be.equal(amount.toString())
    expect((await getBalance(buyer)).toString()).to.be.equal(
      toBN(balanceBuyerBefore).sub(toBN(ticketPrice)).sub(toBN(gasSpent)).sub(toBN(fee)).toString()
    )
    expect((await getBalance(creator)).toString()).to.be.equal(balanceCreatorBefore.toString())
    expect((await getBalance(event[0].escrow)).toString()).to.be.equal(toBN(balanceEscrowBefore).add(toBN(ticketPrice)).toString())
    expect((await getBalance(platformWallet)).toString()).to.be.equal(toBN(balancePlatformBefore).add(toBN(fee)).toString())
  });  

  it("Should Use Ticket", async function () {
    const eventId = 0
    const ticketType = 0
    const message =  getUseTicketParams(events.address, eventId, ticketType)
    const sig = await web3.eth.accounts.sign(Web3.utils.utf8ToHex(message), "bab2f3ac7487e6f3fe900d47b356be09ab9b416d32ef12d08912fb7353d0f7e6")
    await platform.useTicket(message, sig.v, sig.r, sig.s, {from: creator})
    expect((await events.ticketsUsed(eventId, ticketType, buyer)).toString()).to.be.equal('1')
  });

  it("Should Not Use Ticket Again", async function () {
    const eventId = 0
    const ticketType = 0
    const message =  getUseTicketParams(events.address, eventId, ticketType)
    const sig = await web3.eth.accounts.sign(Web3.utils.utf8ToHex(message), "bab2f3ac7487e6f3fe900d47b356be09ab9b416d32ef12d08912fb7353d0f7e6")
    await truffleAssert.fails(platform.useTicket(message, sig.v, sig.r, sig.s, {from: creator}))
  });  

  it("Should Not Withdraw More Than 50% Of Escrow With Stable", async function () {
    const event = await events.getEventByRange(0, 0)
    const escrow = new web3.eth.Contract(escrowABI.abi, event[0].escrow)
    await truffleAssert.fails(escrow.methods.withdrawStable(100).send({from: creator}))
  });

  it("Should Not Withdraw More Than 50% Of Escrow With Native", async function () {
    const event = await events.getEventByRange(0, 0)
    const escrow = new web3.eth.Contract(escrowABI.abi, event[0].escrow)
    await truffleAssert.fails(escrow.methods.withdrawNative(20000).send({from: creator}))
  });

  it("Should Withdraw 50% Of Escrow With Stable", async function () {
    const amount = 50
    const event = await events.getEventByRange(0, 0)
    const balanceCreatorBefore = await tokenStable.balanceOf(creator)
    const balanceEscrowBefore = await tokenStable.balanceOf(event[0].escrow)
    const escrow = new web3.eth.Contract(escrowABI.abi, event[0].escrow)
    await escrow.methods.withdrawStable(amount).send({from: creator, gas: 110000})
    expect((await tokenStable.balanceOf(creator)).toString()).to.be.equal(balanceCreatorBefore.add(toBN(amount)).toString()) 
    expect((await tokenStable.balanceOf(event[0].escrow)).toString()).to.be.equal(balanceEscrowBefore.sub(toBN(amount)).toString())
  });  

  it("Should Withdraw 50% Of Escrow With Native", async function () {
    const amount = 1000
    const event = await events.getEventByRange(0, 0)
    const balanceCreatorBefore = await getBalance(creator)
    const balanceEscrowBefore = await getBalance(event[0].escrow)

    const escrow = new web3.eth.Contract(escrowABI.abi, event[0].escrow)
    const receipt = await escrow.methods.withdrawNative(amount).send({from: creator})
    const tx = await web3.eth.getTransaction(receipt.transactionHash);
    const gasSpent = receipt.gasUsed * tx.gasPrice
    expect((await getBalance(creator)).toString()).to.be.equal(toBN(balanceCreatorBefore).add(toBN(amount)).sub(toBN(gasSpent)).toString()) 
    expect((await getBalance(event[0].escrow)).toString()).to.be.equal(toBN(balanceEscrowBefore).sub(toBN(amount)).toString())
  });

  it("Should Withdraw The Rest Of Escrow With Stable When Event Is Finished", async function () {
    await time.increase(3600)

    const amount = 50
    const event = await events.getEventByRange(0, 0)
    const balanceCreatorBefore = await tokenStable.balanceOf(creator)
    const balanceEscrowBefore = await tokenStable.balanceOf(event[0].escrow)

    const escrow = new web3.eth.Contract(escrowABI.abi, event[0].escrow)
    await escrow.methods.withdrawStable(amount).send({from: creator})
    expect((await tokenStable.balanceOf(creator)).toString()).to.be.equal(balanceCreatorBefore.add(toBN(amount)).toString()) 
    expect((await tokenStable.balanceOf(event[0].escrow)).toString()).to.be.equal(balanceEscrowBefore.sub(toBN(amount)).toString())
  });

  it("Should Withdraw The Rest Of Escrow With Native When Event Is Finished", async function () {
    const amount = 1000
    const event = await events.getEventByRange(0, 0)
    const balanceCreatorBefore = await getBalance(creator)
    const balanceEscrowBefore = await getBalance(event[0].escrow)

    const escrow = new web3.eth.Contract(escrowABI.abi, event[0].escrow)
    const receipt = await escrow.methods.withdrawNative(amount).send({from: creator})
    const tx = await web3.eth.getTransaction(receipt.transactionHash);
    const gasSpent = receipt.gasUsed * tx.gasPrice

    expect((await getBalance(creator)).toString()).to.be.equal(toBN(balanceCreatorBefore).add(toBN(amount)).sub(toBN(gasSpent)).toString()) 
    expect((await getBalance(event[0].escrow)).toString()).to.be.equal(toBN(balanceEscrowBefore).sub(toBN(amount)).toString())
  });

  it("Should Cancel Event And Return Founds When Event Is Cancelled", async function () {
    await platform.createEvent({
      creator,
      eventMetadataUri: "ipfs://eventMetadata", 
      NFTMetadataUri: "ipfs://NFTMetadata", 
      ticketsMetadataUris: ["ipfs://TicketMetadata1","ipfs://TicketMetadata2"], 
      ticketsNFTMetadataUris: ["ipfs://TicketNFTMetadata1","ipfs://TicketNFTMetadata2"], 
      prices: [100,1000, 200,2000], 
      maxSupplies: [100, 200], 
      deadline: Math.floor(new Date().getTime() / 1000) + 10000000,
      percentageWithdraw: 5000
    }, {from: creator})

    const event = await events.getEventByRange(1, 1)
    const eventId = 1
    
    const ticketType = 0
    const tokenUsedStable = 0
    const amount = 2
    const ticketPriceStable = 200

    await tokenStable.approve(event[0].escrow, Web3.utils.toWei("1000000"), {from: buyer})
    await platform.buyTicket(buyer, eventId, ticketType, tokenUsedStable, amount, {from: buyer})

    const ticketType2 = 1
    const tokenUsedNative = 1
    const ticketPriceNative = 4000
    const fee = ticketPriceNative * platformFee / 10000
    await platform.buyTicket(buyer, eventId, ticketType2, tokenUsedNative, amount, {value: ticketPriceNative + fee, from: buyer})

    await platform.cancelEvent(eventId, {from: creator}) 
    const eventCancelled = await events.getEventByRange(1, 1)
    expect(eventCancelled[0].cancelled).to.be.equal(true)

    const balanceStableBuyerBefore = await tokenStable.balanceOf(buyer)
    const balanceStableEscrowBefore = await tokenStable.balanceOf(event[0].escrow)
    const balanceNativeBuyerBefore = await getBalance(buyer)
    const balanceNativeEscrowBefore = await getBalance(event[0].escrow)

    const escrow = new web3.eth.Contract(escrowABI.abi, event[0].escrow)
    const receipt = await escrow.methods.returnFunds().send({from: buyer})
    const tx = await web3.eth.getTransaction(receipt.transactionHash);
    const gasSpent = receipt.gasUsed * tx.gasPrice

    expect((await tokenStable.balanceOf(buyer)).toString()).to.be.equal(balanceStableBuyerBefore.add(toBN(ticketPriceStable)).toString())
    expect((await tokenStable.balanceOf(event[0].escrow)).toString()).to.be.equal(balanceStableEscrowBefore.sub(toBN(ticketPriceStable)).toString())
    expect((await getBalance(buyer)).toString()).to.be.equal(toBN(balanceNativeBuyerBefore).add(toBN(ticketPriceNative)).sub(toBN(gasSpent)).toString())
    expect((await getBalance(event[0].escrow)).toString()).to.be.equal(toBN(balanceNativeEscrowBefore).sub(toBN(ticketPriceNative)).toString())
  });  

})
