// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Rejector {
    receive() external payable {
        revert();
    }
}
