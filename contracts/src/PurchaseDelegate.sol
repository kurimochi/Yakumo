// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {YakumoStore} from "./Yakumo.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract PurchaseDelegate {
    using SafeERC20 for IERC20;

    // --- EIP-7702 Delegate ---

    function executePurchaseWithEth(YakumoStore store, uint256 id, uint256 amount) external {
        uint256 total = store.getTotalPrice(id, amount);

        store.purchaseWithEth{value: total}(id, amount);
    }

    function executePurchaseWithErc20(YakumoStore store, uint256 id, uint256 amount) external {
        (,,,, address tokenContract) = store.works(id);
        if (tokenContract == address(0)) {
            revert YakumoStore.InvalidTokenContract();
        }
        uint256 total = store.getTotalPrice(id, amount);

        IERC20(tokenContract).safeIncreaseAllowance(address(store), total);

        store.purchaseWithErc20(id, amount);
    }
}
