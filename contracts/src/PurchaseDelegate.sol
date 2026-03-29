// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {YakumoStore} from "./Yakumo.sol";

contract PurchaseDelegate {
    // --- EIP-7702 Delegate ---

    function executePurchase(YakumoStore store, uint256 id, uint256 amount) external {
        (,,, uint256 price) = store.works(id);
        uint256 total = price * amount;

        store.purchase{value: total}(id, amount);
    }
}
