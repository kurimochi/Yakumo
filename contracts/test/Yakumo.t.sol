// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";
import {stdError} from "forge-std/StdError.sol";
import {YakumoStore} from "../src/Yakumo.sol";
import {Rejector} from "./Rejector.sol";
import {ReentrancyAttaker} from "./Reentrance.sol";
import {TestERC20Token, FalseERC20Token, TestERC3009Token} from "./Tokens.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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
        vm.store(address(store), bytes32(uint256(structSlot) + 4), bytes32(uint256(uint160(tokenContract))));

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

    function _setEditionsBalance(address account, uint256 id, uint256 amount) internal {
        stdstore.target(address(store)).sig("balanceOf(address,uint256)").with_key(account).with_key(id)
            .checked_write(amount);
    }

    function testRegisterWork() public {
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

    function testRegisterWorkWithErc20() public {
        address creator = makeAddr("1");
        string memory metadataUri = "hogehoge";
        bool transferable = false;
        uint256 price = 1 ether;

        address tokenContract = address(new TestERC20Token());

        vm.prank(creator);
        store.registerWork(metadataUri, transferable, price, tokenContract);
    }

    function testRegisterWorkWithEoa() public {
        address creator = makeAddr("1");
        string memory metadataUri = "hogehoge";
        bool transferable = false;
        uint256 price = 1 ether;

        address tokenContract = makeAddr("2");

        vm.prank(creator);
        uint256 id = store.registerWork(metadataUri, transferable, price, tokenContract);

        (,,,, address workTokenContract) = store.works(id);
        assertEq(workTokenContract, tokenContract);
    }

    function testRegisterWorkWithInvalidContract() public {
        address creator = makeAddr("1");
        string memory metadataUri = "hogehoge";
        bool transferable = false;
        uint256 price = 1 ether;

        address tokenContract = address(new Rejector());

        vm.prank(creator);
        uint256 id = store.registerWork(metadataUri, transferable, price, tokenContract);

        (,,,, address workTokenContract) = store.works(id);
        assertEq(workTokenContract, tokenContract);
    }

    function testRegisterWorkIdCounterOverflow() public {
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

    function testChangePrice() public {
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
        emit YakumoStore.PriceChanged(id, previousPrice, newPrice, tokenContract);

        vm.prank(creator);
        store.changePrice(id, newPrice, tokenContract);

        (,,, uint256 price, address workTokenContract) = store.works(id);
        assertEq(price, newPrice);
        assertEq(workTokenContract, tokenContract);
    }

    function testChangePriceFromErc20() public {
        address creator = makeAddr("1");
        string memory metadataUri = "hogehoge";
        bool transferable = false;
        uint256 price = 1 ether;

        address previousTokenContract = address(new TestERC20Token());
        address newTokenContract = address(0);

        uint256 id = 0;
        _setWork(id, creator, metadataUri, transferable, price, previousTokenContract);
        _setIdCounter(1);

        vm.expectEmit(true, false, false, true);
        emit YakumoStore.PriceChanged(id, price, price, newTokenContract);

        vm.prank(creator);
        store.changePrice(id, price, newTokenContract);

        (,,,, address workTokenContract) = store.works(id);
        assertEq(workTokenContract, newTokenContract);
    }

    function testChangePriceWithEoa() public {
        address creator = makeAddr("1");
        string memory metadataUri = "hogehoge";
        bool transferable = false;
        uint256 price = 1 ether;

        address previousTokenContract = address(0);
        address newTokenContract = makeAddr("2");

        uint256 id = 0;
        _setWork(id, creator, metadataUri, transferable, price, previousTokenContract);
        _setIdCounter(1);

        vm.prank(creator);
        store.changePrice(id, price, newTokenContract);

        (,,,, address workTokenContract) = store.works(id);
        assertEq(workTokenContract, newTokenContract);
    }

    function testChangePriceWithInvalidContract() public {
        address creator = makeAddr("1");
        string memory metadataUri = "hogehoge";
        bool transferable = false;
        uint256 price = 1 ether;

        address previousTokenContract = address(0);
        address newTokenContract = address(new Rejector());

        uint256 id = 0;
        _setWork(id, creator, metadataUri, transferable, price, previousTokenContract);
        _setIdCounter(1);

        vm.prank(creator);
        store.changePrice(id, price, newTokenContract);

        (,,,, address workTokenContract) = store.works(id);
        assertEq(workTokenContract, newTokenContract);
    }

    function testChangePriceNotCreator() public {
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
        store.changePrice(id, newPrice, tokenContract);
    }

    function testChangePriceInvalidWorkId() public {
        address creator = makeAddr("1");
        uint256 id = 0;

        vm.prank(creator);
        vm.expectRevert(YakumoStore.InvalidWorkId.selector);
        store.changePrice(id, 1 ether, address(0));
    }

    function testPurchaseWithEth() public {
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
        emit YakumoStore.Purchased(buyer, id, amount);

        vm.prank(buyer);
        store.purchaseWithEth{value: total}(id, amount);

        assertEq(store.balanceOf(buyer, id), amount);
        assertEq(store.pendingWithdrawals(creator), total);
    }

    function testPurchaseWithEthInvalidTokenContract() public {
        address creator = makeAddr("1");
        address buyer = makeAddr("2");
        string memory metadataUri = "hogehoge";
        bool transferable = false;
        uint256 price = 1 ether;
        address tokenContract = address(new TestERC20Token());

        uint256 id = 0;
        _setWork(id, creator, metadataUri, transferable, price, tokenContract);
        _setIdCounter(1);

        uint256 amount = 2;
        uint256 total = price * amount;

        vm.deal(buyer, total);

        vm.prank(buyer);
        vm.expectRevert(YakumoStore.InvalidTokenContract.selector);

        store.purchaseWithEth{value: total}(id, amount);
    }

    function testPurchaseWithEthInvalidWorkId() public {
        address buyer = makeAddr("1");

        uint256 id = 0;
        uint256 amount = 2;

        vm.prank(buyer);
        vm.expectRevert(YakumoStore.InvalidWorkId.selector);

        store.purchaseWithEth(id, amount);
    }

    function testPurchaseWithEthIncorrectPaymentLess() public {
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

        store.purchaseWithEth(id, amount);
    }

    function testPurchaseWithEthIncorrectPaymentGreater() public {
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

        store.purchaseWithEth{value: total}(id, amount);
    }

    function testPurchaseWithErc20() public {
        address creator = makeAddr("1");
        address buyer = makeAddr("2");
        string memory metadataUri = "hogehoge";
        bool transferable = false;
        uint256 price = 1 ether;

        address tokenContract = address(new TestERC20Token());

        uint256 id = 0;
        _setWork(id, creator, metadataUri, transferable, price, tokenContract);
        _setIdCounter(1);

        uint256 amount = 2;
        uint256 total = price * amount;

        TestERC20Token(tokenContract).mint(buyer, total);

        vm.startPrank(buyer);
        IERC20(tokenContract).approve(address(store), total);

        vm.expectEmit(true, true, false, true);
        emit YakumoStore.Purchased(buyer, id, amount);

        store.purchaseWithErc20(id, amount);
        vm.stopPrank();

        assertEq(store.balanceOf(buyer, id), amount);
        assertEq(IERC20(tokenContract).balanceOf(buyer), 0);
        assertEq(IERC20(tokenContract).balanceOf(creator), total);
    }

    function testPurchaseWithErc20InvalidTokenContract() public {
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
        vm.expectRevert(YakumoStore.InvalidTokenContract.selector);

        store.purchaseWithErc20(id, amount);
    }

    function testPurchaseWithErc20InvalidWorkId() public {
        address buyer = makeAddr("1");

        uint256 id = 0;
        uint256 amount = 2;

        vm.prank(buyer);
        vm.expectRevert(YakumoStore.InvalidWorkId.selector);

        store.purchaseWithErc20(id, amount);
    }

    function testPurchaseWithErc20IncorrectPayment() public {
        address creator = makeAddr("1");
        address buyer = makeAddr("2");
        string memory metadataUri = "hogehoge";
        bool transferable = false;
        uint256 price = 1 ether;

        address tokenContract = address(new TestERC20Token());

        uint256 id = 0;
        _setWork(id, creator, metadataUri, transferable, price, tokenContract);
        _setIdCounter(1);

        uint256 amount = 2;
        uint256 total = price * amount;

        TestERC20Token(tokenContract).mint(buyer, total - 1);

        vm.prank(buyer);
        vm.expectRevert();

        store.purchaseWithErc20(id, amount);
    }

    function testPurchaseWithErc20TransferFailed() public {
        address creator = makeAddr("1");
        address buyer = makeAddr("2");
        string memory metadataUri = "hogehoge";
        bool transferable = false;
        uint256 price = 1 ether;

        address tokenContract = address(new FalseERC20Token());

        uint256 id = 0;
        _setWork(id, creator, metadataUri, transferable, price, tokenContract);
        _setIdCounter(1);

        uint256 amount = 2;
        uint256 total = price * amount;

        FalseERC20Token(tokenContract).mint(buyer, total);

        vm.prank(buyer);
        vm.expectRevert();

        store.purchaseWithErc20(id, amount);
    }

    function testPurchaseWithAuthorization() public {
        address creator = makeAddr("1");
        (address buyer, uint256 buyerPrivateKey) = makeAddrAndKey("2");
        string memory metadataUri = "hogehoge";
        bool transferable = false;
        uint256 price = 1 ether;

        address tokenContract = address(new TestERC3009Token());

        uint256 id = 0;
        _setWork(id, creator, metadataUri, transferable, price, tokenContract);
        _setIdCounter(1);

        uint256 amount = 2;
        uint256 total = price * amount;

        TestERC3009Token(tokenContract).mint(buyer, total);

        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1000;
        bytes32 nonce = keccak256("nonce");
        bytes32 structHash = keccak256(
            abi.encode(
                TestERC3009Token(tokenContract).TRANSFER_WITH_AUTHORIZATION_TYPEHASH(),
                buyer,
                creator,
                total,
                validAfter,
                validBefore,
                nonce
            )
        );
        bytes32 digest = TestERC3009Token(tokenContract).hashTypedDataV4(structHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(buyerPrivateKey, digest);

        vm.expectEmit(true, true, false, true);
        emit YakumoStore.Purchased(buyer, id, amount);

        vm.prank(creator);
        store.purchaseWithAuthorization(buyer, id, amount, validAfter, validBefore, nonce, v, r, s);

        assertEq(store.balanceOf(buyer, id), amount);
        assertEq(IERC20(tokenContract).balanceOf(buyer), 0);
        assertEq(IERC20(tokenContract).balanceOf(creator), total);
    }

    function testPurchaseWithAuthorizationInvalidWorkId() public {
        address buyer = makeAddr("1");

        uint256 id = 0;
        uint256 amount = 2;
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1000;
        bytes32 nonce = keccak256("nonce");
        uint8 v = 0;
        bytes32 r = bytes32(0);
        bytes32 s = bytes32(0);

        vm.prank(buyer);
        vm.expectRevert(YakumoStore.InvalidWorkId.selector);

        store.purchaseWithAuthorization(buyer, id, amount, validAfter, validBefore, nonce, v, r, s);
    }

    function testPurchaseWithAuthorizationInvalidTokenContractWithErc20() public {
        address creator = makeAddr("1");
        address buyer = makeAddr("2");
        string memory metadataUri = "hogehoge";
        bool transferable = false;
        uint256 price = 1 ether;

        address tokenContract = address(new TestERC20Token());

        uint256 id = 0;
        _setWork(id, creator, metadataUri, transferable, price, tokenContract);
        _setIdCounter(1);

        uint256 amount = 2;
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1000;
        bytes32 nonce = keccak256("nonce");
        uint8 v = 0;
        bytes32 r = bytes32(0);
        bytes32 s = bytes32(0);

        vm.prank(buyer);
        vm.expectRevert();

        store.purchaseWithAuthorization(buyer, id, amount, validAfter, validBefore, nonce, v, r, s);
    }

    function testWithdraw() public {
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

    function testWithdrawNoPendingWithdrawal() public {
        address account = makeAddr("1");

        vm.prank(account);
        vm.expectRevert(YakumoStore.NoPendingWithdrawal.selector);

        store.withdraw();
    }

    function testWithdrawWithdrawalFailed() public {
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

    function testWithdrawReentrancy() public {
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

    function testTransferWithTransferable() public {
        address creator = makeAddr("1");
        address buyer = makeAddr("2");
        address receiver = makeAddr("3");
        string memory metadataUri = "hogehoge";
        bool transferable = true;
        uint256 price = 1 ether;
        address tokenContract = address(0);

        _setWork(0, creator, metadataUri, transferable, price, tokenContract);
        _setIdCounter(1);
        _setEditionsBalance(buyer, 0, 1);

        vm.prank(buyer);

        bool result = store.transfer(receiver, 0, 1);
        assertTrue(result);

        assertEq(store.balanceOf(buyer, 0), 0);
        assertEq(store.balanceOf(receiver, 0), 1);
    }

    function testTransferWithUntransferable() public {
        address creator = makeAddr("1");
        address buyer = makeAddr("2");
        address receiver = makeAddr("3");
        string memory metadataUri = "hogehoge";
        bool transferable = false;
        uint256 price = 1 ether;
        address tokenContract = address(0);

        _setWork(0, creator, metadataUri, transferable, price, tokenContract);
        _setIdCounter(1);
        _setEditionsBalance(buyer, 0, 1);

        vm.prank(buyer);
        vm.expectRevert(YakumoStore.NonTransferable.selector);

        store.transfer(receiver, 0, 1);
    }

    function testTransferInvalidWorkId() public {
        address buyer = makeAddr("1");
        address receiver = makeAddr("2");

        vm.prank(buyer);
        vm.expectRevert(YakumoStore.InvalidWorkId.selector);
        store.transfer(receiver, 0, 1);
    }

    function testTransferFromWithTransferable() public {
        address creator = makeAddr("1");
        address owner = makeAddr("2");
        address spender = makeAddr("3");
        address receiver = makeAddr("4");
        string memory metadataUri = "hogehoge";
        bool transferable = true;
        uint256 price = 1 ether;
        address tokenContract = address(0);

        _setWork(0, creator, metadataUri, transferable, price, tokenContract);
        _setIdCounter(1);
        _setEditionsBalance(owner, 0, 2);

        vm.prank(owner);
        store.approve(spender, 0, 1);

        vm.prank(spender);

        bool result = store.transferFrom(owner, receiver, 0, 1);
        assertTrue(result);

        assertEq(store.balanceOf(owner, 0), 1);
        assertEq(store.balanceOf(receiver, 0), 1);
    }

    function testTransferFromWithUntransferable() public {
        address creator = makeAddr("1");
        address owner = makeAddr("2");
        address spender = makeAddr("3");
        address receiver = makeAddr("4");
        string memory metadataUri = "hogehoge";
        bool transferable = false;
        uint256 price = 1 ether;
        address tokenContract = address(0);

        _setWork(0, creator, metadataUri, transferable, price, tokenContract);
        _setIdCounter(1);
        _setEditionsBalance(owner, 0, 1);

        vm.prank(owner);
        store.approve(spender, 0, 1);

        vm.prank(spender);
        vm.expectRevert(YakumoStore.NonTransferable.selector);

        store.transferFrom(owner, receiver, 0, 1);
    }

    function testTransferFromInvalidWorkId() public {
        address owner = makeAddr("1");
        address spender = makeAddr("2");
        address receiver = makeAddr("3");

        vm.prank(spender);
        vm.expectRevert(YakumoStore.InvalidWorkId.selector);
        store.transferFrom(owner, receiver, 0, 1);
    }

    function testGetTotalPrice() public {
        address creator = makeAddr("1");
        string memory metadataUri = "hogehoge";
        bool transferable = false;
        uint256 price = 3 ether;
        address tokenContract = address(0);

        _setWork(0, creator, metadataUri, transferable, price, tokenContract);
        _setIdCounter(1);

        uint256 amount = 4;
        uint256 total = store.getTotalPrice(0, amount);

        assertEq(total, price * amount);
    }

    function testGetTotalPriceInvalidWorkId() public {
        uint256 id = 0;
        uint256 amount = 4;

        vm.expectRevert(YakumoStore.InvalidWorkId.selector);
        store.getTotalPrice(id, amount);
    }
}
