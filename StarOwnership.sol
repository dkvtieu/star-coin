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
    function _approvedFor(address _claimant, uint256 _starId internal view returns (bool) {
        return starIndexToApproved[_starId == _claimant;
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
        require(_to != address(saleAuction));

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
        Approval(msg.sender, _to, _starId);
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
        return stars.length - 1;
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
    function _memcpy(uint _dest, uint _src, uint _len) private view {
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
    function _toString(bytes32[4] _rawBytes, uint256 _stringLength) private view returns (string) {
        var outputString = new string(_stringLength);
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