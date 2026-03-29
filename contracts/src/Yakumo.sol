// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC6909} from "@openzeppelin/contracts/token/ERC6909/ERC6909.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract YakumoStore is ERC6909 {
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
    event EditionMinted(uint256 indexed id, address indexed to, uint256 amount);
    event EditionTransferred(uint256 indexed id, address indexed from, address indexed to, uint256 amount);
    event PriceChanged(uint256 indexed id, uint256 previousPrice, uint256 newPrice, address newTokenContract);
    event Purchased(address indexed buyer, uint256 indexed id, uint256 amount);
    event Withdrawn(address indexed creator, uint256 amount);

    error NotCreator();
    error ArrayLengthMismatch();
    error InvalidWorkId();
    error IncorrectPayment();
    error TransferFailed();
    error NoPendingWithdrawal();
    error WithdrawalFailed();
    error NonTransferable();
    error InvalidTokenContract();

    function registerWork(string calldata metadataUri, bool transferable, uint256 price, address tokenContract)
        external
        returns (uint256)
    {
        if (tokenContract != address(0) && !_supportsErc20(tokenContract)) {
            revert InvalidTokenContract();
        }
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

    function changePrice(uint256 id, uint256 newPrice, address newTokenContract) external {
        if (msg.sender != works[id].creator) {
            revert NotCreator();
        }
        if (newTokenContract != address(0) && !_supportsErc20(newTokenContract)) {
            revert InvalidTokenContract();
        }

        uint256 previousPrice = works[id].price;
        works[id].price = newPrice;
        works[id].tokenContract = newTokenContract;

        emit PriceChanged(id, previousPrice, newPrice, newTokenContract);
    }

    function purchaseWithEth(uint256 id, uint256 amount) external payable {
        if (id >= idCounter) {
            revert InvalidWorkId();
        }
        if (works[id].tokenContract != address(0)) {
            revert InvalidTokenContract();
        }

        uint256 total = works[id].price * amount;
        if (msg.value != total) {
            revert IncorrectPayment();
        }

        _mint(msg.sender, id, amount);
        emit EditionMinted(id, msg.sender, amount);

        address creator = works[id].creator;
        pendingWithdrawals[creator] += total;
        emit Purchased(msg.sender, id, amount);
    }

    function purchaseWithErc20(uint256 id, uint256 amount) external {
        if (id >= idCounter) {
            revert InvalidWorkId();
        }

        address tokenContract = works[id].tokenContract;
        if (tokenContract == address(0)) {
            revert InvalidTokenContract();
        }

        uint256 total = works[id].price * amount;
        bool success = IERC20(tokenContract).transferFrom(msg.sender, works[id].creator, total);
        if (!success) {
            revert TransferFailed();
        }

        _mint(msg.sender, id, amount);
        emit EditionMinted(id, msg.sender, amount);

        emit Purchased(msg.sender, id, amount);
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

    bytes4 constant TOTAL_SUPPLY_SELECTOR = bytes4(keccak256("totalSupply()"));
    bytes4 constant BALANCE_OF_SELECTOR = bytes4(keccak256("balanceOf(address)"));

    function _supportsErc20(address tokenContract) internal view returns (bool) {
        (bool totalSupplyOk, bytes memory totalSupplyData) =
            tokenContract.staticcall(abi.encodeWithSelector(TOTAL_SUPPLY_SELECTOR));
        if (!totalSupplyOk || totalSupplyData.length < 32) {
            return false;
        }

        (bool balanceOfOk, bytes memory balanceOfData) =
            tokenContract.staticcall(abi.encodeWithSelector(BALANCE_OF_SELECTOR, address(this)));
        if (!balanceOfOk || balanceOfData.length < 32) {
            return false;
        }

        return true;
    }
}
