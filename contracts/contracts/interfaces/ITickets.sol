// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

struct TicketInfo {
  string ticketMetadataUri;
  string NFTMetadataUri;
  uint256[2] prices; // 0-Stable 1-Native
  uint256 maxSupply;
}

interface ITickets {
  function mint(address to, uint256 ticketType, uint256 amount) external;
  function getTicketByType(uint256 ticketType) external view returns (TicketInfo memory);
  function getTotalSupply(uint256 id) external view returns (uint256);
}