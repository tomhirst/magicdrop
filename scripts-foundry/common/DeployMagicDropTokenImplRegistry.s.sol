// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {MagicDropTokenImplRegistry} from "contracts/registry/MagicDropTokenImplRegistry.sol";
import {LibClone} from "solady/src/utils/LibClone.sol";

contract DeployMagicDropTokenImplRegistry is Script {
    error AddressMismatch();
    
    function run() external {
        bytes32 salt = vm.envBytes32("REGISTRY_SALT");
        address expectedAddress = address(uint160(vm.envUint("REGISTRY_EXPECTED_ADDRESS")));
        address initialOwner = address(uint160(vm.envUint("INITIAL_OWNER")));
        uint256 privateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(privateKey);
        
        // Deploy the implementation contract
        MagicDropTokenImplRegistry implementation = new MagicDropTokenImplRegistry{salt: salt}();

        // Verify the implementation address matches the predicted address
        if (address(implementation) != expectedAddress) {
            revert AddressMismatch();
        }

        // Deploy the ERC1967 proxy
        address proxy = LibClone.deployDeterministicERC1967(address(implementation), salt);

        // Initialize the proxy with the constructor arguments
        MagicDropTokenImplRegistry(proxy).initialize(initialOwner);

        console.log("Proxy deployed:", proxy);

        vm.stopBroadcast();
    }
}
