// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title  MockVenue — a stand-in for a real trading venue
/// @notice Accepts USDC via receive(), can send back arbitrary amounts via
///         `returnFunds`. Used in tests + the hackathon demo as a placeholder
///         for Hyperliquid / Aster / GMX / etc. Production integrations would
///         replace this with a wrapper that interacts with the real venue.
contract MockVenue {
    address public immutable owner;

    event FundsReceived(address indexed from, uint256 amount);
    event FundsReturned(address indexed to, uint256 amount);

    constructor() {
        owner = msg.sender;
    }

    receive() external payable {
        emit FundsReceived(msg.sender, msg.value);
    }

    /// @notice Push USDC back to a Plinth vault contract.
    /// @dev    Anyone can call (in production, the venue's settlement logic
    ///         would trigger this; in tests we call directly to simulate the
    ///         agent winning/losing positions and pulling settlement).
    function returnFunds(address payable plinth, uint256 amount) external {
        emit FundsReturned(plinth, amount);
        (bool ok,) = plinth.call{value: amount}("");
        require(ok, "send back failed");
    }

    /// @notice Helper: forward a `returnFromVenue` call from the venue back
    ///         to the Plinth contract.  In production this would be the
    ///         agent triggering settlement after closing a position.
    function returnFromVenueOf(
        address payable plinth,
        bytes32 vaultId,
        uint256 amount,
        bytes4 selector
    ) external {
        (bool ok,) = plinth.call{value: amount}(
            abi.encodeWithSelector(selector, vaultId, address(this), amount)
        );
        require(ok, "venue-to-vault return failed");
    }
}
