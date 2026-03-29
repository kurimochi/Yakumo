// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";
import {stdError} from "forge-std/StdError.sol";
import {YakumoStore} from "../src/Yakumo.sol";
import {Rejector} from "./Rejector.sol";
import {ReentrancyAttaker} from "./Reentrance.sol";
import {TestERC20Token} from "./Tokens.sol";

contract YakumoStoreTest is Test {
    using stdStorage for StdStorage;

    YakumoStore store;

    function setUp() public {
        store = new YakumoStore();
    }

    function _setIdCounter(uint256 value) internal {
        stdstore.target(address(store)).sig("idCounter()").checked_write(value);
    }

    function _setWork(
        uint256 id,
        address creator,
        string memory metadataUri,
        bool transferable,
        uint256 price,
        address tokenContract
    ) internal {
        bytes32 structSlot = keccak256(abi.encode(id, uint256(4)));
        bytes32 metadataUriSlot = bytes32(uint256(structSlot) + 1);

        vm.store(address(store), structSlot, bytes32(uint256(uint160(creator))));
        vm.store(address(store), bytes32(uint256(structSlot) + 2), bytes32(transferable ? uint256(1) : uint256(0)));
        vm.store(address(store), bytes32(uint256(structSlot) + 3), bytes32(price));
        vm.store(address(store), bytes32(uint256(structSlot) + 5), bytes32(uint256(uint160(tokenContract))));

        bytes memory metadataUriBytes = bytes(metadataUri);
        if (metadataUriBytes.length <= 31) {
            bytes32 dataWord;
            assembly {
                dataWord := mload(add(metadataUriBytes, 32))
            }
            uint256 encoded = (uint256(dataWord) & ~uint256(0xff)) | (metadataUriBytes.length * 2);
            vm.store(address(store), metadataUriSlot, bytes32(encoded));
        } else {
            vm.store(address(store), metadataUriSlot, bytes32(uint256(metadataUriBytes.length) * 2 + 1));
            bytes32 dataSlot = keccak256(abi.encode(metadataUriSlot));
            for (uint256 i = 0; i < (metadataUriBytes.length + 31) / 32; i++) {
                bytes32 chunk;
                assembly {
                    chunk := mload(add(add(metadataUriBytes, 32), mul(i, 32)))
                }
                vm.store(address(store), bytes32(uint256(dataSlot) + i), chunk);
            }
        }
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
        string memory metadataUri = "hogehoge";
        bool transferable = false;
        uint256 price = 1 ether;
        address tokenContract = address(0);

        vm.prank(creator);
        vm.expectEmit(true, true, false, false);
        emit YakumoStore.WorkRegistered(0, creator);

        uint256 id = store.registerWork(metadataUri, transferable, price, tokenContract);

        assertEq(id, 0);
        (
            address workCreator,
            string memory workMetadataUri,
            bool workTransferable,
            uint256 workPrice,
            address workTokenContract
        ) = store.works(0);
        assertEq(workCreator, creator);
        assertEq(workMetadataUri, metadataUri);
        assertEq(workTransferable, transferable);
        assertEq(workPrice, price);
        assertEq(workTokenContract, tokenContract);

        assertEq(store.idCounter(), 1);
    }

    function test_RegisterWorkWithERC20() public {
        address creator = makeAddr("1");
        string memory metadataUri = "hogehoge";
        bool transferable = false;
        uint256 price = 1 ether;

        address tokenContract = address(new TestERC20Token());

        vm.prank(creator);
        store.registerWork(metadataUri, transferable, price, tokenContract);
    }

    function test_RegisterWorkWithEOA() public {
        address creator = makeAddr("1");
        string memory metadataUri = "hogehoge";
        bool transferable = false;
        uint256 price = 1 ether;

        address tokenContract = makeAddr("2");

        vm.prank(creator);
        vm.expectRevert(YakumoStore.InvalidTokenContract.selector);
        store.registerWork(metadataUri, transferable, price, tokenContract);
    }

    function test_RegisterWorkWithInvalidContract() public {
        address creator = makeAddr("1");
        string memory metadataUri = "hogehoge";
        bool transferable = false;
        uint256 price = 1 ether;

        address tokenContract = address(new Rejector());

        vm.prank(creator);
        vm.expectRevert(YakumoStore.InvalidTokenContract.selector);
        store.registerWork(metadataUri, transferable, price, tokenContract);
    }

    function test_RegisterWorkIdCounterOverflow() public {
        stdstore.target(address(store)).sig("idCounter()").checked_write(UINT256_MAX);

        address creator = makeAddr("1");
        string memory metadataUri = "hogehoge";
        bool transferable = false;
        uint256 price = 1 ether;
        address tokenContract = address(0);

        vm.prank(creator);
        vm.expectRevert(stdError.arithmeticError);

        store.registerWork(metadataUri, transferable, price, tokenContract);
    }

    function test_SetPrice() public {
        address creator = makeAddr("1");
        string memory metadataUri = "hogehoge";
        bool transferable = false;
        address tokenContract = address(0);

        uint256 previousPrice = 1 ether;
        uint256 newPrice = 2 ether;

        uint256 id = 0;
        _setWork(id, creator, metadataUri, transferable, previousPrice, tokenContract);
        _setIdCounter(1);

        vm.expectEmit(true, false, false, true);
        emit YakumoStore.PriceChanged(id, previousPrice, newPrice);

        vm.prank(creator);
        store.changePrice(id, newPrice);

        (,,, uint256 price,) = store.works(id);
        assertEq(price, newPrice);
    }

    function test_SetPriceNotCreator() public {
        address creator = makeAddr("1");
        address attacker = makeAddr("2");
        string memory metadataUri = "hogehoge";
        bool transferable = false;
        address tokenContract = address(0);

        uint256 previousPrice = 1 ether;
        uint256 newPrice = 2 ether;

        uint256 id = 0;
        _setWork(id, creator, metadataUri, transferable, previousPrice, tokenContract);
        _setIdCounter(1);

        vm.prank(attacker);
        vm.expectRevert(YakumoStore.NotCreator.selector);
        store.changePrice(id, newPrice);
    }

    function test_Puchase() public {
        address creator = makeAddr("1");
        address buyer = makeAddr("2");
        string memory metadataUri = "hogehoge";
        bool transferable = false;
        uint256 price = 1 ether;
        address tokenContract = address(0);

        uint256 id = 0;
        _setWork(id, creator, metadataUri, transferable, price, tokenContract);
        _setIdCounter(1);

        uint256 amount = 2;
        uint256 total = price * amount;

        vm.deal(buyer, total);

        vm.expectEmit(true, true, false, true);
        emit YakumoStore.EditionMinted(id, buyer, amount);
        vm.expectEmit(true, true, false, true);
        emit YakumoStore.Purchased(buyer, id, amount);

        vm.prank(buyer);
        store.purchase{value: total}(id, amount);

        assertEq(store.balanceOf(buyer, id), amount);
        assertEq(store.pendingWithdrawals(creator), total);
    }

    function test_PurchaseInvalidWorkId() public {
        address buyer = makeAddr("1");

        uint256 id = 0;
        uint256 amount = 2;

        vm.prank(buyer);
        vm.expectRevert(YakumoStore.InvalidWorkId.selector);

        store.purchase(id, amount);
    }

    function test_PurchaseIncorrectPaymentLess() public {
        address creator = makeAddr("1");
        address buyer = makeAddr("2");
        string memory metadataUri = "hogehoge";
        bool transferable = false;
        uint256 price = 1 ether;
        address tokenContract = address(0);

        uint256 id = 0;
        _setWork(id, creator, metadataUri, transferable, price, tokenContract);
        _setIdCounter(1);

        uint256 amount = 2;

        vm.prank(buyer);
        vm.expectRevert(YakumoStore.IncorrectPayment.selector);

        store.purchase(id, amount);
    }

    function test_PurchaseIncorrectPaymentGreater() public {
        address creator = makeAddr("1");
        address buyer = makeAddr("2");
        string memory metadataUri = "hogehoge";
        bool transferable = false;
        uint256 price = 1 ether;
        address tokenContract = address(0);

        uint256 id = 0;
        _setWork(id, creator, metadataUri, transferable, price, tokenContract);
        _setIdCounter(1);

        uint256 amount = 2;
        uint256 total = price * amount + 1;
        vm.deal(buyer, total);

        vm.prank(buyer);
        vm.expectRevert(YakumoStore.IncorrectPayment.selector);

        store.purchase{value: total}(id, amount);
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
        string memory metadataUri = "hogehoge";
        bool transferable = true;
        uint256 price = 1 ether;
        address tokenContract = address(0);

        _setWork(0, creator, metadataUri, transferable, price, tokenContract);
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
        string memory metadataUri = "hogehoge";
        bool transferable = false;
        uint256 price = 1 ether;
        address tokenContract = address(0);

        _setWork(0, creator, metadataUri, transferable, price, tokenContract);
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
        string memory metadataUri = "hogehoge";
        bool transferable = true;
        uint256 price = 1 ether;
        address tokenContract = address(0);

        _setWork(0, creator, metadataUri, transferable, price, tokenContract);
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
        string memory metadataUri = "hogehoge";
        bool transferable = false;
        uint256 price = 1 ether;
        address tokenContract = address(0);

        _setWork(0, creator, metadataUri, transferable, price, tokenContract);
        _setBalance(owner, 0, 1);

        vm.prank(owner);
        store.approve(spender, 0, 1);

        vm.prank(spender);
        vm.expectRevert(YakumoStore.NonTransferable.selector);

        store.transferFrom(owner, receiver, 0, 1);
    }
}
