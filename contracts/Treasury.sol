// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

contract Treasury is Ownable {
    constructor() Ownable(msg.sender) {}
}
