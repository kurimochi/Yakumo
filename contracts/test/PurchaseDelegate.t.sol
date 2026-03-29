// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {YakumoStore} from "../src/Yakumo.sol";
import {PurchaseDelegate} from "../src/PurchaseDelegate.sol";
import {TestERC20Token} from "./Tokens.sol";

contract PurchaseDelegateTest is Test {
    YakumoStore store;
    PurchaseDelegate delegate;

    address delegator;
    uint256 secretKey;
    address sponsor;

    function setUp() public {
        store = new YakumoStore();
        delegate = new PurchaseDelegate();

        sponsor = makeAddr("1");
        (delegator, secretKey) = makeAddrAndKey("2");
    }

    function testExecutePurchaseWithEth() public {
        string memory metadataUri = "hogehoge";
        bool transferable = false;
        uint256 price = 1 ether;
        address tokenContract = address(0);
        uint256 id = store.registerWork(metadataUri, transferable, price, tokenContract);

        vm.signAndAttachDelegation(address(delegate), secretKey);

        vm.txGasPrice(1);
        vm.deal(sponsor, 10 ether);
        vm.deal(delegator, price);

        uint256 sponsorBalanceBefore = sponsor.balance;
        uint256 delegatorBalanceBefore = delegator.balance;

        vm.prank(sponsor);
        PurchaseDelegate(payable(delegator)).executePurchaseWithEth(store, id, 1);

        assertEq(delegator.balance, delegatorBalanceBefore - price);
        assertLe(sponsor.balance, sponsorBalanceBefore);
        assertLt(sponsorBalanceBefore - sponsor.balance, price);
    }

    function testExecutePurchaseWithEthHaveNoEth() public {
        string memory metadataUri = "hogehoge";
        bool transferable = false;
        uint256 price = 1 ether;
        address tokenContract = address(0);

        vm.prank(sponsor);
        uint256 id = store.registerWork(metadataUri, transferable, price, tokenContract);

        vm.signAndAttachDelegation(address(delegate), secretKey);

        vm.prank(sponsor);
        vm.expectRevert();
        PurchaseDelegate(payable(delegator)).executePurchaseWithEth(store, id, 1);
    }

    function testExecutePurchaseWithErc20() public {
        string memory metadataUri = "hogehoge";
        bool transferable = false;
        uint256 price = 1 ether;

        TestERC20Token token = new TestERC20Token();
        token.mint(delegator, price);

        address tokenContract = address(token);
        vm.prank(sponsor);
        uint256 id = store.registerWork(metadataUri, transferable, price, tokenContract);

        vm.signAndAttachDelegation(address(delegate), secretKey);

        vm.txGasPrice(1);
        vm.deal(sponsor, 10 ether);

        vm.prank(sponsor);
        PurchaseDelegate(delegator).executePurchaseWithErc20(store, id, 1);

        assertEq(token.balanceOf(delegator), 0);
        assertEq(token.balanceOf(sponsor), price);
        assertLe(sponsor.balance, 10 ether);
    }
}
