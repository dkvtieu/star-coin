/// @title A subset of StarCore that handles minting new StarCoins
/// @author dkvtieu + massive help from the CryptoKitties source code (thank you!)

contract StarMinter is StarOwnership {
    /// @dev we can create promo kittens, up to a limit. Only callable by COO
    /// @param _genes the encoded genes of the kitten to be created, any value is accepted
    /// @param _owner the future owner of the created kittens. Default to contract COO
    function mintNewStar(
        string _name,
        string[] _collectionReferences,
        address _owner
    ) external onlyCOO {
        address starOwner = _owner;
        if (starOwner == address(0)) {
             starOwner = cooAddress;
        }

        _createStar(_name, _collectionReferences, starOwner);
    }
}