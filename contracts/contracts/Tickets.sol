// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import "./PlatformGated.sol";
import "./interfaces/ITickets.sol";

/// @title Smart Contract for BiTicket Tickets
/// @author Eduardo Mannarino
contract Tickets is ITickets, ERC1155Supply, PlatformGated {
  error InvalidLength();
  error InvalidTicketType();
  error MaxSupplyExceeded();
  error AddressZero();

  event TicketsMinted(address to, uint256 ticketType, uint256 amount);

  uint256 public totalTicketsType;
  mapping(uint256 id => TicketInfo info) public ticketsType;

  constructor(
    string[] memory ticketMetadataUris, 
    string[] memory NFTMetadataUris,
    uint256[] memory prices, 
    uint256[] memory maxSupplies, 
    address platform) 
      ERC1155("") PlatformGated(platform) {
    if (
      ticketMetadataUris.length != NFTMetadataUris.length ||
      ticketMetadataUris.length * 2 != prices.length || 
      prices.length != maxSupplies.length * 2
    )
      revert InvalidLength();
    for (uint256 i = 0; i <= ticketMetadataUris.length - 1; i++) {
      uint256[2] memory prices_;
      prices_[0] = prices[2 * i];
      prices_[1] = prices[2 * i + 1];
      ticketsType[i] = TicketInfo(ticketMetadataUris[i], NFTMetadataUris[i], prices_, maxSupplies[i]); 
    }
    totalTicketsType = ticketMetadataUris.length;
  }

  /// @notice Mint Tickets NFT
  /// @param to address of the user
  /// @param ticketType Type of the ticket to buy
  /// @param amount amount of tickets to buy
  function mint(address to, uint256 ticketType, uint256 amount) public onlyPlatform {
    if (to == address(0))
      revert AddressZero();
    if (ticketType > totalTicketsType)
      revert InvalidTicketType();
    TicketInfo memory info = ticketsType[ticketType];
    if (totalSupply(ticketType) + amount > info.maxSupply)
      revert MaxSupplyExceeded();    
    _mint(to, ticketType, amount, "");
    emit TicketsMinted(to, ticketType, amount);
  }

  /// @notice Get info of a ticket type
  /// @param ticketType Type of the ticket 
  function getTicketByType(uint256 ticketType) public view returns (TicketInfo memory) {
    return ticketsType[ticketType];
  }

  /// @notice Get total supply (tickets sold) for a ticket type
  /// @param ticketType Type of the ticket 
  function getTotalSupply(uint256 ticketType) public view returns (uint256) {
    return totalSupply(ticketType);
  } 

  /// @notice Get NFT uri for a ticket type
  /// @param ticketType Type of the ticket 
  function uri(uint256 ticketType) public view virtual override returns (string memory) {
    if (ticketType > totalTicketsType)
      revert InvalidTicketType();
    TicketInfo memory ticketTypeInfo = ticketsType[ticketType];
    return ticketTypeInfo.NFTMetadataUri;
  }
}