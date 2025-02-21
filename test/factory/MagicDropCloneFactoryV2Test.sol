// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Initializable} from "solady/src/utils/Initializable.sol";
import {UUPSUpgradeable} from "solady/src/utils/UUPSUpgradeable.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import {LibClone} from "solady/src/utils/LibClone.sol";
import {TokenStandard} from "contracts/common/Structs.sol";
import {MagicDropTokenImplRegistry} from "contracts/registry/MagicDropTokenImplRegistry.sol";

/// @title MagicDropCloneFactoryV2Test
/// @notice A factory contract for creating and managing clones of MagicDrop contracts
/// @dev This contract uses the UUPS proxy pattern
contract MagicDropCloneFactoryV2Test is Ownable, UUPSUpgradeable, Initializable {
    /*==============================================================
    =                            STORAGE                           =
    ==============================================================*/

    /// @notice The registry contract
    MagicDropTokenImplRegistry private _registry;

    /// @notice The max deployment fee (example variable to test upgradability)
    uint256 private _maxDeploymentFee;

    /// @notice Gap for future upgrades (reduced by 1 slot from V1 to test upgradability)
    uint256[47] private __gap;

    // /// @notice The max mint fee (example variable to test upgradability)
    uint256 private _maxMintFee = 0.0025 ether;

    /*==============================================================
    =                           CONSTANTS                          =
    ==============================================================*/

    bytes4 private constant INITIALIZE_SELECTOR = bytes4(keccak256("initialize(string,string,address,uint256)"));

    /*==============================================================
    =                             EVENTS                           =
    ==============================================================*/

    event MagicDropFactoryInitialized();
    event NewContractInitialized(
        address contractAddress,
        address initialOwner,
        uint32 implId,
        TokenStandard standard,
        string name,
        string symbol,
        uint256 mintFee
    );
    event Withdrawal(address to, uint256 amount);

    /*==============================================================
    =                             ERRORS                           =
    ==============================================================*/

    error InitializationFailed();
    error RegistryAddressCannotBeZero();
    error InsufficientDeploymentFee();
    error WithdrawalFailed();
    error InitialOwnerCannotBeZero();
    error NewImplementationCannotBeZero();

    /*==============================================================
    =                          INITIALIZER                         =
    ==============================================================*/

    /// @dev Disables initializers for the implementation contract.
    constructor() {
        _disableInitializers();
    }

    /// @param initialOwner The address of the initial owner
    /// @param registry The address of the registry contract
    function initialize(address initialOwner, address registry) public initializer {
        if (registry == address(0)) {
            revert RegistryAddressCannotBeZero();
        }

        _registry = MagicDropTokenImplRegistry(registry);
        _initializeOwner(initialOwner);

        emit MagicDropFactoryInitialized();
    }

    /*==============================================================
    =                      PUBLIC WRITE METHODS                    =
    ==============================================================*/

    /// @notice Creates a new deterministic clone of a MagicDrop contract
    /// @param name The name of the new contract
    /// @param symbol The symbol of the new contract
    /// @param standard The token standard of the new contract
    /// @param initialOwner The initial owner of the new contract
    /// @param implId The implementation ID
    /// @param salt A unique salt for deterministic address generation
    /// @return The address of the newly created contract
    function createContractDeterministic(
        string calldata name,
        string calldata symbol,
        TokenStandard standard,
        address payable initialOwner,
        uint32 implId,
        bytes32 salt
    ) external payable returns (address) {
        address impl;
        // Retrieve the implementation address from the registry
        if (implId == 0) {
            impl = _registry.getDefaultImplementation(standard);
        } else {
            impl = _registry.getImplementation(standard, implId);
        }

        if (initialOwner == address(0)) {
            revert InitialOwnerCannotBeZero();
        }

        // Retrieve the deployment fee for the implementation and ensure the caller has sent the correct amount
        uint256 deploymentFee = _registry.getDeploymentFee(standard, implId);
        if (msg.value < deploymentFee) {
            revert InsufficientDeploymentFee();
        }

        // Retrieve the mint fee for the implementation
        uint256 mintFee = _registry.getMintFee(standard, implId);

        // Create a unique salt by combining original salt with chain ID and sender
        bytes32 _salt = keccak256(abi.encode(salt, block.chainid, msg.sender));
        // Create a deterministic clone of the implementation contract
        address instance = LibClone.cloneDeterministic(impl, _salt);

        // Initialize the newly created contract
        (bool success,) =
            instance.call(abi.encodeWithSelector(INITIALIZE_SELECTOR, name, symbol, initialOwner, mintFee));
        if (!success) {
            revert InitializationFailed();
        }

        emit NewContractInitialized({
            contractAddress: instance,
            initialOwner: initialOwner,
            implId: implId,
            standard: standard,
            name: name,
            symbol: symbol,
            mintFee: mintFee
        });

        return instance;
    }

    /// @notice Creates a new clone of a MagicDrop contract
    /// @param name The name of the new contract
    /// @param symbol The symbol of the new contract
    /// @param standard The token standard of the new contract
    /// @param initialOwner The initial owner of the new contract
    /// @param implId The implementation ID
    /// @return The address of the newly created contract
    function createContract(
        string calldata name,
        string calldata symbol,
        TokenStandard standard,
        address payable initialOwner,
        uint32 implId
    ) external payable returns (address) {
        address impl;
        // Retrieve the implementation address from the registry
        if (implId == 0) {
            impl = _registry.getDefaultImplementation(standard);
        } else {
            impl = _registry.getImplementation(standard, implId);
        }

        if (initialOwner == address(0)) {
            revert InitialOwnerCannotBeZero();
        }

        // Retrieve the deployment fee for the implementation and ensure the caller has sent the correct amount
        uint256 deploymentFee = _registry.getDeploymentFee(standard, implId);
        if (msg.value < deploymentFee) {
            revert InsufficientDeploymentFee();
        }

        // Retrieve the mint fee for the implementation
        uint256 mintFee = _registry.getMintFee(standard, implId);

        // Create a non-deterministic clone of the implementation contract
        address instance = LibClone.clone(impl);

        // Initialize the newly created contract
        (bool success,) =
            instance.call(abi.encodeWithSelector(INITIALIZE_SELECTOR, name, symbol, initialOwner, mintFee));
        if (!success) {
            revert InitializationFailed();
        }

        emit NewContractInitialized({
            contractAddress: instance,
            initialOwner: initialOwner,
            implId: implId,
            standard: standard,
            name: name,
            symbol: symbol,
            mintFee: mintFee
        });

        return instance;
    }

    /*==============================================================
    =                      PUBLIC VIEW METHODS                     =
    ==============================================================*/

    /// @notice Predicts the deployment address of a deterministic clone
    /// @param standard The token standard of the contract
    /// @param implId The implementation ID
    /// @param salt The salt used for address generation
    /// @return The predicted deployment address
    function predictDeploymentAddress(TokenStandard standard, uint32 implId, bytes32 salt)
        external
        view
        returns (address)
    {
        address impl;
        if (implId == 0) {
            impl = _registry.getDefaultImplementation(standard);
        } else {
            impl = _registry.getImplementation(standard, implId);
        }
        bytes32 _salt = keccak256(abi.encode(salt, block.chainid, msg.sender));
        return LibClone.predictDeterministicAddress(impl, _salt, address(this));
    }

    /// @notice Retrieves the address of the registry contract
    /// @return The address of the registry contract
    function getRegistry() external view returns (address) {
        return address(_registry);
    }

    /// @notice Retrieves the max deployment fee
    /// @dev This function is only used to test upgradability
    /// @return The max deployment fee
    function getMaxDeploymentFee() external view returns (uint256) {
        return _maxDeploymentFee;
    }

    // @notice Reads a storage slot
    // @dev This function is only used to test upgradability
    // @param slot The slot to read
    // @return The data stored in the slot
    function readStorageSlot(uint256 slot) public view returns (bytes32) {
        // Assembly block to read storage slot
        bytes32 data;
        assembly {
            // Use SLOAD to read from the storage slot
            data := sload(slot)
        }

        return data;
    }

    // @notice Reads a storage slot as a uint
    // @dev This function is only used to test upgradability
    // @param slot The slot to read
    // @return The data stored in the slot as a uint
    function readStorageSlotAsUint(uint256 slot) public view returns (uint256) {
        bytes32 data = readStorageSlot(slot);
        return uint256(data);
    }

    // @notice Reads a storage slot as a string
    // @dev This function is only used to test upgradability
    // @param slot The slot to read
    // @return The data stored in the slot as a string
    function readStorageSlotAsString(uint256 slot) public view returns (string memory) {
        bytes32 data = readStorageSlot(slot);
        return string(abi.encodePacked(data));
    }

    /*==============================================================
    =                      ADMIN OPERATIONS                        =
    ==============================================================*/

    ///@dev Internal function to authorize an upgrade.
    ///@param newImplementation Address of the new implementation.
    ///@notice Only the contract owner can upgrade the contract.
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {
        if (newImplementation == address(0)) {
            revert NewImplementationCannotBeZero();
        }
    }

    /// @notice Withdraws the contract's balance
    function withdraw(address to) external onlyOwner {
        (bool success,) = to.call{value: address(this).balance}("");
        if (!success) {
            revert WithdrawalFailed();
        }

        emit Withdrawal(to, address(this).balance);
    }

    /// @dev Overriden to prevent double-initialization of the owner.
    function _guardInitializeOwner() internal pure virtual override returns (bool) {
        return true;
    }

    /// @notice Receives ETH
    receive() external payable {}

    /// @notice Fallback function to receive ETH
    fallback() external payable {}

    /// @notice Sets the max deployment fee
    /// @dev This function is only used to test upgradability
    function setMaxDeploymentFee(uint256 newFee) external onlyOwner {
        _maxDeploymentFee = newFee;
    }
}
