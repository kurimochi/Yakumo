// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";
import {stdError} from "forge-std/StdError.sol";
import {YakumoStore} from "../src/Yakumo.sol";
import {Rejector} from "./Rejector.sol";
import {ReentrancyAttaker} from "./Reentrance.sol";

contract YakumoStoreTest is Test {
    using stdStorage for StdStorage;

    YakumoStore store;

    function setUp() public {
        store = new YakumoStore();
    }

    function _setIdCounter(uint256 value) internal {
        stdstore.target(address(store)).sig("idCounter()").checked_write(value);
    }

    function _setWork(uint256 id, address creator, bytes32 metadataUri, bool transferable, uint256 price) internal {
        stdstore.target(address(store)).sig("works(uint256)").with_key(id).depth(0)
            .checked_write(uint256(uint160(creator)));
        stdstore.target(address(store)).sig("works(uint256)").with_key(id).depth(1).checked_write(uint256(metadataUri));
        stdstore.target(address(store)).sig("works(uint256)").with_key(id).depth(2).checked_write(transferable ? 1 : 0);
        stdstore.target(address(store)).sig("works(uint256)").with_key(id).depth(3).checked_write(price);
    }

    function _setPendingWithdrawal(address account, uint256 amount) internal {
        stdstore.target(address(store)).sig("pendingWithdrawals(address)").with_key(account).checked_write(amount);
    }

    function _setBalance(address account, uint256 id, uint256 amount) internal {
        stdstore.target(address(store)).sig("balanceOf(address,uint256)").with_key(account).with_key(id)
            .checked_write(amount);
    }

    function test_RegisterWork() public {
        address creator = makeAddr("1");
        bytes32 metadataUri = 0x686f6765686f6765000000000000000000000000000000000000000000000000;
        bool transferable = false;
        uint256 price = 1 ether;

        vm.prank(creator);
        vm.expectEmit(true, true, false, false);
        emit YakumoStore.WorkRegistered(0, creator);

        uint256 id = store.registerWork(metadataUri, transferable, price);

        assertEq(id, 0);
        (address workCreator, bytes32 workMetadataUri, bool workTransferable, uint256 workPrice) = store.works(0);
        assertEq(workCreator, creator);
        assertEq(workMetadataUri, metadataUri);
        assertEq(workTransferable, transferable);
        assertEq(workPrice, price);

        assertEq(store.idCounter(), 1);
    }

    function test_RegisterWorkIdCounterOverflow() public {
        stdstore.target(address(store)).sig("idCounter()").checked_write(UINT256_MAX);

        address creator = makeAddr("1");
        bytes32 metadataUri = 0x686f6765686f6765000000000000000000000000000000000000000000000000;
        bool transferable = false;
        uint256 price = 1 ether;

        vm.prank(creator);
        vm.expectRevert(stdError.arithmeticError);

        store.registerWork(metadataUri, transferable, price);
    }

    function test_SetPrice() public {
        address creator = makeAddr("1");
        bytes32 metadataUri = 0x686f6765686f6765000000000000000000000000000000000000000000000000;
        bool transferable = false;

        uint256 previousPrice = 1 ether;
        uint256 newPrice = 2 ether;

        uint256 id = 0;
        _setWork(id, creator, metadataUri, transferable, previousPrice);
        _setIdCounter(1);

        vm.expectEmit(true, false, false, true);
        emit YakumoStore.PriceChanged(id, previousPrice, newPrice);

        vm.prank(creator);
        store.changePrice(id, newPrice);

        (,,, uint256 price) = store.works(id);
        assertEq(price, newPrice);
    }

    function test_SetPriceNotCreator() public {
        address creator = makeAddr("1");
        address attacker = makeAddr("2");
        bytes32 metadataUri = 0x686f6765686f6765000000000000000000000000000000000000000000000000;
        bool transferable = false;

        uint256 previousPrice = 1 ether;
        uint256 newPrice = 2 ether;

        uint256 id = 0;
        _setWork(id, creator, metadataUri, transferable, previousPrice);
        _setIdCounter(1);

        vm.prank(attacker);
        vm.expectRevert(YakumoStore.NotCreator.selector);
        store.changePrice(id, newPrice);
    }

    function test_Puchase() public {
        address creator = makeAddr("1");
        address buyer = makeAddr("2");
        bytes32 metadataUri = 0x686f6765686f6765000000000000000000000000000000000000000000000000;
        bool transferable = false;
        uint256 price = 1 ether;

        uint256 id = 0;
        _setWork(id, creator, metadataUri, transferable, price);
        _setIdCounter(1);

        uint256 amount = 2;
        uint256 total = price * amount;

        vm.deal(buyer, total);

        vm.expectEmit(true, true, false, true);
        emit YakumoStore.EditionMinted(id, buyer, amount);
        vm.expectEmit(true, true, false, true);
        emit YakumoStore.Purchased(buyer, id, amount);

        vm.prank(buyer);
        uint256[] memory ids = new uint256[](1);
        ids[0] = id;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        store.purchase{value: total}(ids, amounts);

        assertEq(store.balanceOf(buyer, id), amount);
        assertEq(store.pendingWithdrawals(creator), total);
    }

    function test_PuchaseMultiple() public {
        address creator1 = makeAddr("1");
        address creator2 = makeAddr("2");
        address buyer = makeAddr("3");

        bytes32 metadataUri1 = 0x686f6765686f6765000000000000000000000000000000000000000000000000;
        bool transferable1 = false;
        uint256 price1 = 1 ether;

        uint256 id1 = 0;
        _setWork(id1, creator1, metadataUri1, transferable1, price1);

        bytes32 metadataUri2 = 0x6675676166756761000000000000000000000000000000000000000000000000;
        bool transferable2 = false;
        uint256 price2 = 2 ether;

        uint256 id2 = 1;
        _setWork(id2, creator2, metadataUri2, transferable2, price2);
        _setIdCounter(2);

        uint256 amount1 = 2;
        uint256 total1 = price1 * amount1;

        uint256 amount2 = 3;
        uint256 total2 = price2 * amount2;

        uint256 total = total1 + total2;
        vm.deal(buyer, total);

        vm.expectEmit(true, true, false, true);
        emit YakumoStore.EditionMinted(id1, buyer, amount1);
        vm.expectEmit(true, true, false, true);
        emit YakumoStore.Purchased(buyer, id1, amount1);

        vm.expectEmit(true, true, false, true);
        emit YakumoStore.EditionMinted(id2, buyer, amount2);
        vm.expectEmit(true, true, false, true);
        emit YakumoStore.Purchased(buyer, id2, amount2);

        vm.prank(buyer);
        uint256[] memory ids = new uint256[](2);
        ids[0] = id1;
        ids[1] = id2;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amount1;
        amounts[1] = amount2;
        store.purchase{value: total}(ids, amounts);

        assertEq(store.balanceOf(buyer, id1), amount1);
        assertEq(store.pendingWithdrawals(creator1), total1);
        assertEq(store.balanceOf(buyer, id2), amount2);
        assertEq(store.pendingWithdrawals(creator2), total2);
    }

    function test_PurchaseArrayLengthMismatch() public {
        address buyer = makeAddr("1");

        uint256[] memory ids = new uint256[](2);
        ids[0] = 0;
        ids[1] = 1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 2;

        vm.prank(buyer);
        vm.expectRevert(YakumoStore.ArrayLengthMismatch.selector);

        store.purchase(ids, amounts);
    }

    function test_PurchaseInvalidWorkId() public {
        address buyer = makeAddr("1");

        uint256[] memory ids = new uint256[](1);
        ids[0] = 0;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 2;

        vm.prank(buyer);
        vm.expectRevert(YakumoStore.InvalidWorkId.selector);

        store.purchase(ids, amounts);
    }

    function test_PurchaseIncorrectPaymentLess() public {
        address creator = makeAddr("1");
        address buyer = makeAddr("2");
        bytes32 metadataUri = 0x686f6765686f6765000000000000000000000000000000000000000000000000;
        bool transferable = false;
        uint256 price = 1 ether;

        uint256 id = 0;
        _setWork(id, creator, metadataUri, transferable, price);
        _setIdCounter(1);

        uint256 amount = 2;

        uint256[] memory ids = new uint256[](1);
        ids[0] = id;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        vm.prank(buyer);
        vm.expectRevert(YakumoStore.IncorrectPayment.selector);

        store.purchase(ids, amounts);
    }

    function test_PurchaseIncorrectPaymentGreater() public {
        address creator = makeAddr("1");
        address buyer = makeAddr("2");
        bytes32 metadataUri = 0x686f6765686f6765000000000000000000000000000000000000000000000000;
        bool transferable = false;
        uint256 price = 1 ether;

        uint256 id = 0;
        _setWork(id, creator, metadataUri, transferable, price);
        _setIdCounter(1);

        uint256 amount = 2;
        uint256 total = price * amount + 1;
        vm.deal(buyer, total);

        uint256[] memory ids = new uint256[](1);
        ids[0] = id;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        vm.prank(buyer);
        vm.expectRevert(YakumoStore.IncorrectPayment.selector);

        store.purchase{value: total}(ids, amounts);
    }

    function test_Withdraw() public {
        address creator = makeAddr("1");
        uint256 price = 1 ether;

        uint256 amount = 2;
        uint256 total = price * amount;
        _setPendingWithdrawal(creator, total);
        vm.deal(address(store), total);

        vm.prank(creator);
        vm.expectEmit(true, false, false, true);
        emit YakumoStore.Withdrawn(creator, total);

        store.withdraw();

        assertEq(creator.balance, total);
        assertEq(store.pendingWithdrawals(creator), 0);
    }

    function test_WithdrawNoPendingWithdrawal() public {
        address account = makeAddr("1");

        vm.prank(account);
        vm.expectRevert(YakumoStore.NoPendingWithdrawal.selector);

        store.withdraw();
    }

    function test_WithdrawWithdrawalFailed() public {
        address rejector = address(new Rejector());
        uint256 price = 1 ether;

        uint256 amount = 2;
        uint256 total = price * amount;
        _setPendingWithdrawal(rejector, total);
        vm.deal(address(store), total);

        vm.prank(rejector);
        vm.expectRevert(YakumoStore.WithdrawalFailed.selector);

        store.withdraw();
    }

    function test_WithdrawReentrancy() public {
        address creator = makeAddr("1");
        uint256 price = 1 ether;

        uint256 amount = 2;
        uint256 total = price * amount;

        ReentrancyAttaker attackerContract = new ReentrancyAttaker(address(store));
        _setPendingWithdrawal(creator, total);
        _setPendingWithdrawal(address(attackerContract), attackerContract.AMOUNT());
        vm.deal(address(store), total + attackerContract.AMOUNT());
        address attacker = makeAddr("3");
        vm.deal(attacker, attackerContract.AMOUNT());

        vm.prank(attacker);
        attackerContract.attack{value: attackerContract.AMOUNT()}();

        assertEq(address(store).balance, total);
        assertEq(store.pendingWithdrawals(creator), total);
    }

    function test_transferWithTransferable() public {
        address creator = makeAddr("1");
        address buyer = makeAddr("2");
        address receiver = makeAddr("3");
        bytes32 metadataUri = 0x686f6765686f6765000000000000000000000000000000000000000000000000;
        bool transferable = true;
        uint256 price = 1 ether;

        _setWork(0, creator, metadataUri, transferable, price);
        _setBalance(buyer, 0, 1);

        vm.prank(buyer);
        vm.expectEmit(true, true, true, true);
        emit YakumoStore.EditionTransferred(0, buyer, receiver, 1);

        bool result = store.transfer(receiver, 0, 1);
        assertTrue(result);

        assertEq(store.balanceOf(buyer, 0), 0);
        assertEq(store.balanceOf(receiver, 0), 1);
    }

    function test_transferWithUntransferable() public {
        address creator = makeAddr("1");
        address buyer = makeAddr("2");
        address receiver = makeAddr("3");
        bytes32 metadataUri = 0x686f6765686f6765000000000000000000000000000000000000000000000000;
        bool transferable = false;
        uint256 price = 1 ether;

        _setWork(0, creator, metadataUri, transferable, price);
        _setBalance(buyer, 0, 1);

        vm.prank(buyer);
        vm.expectRevert(YakumoStore.NonTransferable.selector);

        store.transfer(receiver, 0, 1);
    }

    function test_transferFromWithTransferable() public {
        address creator = makeAddr("1");
        address owner = makeAddr("2");
        address spender = makeAddr("3");
        address receiver = makeAddr("4");
        bytes32 metadataUri = 0x686f6765686f6765000000000000000000000000000000000000000000000000;
        bool transferable = true;
        uint256 price = 1 ether;

        _setWork(0, creator, metadataUri, transferable, price);
        _setBalance(owner, 0, 2);

        vm.prank(owner);
        store.approve(spender, 0, 1);

        vm.prank(spender);
        vm.expectEmit(true, true, true, true);
        emit YakumoStore.EditionTransferred(0, owner, receiver, 1);

        bool result = store.transferFrom(owner, receiver, 0, 1);
        assertTrue(result);

        assertEq(store.balanceOf(owner, 0), 1);
        assertEq(store.balanceOf(receiver, 0), 1);
    }

    function test_transferFromWithUntransferable() public {
        address creator = makeAddr("1");
        address owner = makeAddr("2");
        address spender = makeAddr("3");
        address receiver = makeAddr("4");
        bytes32 metadataUri = 0x686f6765686f6765000000000000000000000000000000000000000000000000;
        bool transferable = false;
        uint256 price = 1 ether;

        _setWork(0, creator, metadataUri, transferable, price);
        _setBalance(owner, 0, 1);

        vm.prank(owner);
        store.approve(spender, 0, 1);

        vm.prank(spender);
        vm.expectRevert(YakumoStore.NonTransferable.selector);

        store.transferFrom(owner, receiver, 0, 1);
    }
}
