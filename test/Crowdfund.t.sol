// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Crowdfund.sol";

contract CounterTest is Test {
    Crowdfund public crowdfund;

    function setUp() public {
        crowdfund = new Crowdfund();
    }

    function test_assertTrue() public {
        assertTrue(true);
    }
}
