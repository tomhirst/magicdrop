// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {ERC721MInitializableV1_0_2 as ERC721MInitializable} from "contracts/nft/erc721m/ERC721MInitializableV1_0_2.sol";
import {ERC1155MInitializableV1_0_2 as ERC1155MInitializable} from "contracts/nft/erc1155m/ERC1155MInitializableV1_0_2.sol";
import {ERC721MagicDropCloneable} from "contracts/nft/erc721m/clones/ERC721MagicDropCloneable.sol";
import {ERC1155MagicDropCloneable} from "contracts/nft/erc1155m/clones/ERC1155MagicDropCloneable.sol";
import {TokenStandard} from "contracts/common/Structs.sol";

enum Usecase {
    ERC721_LP,
    ERC1155_LP,
    ERC721_SS,
    ERC1155_SS
}

contract DeployMagicDropImplementation is Script {
    error AddressMismatch(address expected, address actual);
    error InvalidTokenStandard(string standard);
    error InvalidUsecase(string usecase);

    function run() external {
        bytes32 salt = vm.envBytes32("IMPL_SALT");
        address expectedAddress = address(uint160(vm.envUint("IMPL_EXPECTED_ADDRESS")));
        Usecase usecase = parseUsecase(vm.envString("TOKEN_STANDARD"));
        TokenStandard standard = parseTokenStandard(usecase);
        uint256 privateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(privateKey);

        address deployedAddress;

        if (standard == TokenStandard.ERC721) {
            if (usecase == Usecase.ERC721_LP) {
                deployedAddress = address(new ERC721MInitializable{salt: salt}());
            } else if (usecase == Usecase.ERC721_SS) {
                deployedAddress = address(new ERC721MagicDropCloneable{salt: salt}());
            }
        } else if (standard == TokenStandard.ERC1155) {
            if (usecase == Usecase.ERC1155_LP) {
                deployedAddress = address(new ERC1155MInitializable{salt: salt}());
            } else if (usecase == Usecase.ERC1155_SS) {
                deployedAddress = address(new ERC1155MagicDropCloneable{salt: salt}());
            }
        }

        if (address(deployedAddress) != expectedAddress) {
            revert AddressMismatch(expectedAddress, deployedAddress);
        }

        console.log("Implementation deployed:", deployedAddress);

        vm.stopBroadcast();
    }

    function stringEquals(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }

    function parseUsecase(string memory usecaseString) internal pure returns (Usecase) {
        if (stringEquals(usecaseString, "ERC721_LP")) {
            return Usecase.ERC721_LP;
        } else if (stringEquals(usecaseString, "ERC1155_LP")) {
            return Usecase.ERC1155_LP;
        } else if (stringEquals(usecaseString, "ERC721_SS")) {
            return Usecase.ERC721_SS;
        } else if (stringEquals(usecaseString, "ERC1155_SS")) {
            return Usecase.ERC1155_SS;
        } else {
            revert InvalidUsecase(usecaseString);
        }
    }
    
    function parseTokenStandard(Usecase usecase) internal pure returns (TokenStandard) {
        if (usecase == Usecase.ERC721_LP || usecase == Usecase.ERC721_SS) {
            return TokenStandard.ERC721;
        } else if (usecase == Usecase.ERC1155_LP || usecase == Usecase.ERC1155_SS) {
            return TokenStandard.ERC1155;
        } else {
            revert InvalidTokenStandard("Invalid usecase");
        }
    }
}
