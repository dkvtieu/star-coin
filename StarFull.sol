/// @title A subset of StarCore that handles a permission based role system.
/// @author dkvtieu + massive help from the CryptoKitties source code (thank you!)

pragma solidity ^0.4.25;

contract StarPermissionHandler {
    // There is currently one role managed here:
    //
    // CEO: (Initially set to the address that created the smart contract in the StarCore constructor.)
    // - Can reassign other roles
    // - Can change the addresses of StarCore's dependent smart contracts.
    // - Can unpause the smart contract.
    //
    // CFO:
    // - Can withdraw funds from StarCore and its SaleAuction contract.
    //
    // COO:
    // - Can mint new coins

    // The addresses of the accounts (or contracts) that can execute actions within each roles.
    address public ceoAddress;
    address public cfoAddress;
    address public cooAddress;

    // @dev Keeps track whether the contract is paused. When that is true, most actions are blocked
    bool public paused = false;

    /// @dev Access modifier for CEO-only functionality
    modifier onlyCEO() {
        require(msg.sender == ceoAddress);
        _;
    }

    /// @dev Access modifier for CFO-only functionality
    modifier onlyCFO() {
        require(msg.sender == cfoAddress);
        _;
    }

    /// @dev Access modifier for COO-only functionality
    modifier onlyCOO() {
        require(msg.sender == cooAddress);
        _;
    }

    modifier onlyCLevel() {
        require(
            msg.sender == cooAddress ||
            msg.sender == ceoAddress ||
            msg.sender == cfoAddress
        );
        _;
    }

    /// @dev Assigns a new address to act as the CEO. Only available to the current CEO.
    /// @param _newCEO The address of the new CEO
    function setCEO(address _newCEO) external onlyCEO {
        require(_newCEO != address(0));

        ceoAddress = _newCEO;
    }

    /// @dev Assigns a new address to act as the CFO. Only available to the current CEO.
    /// @param _newCFO The address of the new CFO
    function setCFO(address _newCFO) external onlyCEO {
        require(_newCFO != address(0));

        cfoAddress = _newCFO;
    }

    /// @dev Assigns a new address to act as the COO. Only available to the current CEO.
    /// @param _newCOO The address of the new COO
    function setCOO(address _newCOO) external onlyCEO {
        require(_newCOO != address(0));

        cooAddress = _newCOO;
    }

    /*** Pausable functionality adapted from OpenZeppelin ***/

    /// @dev Modifier to allow actions only when the contract IS NOT paused
    modifier whenNotPaused() {
        require(!paused);
        _;
    }

    /// @dev Modifier to allow actions only when the contract IS paused
    modifier whenPaused {
        require(paused);
        _;
    }

    /// @dev Called by any "C-level" role to pause the contract. Used only when
    ///  a bug or exploit is detected and we need to limit damage.
    function pause() external onlyCLevel whenNotPaused {
        paused = true;
    }

    /// @dev Unpauses the smart contract. Can only be called by the CEO, since
    ///  one reason we may pause the contract is when CFO or COO accounts are
    ///  compromised.
    /// @notice This is public rather than external so it can be called by
    ///  derived contracts.
    function unpause() public onlyCEO whenPaused {
        // can't unpause if contract was upgraded
        paused = false;
    }
}

/// @title Base contract for StarCoin. Holds all common structs, events and base variables.
/// @author dkvtieu + massive help from the CryptoKitties source code (thank you!)

contract StarBase is StarPermissionHandler {
    /*** EVENTS ***/

    /// @dev The Creation event is fired whenever a new StarCoin comes into existence
    ///  (on the contract).
    event Creation(address owner, uint256 starId);

    /// @dev Transfer event as defined in current draft of ERC721. Emitted every time a star
    ///  ownership is assigned, including Creations.
    event Transfer(address from, address to, uint256 tokenId);

    /*** DATA TYPES ***/

    /// @dev The main Star struct.
    ///  Note that the order of the members in this structure is important because of the
    ///  byte-packing rules used by Ethereum.
    ///  Ref: http://solidity.readthedocs.io/en/develop/miscellaneous.html
    struct Star {
        // The common name of the star
        bytes32 name;

        // The collection references this star in our sky-map db
        bytes32[] collectionReferences;

        // The timestamp from the block when this star came into existence (on the contract).
        uint64 creationTime;
    }

    /*** STORAGE ***/

    /// @dev An array of Star structs for all Stars in existence .
    ///  The (local to StarCore) localId of each star is actually an index into this array.
    Star[] stars;

    /// @dev A mapping from Star localIds to the address that owns them. All Stars have
    ///  some valid owner address, even newly added Stars are created with a non-zero owner.
    mapping (uint256 => address) public starIndexToOwner;

    // @dev A mapping from owner address to count of Stars that address owns.
    //  Used internally inside balanceOf() to resolve ownership count.
    mapping (address => uint256) ownershipStarCount;

    /// @dev A mapping from starIds to an address that has been approved to call
    ///  transferFrom(). Each Star can only have one approved address for transfer
    ///  at any time. A zero value means no approval is outstanding.
    mapping (uint256 => address) public starIndexToApproved;

    /// @dev Assigns ownership of a specific Star to an address.
    function _transfer(address _from, address _to, uint256 _starId) internal {
        // Since the number of Stars is capped to 2^32 we can't overflow this
        ownershipStarCount[_to]++;
        // transfer ownership
        starIndexToOwner[_starId] = _to;
        // When creating a new Star, _from is 0x0 but we can't account that address.
        if (_from != address(0)) {
            ownershipStarCount[_from]--;
            // clear any previously approved ownership exchange
            delete starIndexToApproved[_starId];
        }
        // Emit the transfer event.
        emit Transfer(_from, _to, _starId);
    }

    /// @dev An internal method that creates a new Star and stores it. This
    ///  method doesn't do any checking and should only be called when the
    ///  input data is known to be valid. Will generate both a Creation event
    ///  and a Transfer event.

    function _createStar(
        bytes32 _name,
        bytes32[] _collectionReferences,
        address _owner
    )
        internal
        returns (uint)
    {
        // These requires are not strictly necessary, our calling code should make
        // sure that these conditions are never broken. However! _createStar() is already
        // an expensive call (for storage), and it doesn't hurt to be especially careful
        // to ensure our data structures are always valid.
        // require(_matronId == uint256(uint32(_matronId)));
        // require(_sireId == uint256(uint32(_sireId)));
        // require(_generation == uint256(uint16(_generation)));

        Star memory _star = Star({
            creationTime: uint64(now),
            name: _name,
            collectionReferences: _collectionReferences
        });
        uint256 newStarId = stars.push(_star) - 1;

        // May never happen but it's good practice to check just incase
        require(newStarId == uint256(uint32(newStarId)));

        // emit the birth event
        emit Creation(
            _owner,
            newStarId
        );

        // This will assign ownership, and also emit the Transfer event as
        // per ERC721 draft
        _transfer(0, _owner, newStarId);

        return newStarId;
    }
}

/// @title Interface for contracts conforming to ERC-721: Non-Fungible Tokens
/// @author dkvtieu + massive help from the CryptoKitties source code (thank you!)

contract ERC721 {
    // Required methods
    function totalSupply() public view returns (uint256 total);
    function balanceOf(address _owner) public view returns (uint256 balance);
    function ownerOf(uint256 _tokenId) external view returns (address owner);
    function approve(address _to, uint256 _tokenId) external;
    function transfer(address _to, uint256 _tokenId) external;
    function transferFrom(address _from, address _to, uint256 _tokenId) external;

    // Events
    event Transfer(address from, address to, uint256 tokenId);
    event Approval(address owner, address approved, uint256 tokenId);

    // ERC-165 Compatibility (https://github.com/ethereum/EIPs/issues/165)
    function supportsInterface(bytes4 _interfaceID) external view returns (bool);
}

/// @title The external contract that is responsible for generating metadata for the kitties,
///  it has one function that will return the data as bytes.

contract ERC721Metadata {
    /// @dev Given a token Id, returns a byte array that is supposed to be converted into string.
    function getMetadata(uint256 _tokenId, string) public pure returns (bytes32[4] buffer, uint256 count) {
        if (_tokenId == 1) {
            buffer[0] = "Hello World! :D";
            count = 15;
        } else if (_tokenId == 2) {
            buffer[0] = "I would definitely choose a medi";
            buffer[1] = "um length string.";
            count = 49;
        } else if (_tokenId == 3) {
            buffer[0] = "Lorem ipsum dolor sit amet, mi e";
            buffer[1] = "st accumsan dapibus augue lorem,";
            buffer[2] = " tristique vestibulum id, libero";
            buffer[3] = " suscipit varius sapien aliquam.";
            count = 128;
        }
    }
}

/// @title Manages ownership, ERC-721 (draft) compliant.
/// @author dkvtieu + massive help from the CryptoKitties source code (thank you!)
/// @dev Ref: https://github.com/ethereum/EIPs/issues/721

contract StarOwnership is StarBase, ERC721 {

    /// @notice Name and symbol of the non fungible token, as defined in ERC721.
    string public constant name = "StarCoin";
    string public constant symbol = "STAC";

    // The contract that will return Star metadata
    ERC721Metadata public erc721Metadata;

    bytes4 constant InterfaceSignature_ERC165 =
        bytes4(keccak256('supportsInterface(bytes4)'));

    bytes4 constant InterfaceSignature_ERC721 =
        bytes4(keccak256('name()')) ^
        bytes4(keccak256('symbol()')) ^
        bytes4(keccak256('totalSupply()')) ^
        bytes4(keccak256('balanceOf(address)')) ^
        bytes4(keccak256('ownerOf(uint256)')) ^
        bytes4(keccak256('approve(address,uint256)')) ^
        bytes4(keccak256('transfer(address,uint256)')) ^
        bytes4(keccak256('transferFrom(address,address,uint256)')) ^
        bytes4(keccak256('tokensOfOwner(address)')) ^
        bytes4(keccak256('tokenMetadata(uint256,string)'));

    /// @notice Introspection interface as per ERC-165 (https://github.com/ethereum/EIPs/issues/165).
    ///  Returns true for any standardized interfaces implemented by this contract. We implement
    ///  ERC-165 (obviously!) and ERC-721.
    function supportsInterface(bytes4 _interfaceID) external view returns (bool)
    {
        // DEBUG ONLY
        //require((InterfaceSignature_ERC165 == 0x01ffc9a7) && (InterfaceSignature_ERC721 == 0x9a20483d));

        return ((_interfaceID == InterfaceSignature_ERC165) || (_interfaceID == InterfaceSignature_ERC721));
    }

    /// @dev Set the address of the sibling contract that tracks metadata.
    ///  CEO only.
    function setMetadataAddress(address _contractAddress) public onlyCEO {
        erc721Metadata = ERC721Metadata(_contractAddress);
    }

    // Internal utility functions: These functions all assume that their input arguments
    // are valid. We leave it to public methods to sanitize their inputs and follow
    // the required logic.

    /// @dev Checks if a given address is the current owner of a particular Star.
    /// @param _claimant the address we are validating against.
    /// @param _starId Star id, only valid when > 0
    function _owns(address _claimant, uint256 _starId) internal view returns (bool) {
        return starIndexToOwner[_starId] == _claimant;
    }

    /// @dev Checks if a given address currently has transferApproval for a particular Star.
    /// @param _claimant the address we are confirming the Star is approved for.
    /// @param _starId Star id, only valid when > 0
    function _approvedFor(address _claimant, uint256 _starId) internal view returns (bool) {
        return starIndexToApproved[_starId] == _claimant;
    }

    /// @dev Marks an address as being approved for transferFrom(), overwriting any previous
    ///  approval. Setting _approved to address(0) clears all transfer approval.
    ///  NOTE: _approve() does NOT send the Approval event. This is intentional because
    ///  _approve() and transferFrom() are used together for putting Stars on auction, and
    ///  there is no value in spamming the log with Approval events in that case.
    function _approve(uint256 _starId, address _approved) internal {
        starIndexToApproved[_starId] = _approved;
    }

    /// @notice Returns the number of Stars owned by a specific address.
    /// @param _owner The owner address to check.
    /// @dev Required for ERC-721 compliance
    function balanceOf(address _owner) public view returns (uint256 count) {
        return ownershipStarCount[_owner];
    }

    /// @notice Transfers a Star to another address. If transferring to a smart
    ///  contract be VERY CAREFUL to ensure that it is aware of ERC-721 (or
    ///  the StarCoin contract specifically) or your Star may be lost forever.
    /// @param _to The address of the recipient, can be a user or contract.
    /// @param _starId The ID of the Star to transfer.
    /// @dev Required for ERC-721 compliance.
    function transfer(
        address _to,
        uint256 _starId
    )
        external
        whenNotPaused
    {
        // Safety check to prevent against an unexpected 0x0 default.
        require(_to != address(0));
        // Disallow transfers to this contract to prevent accidental misuse.
        // The contract should never own any Stars (except very briefly
        // after a Star is initially minted and before it goes on auction).
        require(_to != address(this));
        // Disallow transfers to the auction contracts to prevent accidental
        // misuse. Auction contracts should only take ownership of Stars
        // through the allow + transferFrom flow.
        // require(_to != address(saleAuction));

        // You can only send your own star.
        require(_owns(msg.sender, _starId));

        // Reassign ownership, clear pending approvals, emit Transfer event.
        _transfer(msg.sender, _to, _starId);
    }

    /// @notice Grant another address the right to transfer a specific Star via
    ///  transferFrom(). This is the preferred flow for transfering NFTs to contracts.
    /// @param _to The address to be granted transfer approval. Pass address(0) to
    ///  clear all approvals.
    /// @param _starId The ID of the Star that can be transferred if this call succeeds.
    /// @dev Required for ERC-721 compliance.
    function approve(
        address _to,
        uint256 _starId
    )
        external
        whenNotPaused
    {
        // Only an owner can grant transfer approval.
        require(_owns(msg.sender, _starId));

        // Register the approval (replacing any previous approval).
        _approve(_starId, _to);

        // Emit approval event.
        emit Approval(msg.sender, _to, _starId);
    }

    /// @notice Transfer a Star owned by another address, for which the calling address
    ///  has previously been granted transfer approval by the owner.
    /// @param _from The address that owns the Star to be transfered.
    /// @param _to The address that should take ownership of the Star. Can be any address,
    ///  including the caller.
    /// @param _starId The ID of the Star to be transferred.
    /// @dev Required for ERC-721 compliance.
    function transferFrom(
        address _from,
        address _to,
        uint256 _starId
    )
        external
        whenNotPaused
    {
        // Safety check to prevent against an unexpected 0x0 default.
        require(_to != address(0));
        // Disallow transfers to this contract to prevent accidental misuse.
        // The contract should never own any Stars (except very briefly
        // after a Star is initially minted and before it goes on auction).
        require(_to != address(this));
        // Check for approval and valid ownership
        require(_approvedFor(msg.sender, _starId));
        require(_owns(_from, _starId));

        // Reassign ownership (also clears pending approvals and emits Transfer event).
        _transfer(_from, _to, _starId);
    }

    /// @notice Returns the total number of Stars currently in existence.
    /// @dev Required for ERC-721 compliance.
    function totalSupply() public view returns (uint) {
        return stars.length;
    }

    /// @notice Returns the address currently assigned ownership of a given Star.
    /// @dev Required for ERC-721 compliance.
    function ownerOf(uint256 _starId)
        external
        view
        returns (address owner)
    {
        owner = starIndexToOwner[_starId];

        require(owner != address(0));
    }

    /// @notice Returns a list of all Stars IDs assigned to an address.
    /// @param _owner The owner whose Stars we are interested in.
    /// @dev This method MUST NEVER be called by smart contract code. First, it's fairly
    ///  expensive (it walks the entire stars array looking for Stars belonging to owner),
    ///  but it also returns a dynamic array, which is only supported for web3 calls, and
    ///  not contract-to-contract calls.
    function tokensOfOwner(address _owner) external view returns(uint256[] ownerStars) {
        uint256 starCount = balanceOf(_owner);

        if (starCount == 0) {
            // Return an empty array
            return new uint256[](0);
        } else {
            uint256[] memory result = new uint256[](starCount);
            uint256 totalStars = totalSupply();
            uint256 resultIndex = 0;

            // We count on the fact that all Stars have IDs starting at 1 and increasing
            // sequentially up to the totalStar count.
            uint256 starId;

            for (starId = 1; starId <= totalStars; starId++) {
                if (starIndexToOwner[starId] == _owner) {
                    result[resultIndex] = starId;
                    resultIndex++;
                }
            }

            return result;
        }
    }

    /// @dev Adapted from memcpy() by @arachnid (Nick Johnson <arachnid@notdot.net>)
    ///  This method is licenced under the Apache License.
    ///  Ref: https://github.com/Arachnid/solidity-stringutils/blob/2f6ca9accb48ae14c66f1437ec50ed19a0616f78/strings.sol
    function _memcpy(uint _dest, uint _src, uint _len) private pure {
        // Copy word-length chunks while possible
        for(; _len >= 32; _len -= 32) {
            assembly {
                mstore(_dest, mload(_src))
            }
            _dest += 32;
            _src += 32;
        }

        // Copy remaining bytes
        uint256 mask = 256 ** (32 - _len) - 1;
        assembly {
            let srcpart := and(mload(_src), not(mask))
            let destpart := and(mload(_dest), mask)
            mstore(_dest, or(destpart, srcpart))
        }
    }

    /// @dev Adapted from toString(slice) by @arachnid (Nick Johnson <arachnid@notdot.net>)
    ///  This method is licenced under the Apache License.
    ///  Ref: https://github.com/Arachnid/solidity-stringutils/blob/2f6ca9accb48ae14c66f1437ec50ed19a0616f78/strings.sol
    function _toString(bytes32[4] _rawBytes, uint256 _stringLength) private pure returns (string) {
        string memory outputString = new string(_stringLength);
        uint256 outputPtr;
        uint256 bytesPtr;

        assembly {
            outputPtr := add(outputString, 32)
            bytesPtr := _rawBytes
        }

        _memcpy(outputPtr, bytesPtr, _stringLength);

        return outputString;
    }

    /// @notice Returns a URI pointing to a metadata package for this token conforming to
    ///  ERC-721 (https://github.com/ethereum/EIPs/issues/721)
    /// @param _starId The ID number of the Star whose metadata should be returned.
    function tokenMetadata(uint256 _starId, string _preferredTransport) external view returns (string infoUrl) {
        require(erc721Metadata != address(0));
        bytes32[4] memory buffer;
        uint256 count;
        (buffer, count) = erc721Metadata.getMetadata(_starId, _preferredTransport);

        return _toString(buffer, count);
    }
}

/// @title A subset of StarCore that handles minting new StarCoins
/// @author dkvtieu + massive help from the CryptoKitties source code (thank you!)

contract StarMinter is StarOwnership {
    function mintNewStar(
        bytes32 _name,
        bytes32[] _collectionReferences,
        address _owner
    ) external onlyCOO {
        address starOwner = _owner;
        if (starOwner == address(0)) {
             starOwner = cooAddress;
        }

        _createStar(_name, _collectionReferences, starOwner);
    }
}

/// @title StarCoin WIP
/// @author dkvtieu + massive help from the CryptoKitties source code (thank you!)

contract StarCore is StarMinter {
    /// @notice Creates the main CryptoKitties smart contract instance.
    constructor() public {
        // Starts paused.
        paused = true;

        // the creator of the contract is the initial CEO
        ceoAddress = msg.sender;

        // this is temporary, we should delegate different tasks to other roles so main CEO
        // address is used as little as possible
        cooAddress = msg.sender;
        cfoAddress = msg.sender;
    }

    /// @notice Returns all the relevant information about a specific Star.
    /// @param _starId The ID of the star of interest.
    function getStar(uint256 _starId)
        external
        view
        returns (
        bytes32 name,
        bytes32[] collectionReferences,
        uint64 creationTime
    ) {
        Star storage star = stars[_starId];

        name = star.name;
        collectionReferences = star.collectionReferences;
        creationTime = star.creationTime;
    }

    /// @dev Override unpause so it requires all external contract addresses
    ///  to be set before contract can be unpaused. Also, we can't have
    ///  newContractAddress set either, because then the contract was upgraded.
    /// @notice This is public rather than external so we can call super.unpause
    ///  without using an expensive CALL.
    function unpause() public onlyCEO whenPaused {
        // require(saleAuction != address(0));
        // require(newContractAddress == address(0));

        // Actually unpause the contract.
        super.unpause();
    }

    // @dev Allows the CFO to capture the balance available to the contract.
    function withdrawBalance() external onlyCFO {
        address _contract = this;
        cfoAddress.transfer(_contract.balance);
    }
}