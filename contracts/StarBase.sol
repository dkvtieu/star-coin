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

        [
            {bytes32 collectionRef, bytes32 collectionId},
            {bytes32 collectionRef, bytes32 collectionId},
            {bytes32 collectionRef, bytes32 collectionId}
        ]

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
