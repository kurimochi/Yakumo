// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {YakumoStore} from "../src/Yakumo.sol";
import {PurchaseDelegate} from "../src/PurchaseDelegate.sol";

contract PurchaseDelegateTest is Test {
    YakumoStore store;
    PurchaseDelegate delegate;

    uint256 price = 1 ether;
    address delegator;
    uint256 secretKey;
    address sponsor;
    uint256 id;

    function setUp() public {
        store = new YakumoStore();
        delegate = new PurchaseDelegate();

        sponsor = makeAddr("1");
        string memory metadataUri = "hogehoge";
        bool transferable = false;
        address tokenContract = address(0);

        vm.prank(sponsor);
        id = store.registerWork(metadataUri, transferable, price, tokenContract);

        (delegator, secretKey) = makeAddrAndKey("2");
    }

    function testPurchaseDelegate() public {
        vm.signAndAttachDelegation(address(delegate), secretKey);

        vm.txGasPrice(1);
        vm.deal(sponsor, 10 ether);
        vm.deal(delegator, price);

        uint256 sponsorBalanceBefore = sponsor.balance;
        uint256 delegatorBalanceBefore = delegator.balance;

        vm.prank(sponsor);
        PurchaseDelegate(payable(delegator)).executePurchase(store, id, 1);

        assertEq(delegator.balance, delegatorBalanceBefore - price);
        assertLe(sponsor.balance, sponsorBalanceBefore);
        assertLt(sponsorBalanceBefore - sponsor.balance, price);
    }

    function testPurchaseDelegateHaveNoEth() public {
        vm.signAndAttachDelegation(address(delegate), secretKey);

        vm.prank(sponsor);
        vm.expectRevert();
        PurchaseDelegate(payable(delegator)).executePurchase(store, id, 1);
    }
}
