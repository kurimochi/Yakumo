// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {IERC3009} from "../src/IERC3009.sol";

contract TestERC20Token is ERC20 {
    constructor() ERC20("Test Token", "TEST") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract FalseERC20Token is ERC20 {
    constructor() ERC20("False Token", "FALSE") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function transferFrom(address, address, uint256) public pure override returns (bool) {
        return false;
    }
}

contract TestERC3009Token is ERC20, EIP712, IERC3009 {
    constructor() ERC20("Test Token", "TEST") EIP712("Test Token", "1") {}

    bytes32 public constant TRANSFER_WITH_AUTHORIZATION_TYPEHASH = keccak256(
        "TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"
    );
    bytes32 public constant RECEIVE_WITH_AUTHORIZATION_TYPEHASH = keccak256(
        "ReceiveWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"
    );

    mapping(address => mapping(bytes32 => bool)) internal _authorizationStates;

    error AuthorizationIsNotYetValid();
    error AuthorizationIsExpired();
    error AuthorizationIsUsed();
    error InvalidSignature();
    error CallerMustBeThePayee();

    function authorizationState(address authorizer, bytes32 nonce) external view returns (bool) {
        return _authorizationStates[authorizer][nonce];
    }

    function transferWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        if (block.timestamp <= validAfter) {
            revert AuthorizationIsNotYetValid();
        }
        if (block.timestamp >= validBefore) {
            revert AuthorizationIsExpired();
        }
        if (_authorizationStates[from][nonce]) {
            revert AuthorizationIsUsed();
        }

        bytes32 structHash = keccak256(
            abi.encode(TRANSFER_WITH_AUTHORIZATION_TYPEHASH, from, to, value, validAfter, validBefore, nonce)
        );
        bytes32 digest = _hashTypedDataV4(structHash);

        if (ecrecover(digest, v, r, s) != from) {
            revert InvalidSignature();
        }

        _authorizationStates[from][nonce] = true;
        emit AuthorizationUsed(from, nonce);

        _transfer(from, to, value);
    }

    function receiveWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        if (to != msg.sender) {
            revert CallerMustBeThePayee();
        }

        if (block.timestamp <= validAfter) {
            revert AuthorizationIsNotYetValid();
        }
        if (block.timestamp >= validBefore) {
            revert AuthorizationIsExpired();
        }
        if (_authorizationStates[from][nonce]) {
            revert AuthorizationIsUsed();
        }

        bytes32 structHash =
            keccak256(abi.encode(RECEIVE_WITH_AUTHORIZATION_TYPEHASH, from, to, value, validAfter, validBefore, nonce));
        bytes32 digest = _hashTypedDataV4(structHash);

        if (ecrecover(digest, v, r, s) != from) {
            revert InvalidSignature();
        }

        _authorizationStates[from][nonce] = true;
        emit AuthorizationUsed(from, nonce);

        _transfer(from, to, value);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function hashTypedDataV4(bytes32 structHash) external view returns (bytes32) {
        return _hashTypedDataV4(structHash);
    }
}
