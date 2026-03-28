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

        vm.prank(sponsor);
        id = store.registerWork(metadataUri, transferable, price);

        (delegator, secretKey) = makeAddrAndKey("2");
    }

    function test_PurchaseDelegate() public {
        vm.signAndAttachDelegation(address(delegate), secretKey);

        uint256[] memory ids = new uint256[](1);
        ids[0] = id;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1;

        vm.txGasPrice(1);
        vm.deal(sponsor, 10 ether);
        vm.deal(delegator, price);

        uint256 sponsorBalanceBefore = sponsor.balance;
        uint256 delegatorBalanceBefore = delegator.balance;

        vm.prank(sponsor);
        PurchaseDelegate(payable(delegator)).executePurchase(store, ids, amounts);

        assertEq(delegator.balance, delegatorBalanceBefore - price);
        assertLe(sponsor.balance, sponsorBalanceBefore);
        assertLt(sponsorBalanceBefore - sponsor.balance, price);
    }

    function test_PurchaseDelegateHaveNoEth() public {
        vm.signAndAttachDelegation(address(delegate), secretKey);

        uint256[] memory ids = new uint256[](1);
        ids[0] = id;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1;

        vm.prank(sponsor);
        vm.expectRevert();
        PurchaseDelegate(payable(delegator)).executePurchase(store, ids, amounts);
    }

    function test_PurchaseDelegateArrayLengthMismatch() public {
        vm.signAndAttachDelegation(address(delegate), secretKey);

        uint256[] memory ids = new uint256[](1);
        ids[0] = id;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1;
        amounts[1] = 2;

        vm.deal(delegator, price);

        vm.prank(sponsor);
        vm.expectRevert(PurchaseDelegate.ArrayLengthMismatch.selector);
        PurchaseDelegate(payable(delegator)).executePurchase(store, ids, amounts);
    }
}
