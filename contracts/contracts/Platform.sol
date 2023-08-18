// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IEscrow.sol";
import "./interfaces/IEvents.sol";
import "./interfaces/ITickets.sol";
import "./interfaces/IUsers.sol";

/// @title Smart Contract for BiTicket Platform
/// @author Eduardo Mannarino
/// @notice This is the entrypoint for interacting with the others SC
contract Platform is Ownable {
  error AddressZero();
  error ErrorGettingEvent();
  error InvalidLength();
  error EventCancelled();
  error EmptyMetadata();
  error NotUser();
  error CannotSendFunds();
  error IncorrectSentFunds();
  error NotCreator();
  error EventDeadlineReached(uint256, uint256);
  error MaxSupplyExceeded();
  error TokenNotSupported();
  error InvalidFee();
  error PlatformWalletNotSet();
  error InvalidAmount();

  event TicketBought(address indexed user, uint256 indexed eventId, uint256 indexed ticketType);

  IEvents public eventsContract;
  IUsers public usersContract;
  address public platformWallet;
  uint16 public platformFee; // Two decimal places (10% = 1000)
  IERC20 public immutable tokenStable; 

  constructor(address tokenStable_) payable {
    tokenStable = IERC20(tokenStable_);
    tokenStable.approve(address(this), 2**256 - 1);
  }

  /// @notice Creates an Event 
  /// @param createEventParams Set of Events Configuration
  function createEvent(CreateEventParams memory createEventParams) external onlyUser(msg.sender) {
    if (
      createEventParams.ticketsMetadataUris.length * 2 != createEventParams.prices.length  || 
      createEventParams.prices.length != createEventParams.maxSupplies.length * 2
    )
      revert InvalidLength();    
    uint256 eventId = eventsContract.createEvent(
      CreateEventParams(
        createEventParams.creator, 
        createEventParams.eventMetadataUri, 
        createEventParams.NFTMetadataUri, 
        createEventParams.ticketsMetadataUris, 
        createEventParams.ticketsNFTMetadataUris, 
        createEventParams.prices, 
        createEventParams.maxSupplies, 
        createEventParams.deadline,
        createEventParams.percentageWithdraw
      ),
      address(tokenStable),
      platformFee
    );
    Event[] memory event_ = eventsContract.getEventByRange(eventId, eventId);
    tokenStable.approve(event_[0].escrow, 2**256 - 1);
  } 

  /// @notice Buy Tickets
  /// @param user address of the user who will receive the ticket
  /// @param eventId Id of the Event
  /// @param ticketType Ticket Type to be bought
  /// @param tokenUsed Token used to pay (0: TokenStable - 1: Token Native)
  /// @param amount Amount of tickets to buy
  function buyTicket(
    address user, 
    uint256 eventId, 
    uint256 ticketType, 
    uint256 tokenUsed, 
    uint256 amount
  ) external payable onlyUser(user) {
    _buyTicket(user, eventId, ticketType, tokenUsed, amount, user);
  }

  /// @notice Internal function to buy
  /// @param user address of the user who will receive the ticket
  /// @param eventId Id of the Event
  /// @param ticketType Ticket Type to be bought
  /// @param tokenUsed Token used to pay (0: TokenStable - 1: Token Native)
  /// @param amount Amount of tickets to buy
  /// @param payer address of the payer
  function _buyTicket(
    address user, 
    uint256 eventId, 
    uint256 ticketType, 
    uint256 tokenUsed, 
    uint256 amount,
    address payer
  ) internal {
    if (user == address(0))
      revert AddressZero();
    if (amount == 0)
      revert InvalidAmount();
    Event[] memory event_ = eventsContract.getEventByRange(eventId, eventId);
    if (event_[0].cancelled)
      revert EventCancelled();
    if (block.timestamp >= event_[0].deadline)
      revert EventDeadlineReached(block.timestamp, event_[0].deadline);

    ITickets ticketsContract = ITickets(event_[0].tickets);
    TicketInfo memory ticketInfo = ticketsContract.getTicketByType(ticketType);

    if (ticketsContract.getTotalSupply(ticketType) + amount > ticketInfo.maxSupply) 
      revert MaxSupplyExceeded();
    
    if (event_[0].platformFee != 0 && platformWallet == address(0))
      revert PlatformWalletNotSet();

    if (tokenUsed == 0) { // Stable
      uint256 price = ticketInfo.prices[0];
      if (price == 0)
        revert TokenNotSupported();
      uint256 fee = price * amount * event_[0].platformFee / 10000;
      if (fee > 0)
        tokenStable.transferFrom(payer, platformWallet, fee);
      IEscrow(event_[0].escrow).depositStable(user, price * amount, payer);  
    } 

    if (tokenUsed == 1) { // Native
      uint256 price = ticketInfo.prices[1];
      if (price == 0)
        revert TokenNotSupported();
      uint256 fee = price * amount * event_[0].platformFee / 10000;
      if (msg.value != (price * amount) + fee)
        revert IncorrectSentFunds();
      if (fee > 0) {
        (bool sent, ) = platformWallet.call{value: fee}("");
        if (!sent)
          revert CannotSendFunds();      
      }
      IEscrow(event_[0].escrow).depositNative{value: msg.value - fee}(user); 
    }
    ticketsContract.mint(user, ticketType, amount);
    emit TicketBought(user, eventId, ticketType);
  }

  /// @notice Allows creator to use tickets and mark it as used
  /// @param message Message with the necessary information (address of contract, eventId, tokenType, nonce)
  /// @param v Component v of the signature
  /// @param r Component r of the signature
  /// @param s Component s of the signature
  function useTicket(bytes calldata message, uint8 v, bytes32 r, bytes32 s) external onlyUser(msg.sender) {
    eventsContract.useTicket(message, v, r, s);         
  }

  /// @notice Allows user to register or update the data
  /// @param metadataUri Link to Metadata of the info
  function upsertUser(string memory metadataUri) public {
    if (bytes(metadataUri).length == 0)
      revert EmptyMetadata();   
    usersContract.upsertUser(msg.sender, metadataUri); 
  }

  /// @notice Allows creator to cancel an event
  /// @param eventId Id of the Event to be cancelled
  function cancelEvent(uint256 eventId) external onlyUser(msg.sender) {
    Event[] memory event_ = eventsContract.getEventByRange(eventId, eventId);
    if (msg.sender != event_[0].creator)
      revert NotCreator();
    eventsContract.cancelEvent(eventId);
  } 

  /// @notice Set the Events Contract
  /// @param _eventsContract Address of the Events Contract
  function setEventsContract(address _eventsContract) external onlyOwner {
    if (_eventsContract == address(0))
      revert AddressZero();
    eventsContract = IEvents(address(_eventsContract));
  }

  /// @notice Set the Users Contract
  /// @param _usersContract Address of the Users Contract
  function setUsersContract(address _usersContract) external onlyOwner {
    if (_usersContract == address(0))
      revert AddressZero();
    usersContract = IUsers(address(_usersContract));
  }

  /// @notice Set the Platform Fee
  /// @param _platformFee Platform fee (Two decimals places: 10% = 1000)
  function setPlatformFee(uint16 _platformFee) external onlyOwner {
    if (platformFee >= 3000)
      revert InvalidFee();
    platformFee = _platformFee;
  }

  /// @notice Set the Platform Wallet
  /// @param _platformWallet Platform Wallet that recollects fees
  function setPlatformWallet(address _platformWallet) external onlyOwner {
    if (_platformWallet == address(0))
      revert AddressZero();
    platformWallet = _platformWallet;
  }

  /// @notice Modifier to check only user interactions
  modifier onlyUser(address user) {
      _checkIsUser(user);
      _;
  }

  /// @notice Function to check Valid Users
  /// @param user address of the user to check
  function _checkIsUser(address user) private view {
    if (bytes(usersContract.users(user)).length == 0) 
      revert NotUser();
  }
}