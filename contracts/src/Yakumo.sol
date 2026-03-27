// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC6909} from "@openzeppelin/contracts/token/ERC6909/ERC6909.sol";

contract YakumoStore is ERC6909 {
    struct Work {
        address creator;
        bytes32 metadataUri;
        bool transferable;
        uint256 price;
    }

    uint256 public idCounter = 0;
    mapping(uint256 => Work) public works;
    mapping(address => uint256) public pendingWithdrawals;

    event WorkRegistered(uint256 indexed id, address indexed creator);
    event EditionMinted(uint256 indexed id, address indexed to, uint256 amount);
    event EditionTransferred(uint256 indexed id, address indexed from, address indexed to, uint256 amount);
    event PriceChanged(uint256 indexed id, uint256 previousPrice, uint256 newPrice);
    event Purchased(address indexed buyer, uint256 indexed id, uint256 amount);
    event Withdrawn(address indexed creator, uint256 amount);

    error NotCreator();
    error ArrayLengthMismatch();
    error InvalidWorkId();
    error IncorrectPayment();
    error NoPendingWithdrawal();
    error WithdrawalFailed();
    error NonTransferable();

    function registerWork(bytes32 metadataUri, bool transferable, uint256 price) external returns (uint256) {
        works[idCounter] =
            Work({creator: msg.sender, metadataUri: metadataUri, transferable: transferable, price: price});
        emit WorkRegistered(idCounter, msg.sender);

        idCounter++;
        return idCounter - 1;
    }

    function changePrice(uint256 id, uint256 newPrice) external {
        if (msg.sender != works[id].creator) {
            revert NotCreator();
        }
        uint256 previousPrice = works[id].price;
        works[id].price = newPrice;

        emit PriceChanged(id, previousPrice, newPrice);
    }

    function purchase(uint256[] calldata ids, uint256[] calldata amounts) external payable {
        if (ids.length != amounts.length) {
            revert ArrayLengthMismatch();
        }

        uint256 total = 0;
        uint256 maxId = idCounter;
        for (uint256 i = 0; i < ids.length;) {
            uint256 id = ids[i];
            if (id >= maxId) {
                revert InvalidWorkId();
            }
            total += works[id].price * amounts[i];
            unchecked {
                ++i;
            }
        }
        if (msg.value != total) {
            revert IncorrectPayment();
        }

        for (uint256 i = 0; i < ids.length;) {
            uint256 id = ids[i];
            uint256 amount = amounts[i];
            uint256 price = works[id].price;
            _mint(msg.sender, id, amount);
            emit EditionMinted(id, msg.sender, amount);

            address creator = works[id].creator;
            pendingWithdrawals[creator] += price * amount;
            emit Purchased(msg.sender, id, amount);

            unchecked {
                ++i;
            }
        }
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

    function isTransferable(uint256 id) public view returns (bool) {
        return works[id].transferable;
    }

    function transfer(address receiver, uint256 id, uint256 amount) public virtual override returns (bool) {
        if (!isTransferable(id)) {
            revert NonTransferable();
        }
        bool result = super.transfer(receiver, id, amount);
        emit EditionTransferred(id, msg.sender, receiver, amount);
        return result;
    }

    function transferFrom(address sender, address receiver, uint256 id, uint256 amount)
        public
        virtual
        override
        returns (bool)
    {
        if (!isTransferable(id)) {
            revert NonTransferable();
        }
        bool result = super.transferFrom(sender, receiver, id, amount);
        emit EditionTransferred(id, sender, receiver, amount);
        return result;
    }
}
