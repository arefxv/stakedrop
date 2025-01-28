// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Ownable} from "@openzeppelin-contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin-contracts/token/ERC20/ERC20.sol";

contract StakeDropToken is ERC20, Ownable {
    constructor() ERC20("Stake Drop Token", "SDT") Ownable(msg.sender) {}

    function mint(address to, uint256 value) external onlyOwner {
        _mint(to, value);
    }
}
