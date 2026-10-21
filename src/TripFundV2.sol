// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TripFund} from "./TripFund.sol";

/// @custom:oz-upgrades-from TripFund.sol:TripFund
contract TripFundV2 is TripFund {
    function contributeFor(address beneficiary, uint256 amount) external {
        _contribute(msg.sender, beneficiary, amount);
    }
}
