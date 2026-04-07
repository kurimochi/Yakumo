// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC6909} from "@openzeppelin/contracts/token/ERC6909/ERC6909.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC3009} from "./IERC3009.sol";

contract YakumoStore is ERC6909 {
    using SafeERC20 for IERC20;

    struct Work {
        address creator;
        string metadataUri;
        bool transferable;
        uint256 price;
        address tokenContract;
    }

    uint256 public idCounter = 0;
    mapping(uint256 => Work) public works;
    mapping(address => uint256) public pendingWithdrawals;

    event WorkRegistered(uint256 indexed id, address indexed creator);
    event PriceChanged(uint256 indexed id, uint256 previousPrice, uint256 newPrice, address newTokenContract);
    event Purchased(address indexed buyer, uint256 indexed id, uint256 amount);
    event Withdrawn(address indexed creator, uint256 amount);

    error NotCreator();
    error InvalidWorkId();
    error IncorrectPayment();
    error NoPendingWithdrawal();
    error WithdrawalFailed();
    error NonTransferable();
    error InvalidTokenContract();

    modifier requireValidWorkId(uint256 id) {
        if (id >= idCounter) {
            revert InvalidWorkId();
        }
        _;
    }

    function _getTotalPrice(Work storage work, uint256 amount) internal view returns (uint256) {
        return work.price * amount;
    }

    function getTotalPrice(uint256 id, uint256 amount) external view requireValidWorkId(id) returns (uint256) {
        return _getTotalPrice(works[id], amount);
    }

    function registerWork(string calldata metadataUri, bool transferable, uint256 price, address tokenContract)
        external
        returns (uint256)
    {
        works[idCounter] = Work({
            creator: msg.sender,
            metadataUri: metadataUri,
            transferable: transferable,
            price: price,
            tokenContract: tokenContract
        });
        emit WorkRegistered(idCounter, msg.sender);

        idCounter++;
        return idCounter - 1;
    }

    function changePrice(uint256 id, uint256 newPrice, address newTokenContract) external requireValidWorkId(id) {
        Work storage work = works[id];

        if (msg.sender != work.creator) {
            revert NotCreator();
        }

        uint256 previousPrice = work.price;
        work.price = newPrice;
        work.tokenContract = newTokenContract;

        emit PriceChanged(id, previousPrice, newPrice, newTokenContract);
    }

    function purchaseWithEth(uint256 id, uint256 amount) external payable requireValidWorkId(id) {
        Work storage work = works[id];

        if (work.tokenContract != address(0)) {
            revert InvalidTokenContract();
        }

        uint256 total = _getTotalPrice(work, amount);
        if (msg.value != total) {
            revert IncorrectPayment();
        }

        _mint(msg.sender, id, amount);

        address creator = work.creator;
        pendingWithdrawals[creator] += total;
        emit Purchased(msg.sender, id, amount);
    }

    function purchaseWithErc20(uint256 id, uint256 amount) external requireValidWorkId(id) {
        Work storage work = works[id];

        address tokenContract = work.tokenContract;
        if (tokenContract == address(0)) {
            revert InvalidTokenContract();
        }

        uint256 total = _getTotalPrice(work, amount);
        IERC20(tokenContract).safeTransferFrom(msg.sender, work.creator, total);

        _mint(msg.sender, id, amount);

        emit Purchased(msg.sender, id, amount);
    }

    function purchaseWithAuthorization(
        address buyer,
        uint256 id,
        uint256 amount,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external requireValidWorkId(id) {
        Work storage work = works[id];

        address tokenContract = work.tokenContract;
        if (tokenContract.code.length == 0) {
            revert InvalidTokenContract();
        }
        uint256 total = _getTotalPrice(work, amount);
        IERC3009(tokenContract)
            .transferWithAuthorization(buyer, work.creator, total, validAfter, validBefore, nonce, v, r, s);

        _mint(buyer, id, amount);

        emit Purchased(buyer, id, amount);
    }

    function withdraw() external {
        uint256 amount = pendingWithdrawals[msg.sender];
        if (amount == 0) {
            revert NoPendingWithdrawal();
        }
        emit Withdrawn(msg.sender, amount);

        pendingWithdrawals[msg.sender] = 0;
        (bool sent,) = payable(msg.sender).call{value: amount}("");
        if (!sent) {
            revert WithdrawalFailed();
        }
    }

    modifier requireTransferable(uint256 id) {
        if (!works[id].transferable) {
            revert NonTransferable();
        }
        _;
    }

    function transfer(address receiver, uint256 id, uint256 amount)
        public
        virtual
        override
        requireValidWorkId(id)
        requireTransferable(id)
        returns (bool)
    {
        return super.transfer(receiver, id, amount);
    }

    function transferFrom(address sender, address receiver, uint256 id, uint256 amount)
        public
        virtual
        override
        requireValidWorkId(id)
        requireTransferable(id)
        returns (bool)
    {
        return super.transferFrom(sender, receiver, id, amount);
    }
}
