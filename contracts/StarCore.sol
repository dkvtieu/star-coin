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

    /// @notice Returns all the relevant information about a specific kitty.
    /// @param _starId The ID of the kitty of interest.
    function getStar(uint256 _starId)
        external
        view
        returns (
        string name,
        string[] collectionReferences,
        uint64 creationTime
    ) {
        Star storage star = stars[_starId];

        name = star.name;
        collectionReferences = star.collectionReferences;
        creationTime = uint256(star.creationTime);
    }

    /// @dev Override unpause so it requires all external contract addresses
    ///  to be set before contract can be unpaused. Also, we can't have
    ///  newContractAddress set either, because then the contract was upgraded.
    /// @notice This is public rather than external so we can call super.unpause
    ///  without using an expensive CALL.
    function unpause() public onlyCEO whenPaused {
        // require(saleAuction != address(0));
        require(newContractAddress == address(0));

        // Actually unpause the contract.
        super.unpause();
    }

    // @dev Allows the CFO to capture the balance available to the contract.
    function withdrawBalance() external onlyCFO {
        cfoAddress.send(this.balance);
    }
}