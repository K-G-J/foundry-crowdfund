// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Crowdfund.sol";
import "../src/MockToken.sol";
import "../src/IERC20.sol";

// forge test --match-contract CrowdfundTest

contract CrowdfundTest is Test {
    /* ========== STATE VARIABLES ========== */
    MockToken public mockToken;
    Crowdfund public crowdfund;
    address launcher = address(0x123);
    address pledger1 = address(0x456);
    address pledger2 = address(0x789);

    /* ========== CROWDFUND EVENTS ========== */
    event Launch(
        uint256 indexed id,
        address indexed creator,
        uint256 goal,
        uint32 startAt,
        uint32 endAt
    );
    event Cancel(uint256 indexed id);
    event Pledged(uint256 indexed id, address indexed caller, uint256 amount);
    event Unpledged(uint256 indexed id, address indexed caller, uint256 amount);
    event Claim(uint256 indexed id);
    event Refund(uint256 indexed id, address indexed caller, uint256 amount);

    function setUp() public {
        mockToken = new MockToken();
        crowdfund = new Crowdfund();
        crowdfund.initialize(IERC20(address(mockToken)), 1 days, 20 days);

        vm.label(address(crowdfund), "Crowdfund");
        vm.label(address(mockToken), "MockToken");
        vm.label(launcher, "Launcher");
        vm.label(pledger1, "Pledger1");
        vm.label(pledger2, "Pledger2");
    }

    function test__setUp() public {
        assertEq(address(crowdfund.token()), address(mockToken));
        assertEq(crowdfund.minDuration(), 1 days);
        assertEq(crowdfund.maxDuration(), 20 days);
    }
}
