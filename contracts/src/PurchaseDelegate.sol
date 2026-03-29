// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {YakumoStore} from "./Yakumo.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract PurchaseDelegate {
    // --- EIP-7702 Delegate ---

    function executePurchaseWithEth(YakumoStore store, uint256 id, uint256 amount) external {
        (,,, uint256 price,) = store.works(id);
        uint256 total = price * amount;

        store.purchaseWithEth{value: total}(id, amount);
    }

    function executePurchaseWithErc20(YakumoStore store, uint256 id, uint256 amount) external {
        (,,, uint256 price, address tokenContract) = store.works(id);
        uint256 total = price * amount;

        IERC20(tokenContract).approve(address(store), total);

        store.purchaseWithErc20(id, amount);
    }
}
