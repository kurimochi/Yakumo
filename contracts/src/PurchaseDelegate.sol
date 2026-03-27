// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {YakumoStore} from "./Yakumo.sol";

contract PurchaseDelegate {
    error ArrayLengthMismatch();

    // --- EIP-7702 Delegate ---

    function executePurchase(YakumoStore store, uint256[] calldata ids, uint256[] calldata amounts) external {
        if (ids.length != amounts.length) {
            revert ArrayLengthMismatch();
        }
        uint256 total = 0;
        for (uint256 i = 0; i < ids.length;) {
            uint256 id = ids[i];
            (,,, uint256 price) = store.works(id);
            total += price * amounts[i];
            unchecked {
                ++i;
            }
        }
        store.purchase{value: total}(ids, amounts);
    }
}
