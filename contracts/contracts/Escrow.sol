// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./interfaces/IEscrow.sol";
import "./interfaces/IEvents.sol";
import "./PlatformGated.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Smart Contract for BiTicket Escrow
/// @author Eduardo Mannarino
/// @notice One Escrow contract for Event
contract Escrow is IEscrow, PlatformGated {
  error InvalidAddress();
  error InvalidPercentage(uint32 percentageWithdraw);
  error NotSeller();
  error CannotSendFunds();
  error EventCancelled();
  error EventNotCancelled();
  error EventNotFinished();
  error MaximumWithdrawalExcedeed();

  event NewDepositStable(address user, uint256 amount);
  event NewDepositNative(address user, uint256 amount);
  event NewWithdrawStable(uint256 amount);
  event NewWithdrawNative(uint256 amount);
  event FundsReturned(address user);

  mapping (address buyer => uint256[2] amount) public balances;
  uint256 public totalStable;
  uint256 public totalNative;
  uint256 public withdrawnStable;
  uint256 public withdrawnNative;
  uint256 public immutable eventId;
  IEvents public immutable eventsContract;
  address public immutable seller;
  uint16 public immutable percentageWithdraw; // Two decimal places (20% = 2000)
  IERC20 public immutable tokenStable;

  constructor(
    uint256 _eventId, 
    address _eventsContract, 
    address _seller, 
    uint16 _percentageWithdraw,
    address _tokenStable,
    address platform
  ) PlatformGated(platform) payable  {
    if (_eventsContract == address(0) || _seller == address(0) )
      revert InvalidAddress();
    if (_percentageWithdraw > 10000)
      revert InvalidPercentage(_percentageWithdraw);
    
    eventId = _eventId;
    eventsContract = IEvents(_eventsContract);
    seller = _seller;      
    percentageWithdraw = _percentageWithdraw;
    tokenStable = IERC20(_tokenStable);
  }

  /// @notice Deposit into the escrow using Token 0 (Token Stable)
  /// @param user Address of user that buys.
  /// @param amount Amount of Token to Deposit
  /// @param user Address of payer
  /// @dev Payer must differ user to supports Cross Chain buys.
    function depositStable(address user, uint256 amount, address payer) public onlyPlatform {
    if (!tokenStable.transferFrom(payer, address(this), amount))
      revert CannotSendFunds();
    balances[user][0] += amount;
    totalStable += amount;
    emit NewDepositStable(user, amount);
  }

  /// @notice Deposit into the escrow using Token 2 (Token Native)
  /// @param user Address of user that buys.
  function depositNative(address user) public payable onlyPlatform {
    balances[user][1] += msg.value;
    totalNative += msg.value;
    emit NewDepositNative(user, msg.value);
  }

  /// @notice Allows Seller to Withdraw Token Stable following the rules
  /// @param amount Amount of Token to Deposit
  function withdrawStable(uint256 amount) external {
    checkWithdraw(amount, 0);
    withdrawnStable += amount;
    if (!tokenStable.transfer(seller, amount))
      revert CannotSendFunds();
    emit NewWithdrawStable(amount);
  }

  /// @notice Allows Seller to Withdraw Token Native following the rules
  /// @param amount Amount of Token to Deposit
  function withdrawNative(uint256 amount) external {
    checkWithdraw(amount, 1);
    withdrawnNative += amount;
    (bool sent, ) = seller.call{value: amount}("");
    if (!sent)
      revert CannotSendFunds();
    emit NewWithdrawNative(amount);
  }

  /// @notice Allows buyers to withdraw tokens if event is cancelled
  function returnFunds() external {
    Event[] memory event_ = eventsContract.getEventByRange(eventId, eventId);
    if (!event_[0].cancelled)
      revert EventNotCancelled();

    uint256 balance = balances[msg.sender][0];
    if (balance > 0)
      tokenStable.transfer(msg.sender, balance);

    balance = balances[msg.sender][1];
    if (balance > 0) {
      (bool sent, ) = msg.sender.call{value: balance}("");
      if (!sent)
        revert CannotSendFunds();      
    }

    emit FundsReturned(msg.sender);
  }

  function checkWithdraw(uint256 amount, uint8 tokenUsed) internal view {
    if (msg.sender != seller)
      revert NotSeller();
    Event[] memory event_ = eventsContract.getEventByRange(eventId, eventId);
    uint16 _percentageWithdraw = percentageWithdraw;
    if (block.timestamp > event_[0].deadline)
      _percentageWithdraw = 10000;

    uint256 balance;
    uint256 total;
    uint256 withdrawn;
    if (tokenUsed == 0) {
      balance = tokenStable.balanceOf(address(this));
      withdrawn = withdrawnStable;
      total = totalStable;
    }
    if (tokenUsed == 1) {
      balance = address(this).balance;
      withdrawn = withdrawnNative;
      total = totalNative;
    }

    if (amount + withdrawn > total * _percentageWithdraw / 10000)  
      revert MaximumWithdrawalExcedeed();
      
    if (event_[0].cancelled)
      revert EventCancelled();
  }
}