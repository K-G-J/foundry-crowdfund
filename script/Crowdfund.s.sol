// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/Crowdfund.sol";
import "../src/IERC20.sol";

uint256 constant MIN_DURATION = 1 days;
uint256 constant MAX_DURATION = 30 days;
address constant WETH_TOKEN = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

contract CrowdfundDeployScript is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        Crowdfund crowdfund = new Crowdfund();
        crowdfund.initialize(IERC20(WETH_TOKEN), MIN_DURATION, MAX_DURATION);
        vm.stopBroadcast();
    }
}
