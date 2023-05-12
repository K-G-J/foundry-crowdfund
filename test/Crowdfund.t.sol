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
    address pledger1 = address(0x123);
    address pledger2 = address(0x456);
    uint256 campaignGoal = 5 ether;
    uint32 startAt = 2 days;
    uint32 endAt = 5 days;

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
        vm.label(address(this), "Launcher");
        vm.label(pledger1, "Pledger1");
        vm.label(pledger2, "Pledger2");
    }

    /* ========== MODIFIERS ========== */
    modifier launchCampaignsBefore(uint256 _numCampaings) {
        launchCampaigns(_numCampaings);
        _;
    }

    /* ========== HELPER FUNCTIONS ========== */

    function launchCampaigns(uint256 _numCampaigns) public {
        for (uint256 i = 1; i <= _numCampaigns; i++) {
            crowdfund.launch(campaignGoal, startAt, endAt);
            assertEq((crowdfund.getCampaign(i)).id, i);
        }
    }

    /* ========== initialize ========== */
    function test__initializeAgainReverts() public {
        vm.expectRevert("Initializable: contract is already initialized");
        crowdfund.initialize(IERC20(address(mockToken)), 1 days, 20 days);
    }

    function test__initialize() public {
        assertEq(address(crowdfund.token()), address(mockToken));
        assertEq(crowdfund.minDuration(), 1 days);
        assertEq(crowdfund.maxDuration(), 20 days);
    }

    /* ========== launch ========== */
    function test__launchInvalidStartAtReverts() public {
        uint32 invalidStartTime = uint32(0);
        vm.expectRevert("start at < now");
        crowdfund.launch(campaignGoal, invalidStartTime, endAt);
    }

    function test__launchCampaignTooShortReverts() public {
        uint32 invalidEndTime = uint32(startAt + 10);
        vm.expectRevert("not in min & max duration");
        crowdfund.launch(campaignGoal, startAt, invalidEndTime);
    }

    function test__launchCampaignTooLongReverts() public {
        uint32 invalidEndTime = uint32(startAt + 30 days);
        vm.expectRevert("not in min & max duration");
        crowdfund.launch(campaignGoal, startAt, invalidEndTime);
    }

    function test__launch() public {
        crowdfund.launch(campaignGoal, startAt, endAt);
        Crowdfund.Campaign memory campaign = crowdfund.getCampaign(1);
        assertEq(campaign.id, 1);
        assertEq(campaign.creator, address(this));
        assertEq(campaign.goal, campaignGoal);
        assertEq(campaign.pledged, 0);
        assertEq(campaign.startAt, startAt);
        assertEq(campaign.endAt, endAt);
        assertEq(campaign.claimed, false);
        assertEq(campaign.cancelled, false);
    }

    function test__launchEvent() public {
        vm.expectEmit(true, true, false, true, address(crowdfund));
        emit Launch(1, address(this), campaignGoal, startAt, endAt);
        crowdfund.launch(campaignGoal, startAt, endAt);
        Crowdfund.Campaign memory campaign = crowdfund.getCampaign(1);
        assertEq(campaign.id, 1);
    }

    /* ========== cancel ========== */
    function test__cancelCampaignDoesNotExistReverts()
        public
        launchCampaignsBefore(1)
    {
        vm.expectRevert("campaign does not exist");
        crowdfund.cancel(2);
        assertFalse((crowdfund.getCampaign(1)).cancelled);
    }

    function test__cancelNotCampaignCreatorReverts()
        public
        launchCampaignsBefore(1)
    {
        vm.prank(pledger1);
        vm.expectRevert("not creator");
        crowdfund.cancel(1);
        assertFalse((crowdfund.getCampaign(1)).cancelled);
    }

    function test__cancel() public launchCampaignsBefore(1) {
        crowdfund.cancel(1);
        assertTrue((crowdfund.getCampaign(1)).cancelled);
    }

    function test__cancelMultpleCampaigns() public launchCampaignsBefore(3) {
        crowdfund.cancel(1);
        assertTrue((crowdfund.getCampaign(1)).cancelled);
        crowdfund.cancel(2);
        assertTrue((crowdfund.getCampaign(2)).cancelled);
        crowdfund.cancel(3);
        assertTrue((crowdfund.getCampaign(3)).cancelled);
    }

    function test__cancelAlreadyCancelledReverts()
        public
        launchCampaignsBefore(1)
    {
        crowdfund.cancel(1);
        assertTrue((crowdfund.getCampaign(1)).cancelled);
        vm.expectRevert("campaign cancelled");
        crowdfund.cancel(1);
    }

    function test__cancelEvent() public launchCampaignsBefore(1) {
        vm.expectEmit(true, false, false, true, address(crowdfund));
        emit Cancel(1);
        crowdfund.cancel(1);
        assertTrue((crowdfund.getCampaign(1)).cancelled);
    }

    /* ========== pledge ========== */
    function test__pledgeCampaignDoesNotExistReverts() public {}

    function test__pledgeCampaignCancelledReverts() public {}

    function test__pledgeCampaignNotStartedReverts() public {}

    function test__pledgeCampaignEndedReverts() public {}

    function test__pledge() public {}

    function test__pledgeMultipledCampaigns() public {}

    function test__pledgeEvent() public {}

    /* ========== unpledge ========== */
    function test__unpledgeCampaignDoesNotExistReverts() public {}

    function test__unpledgeCampaignNotStartedReverts() public {}

    function test__unpledgeCampaignEndedReverts() public {}

    function test__unpledgeInvalidAmount() public {}

    function test_unpledge() public {}

    function test__unpledgeMultpleCampaign() public {}

    function test__unpledgeEvent() public {}

    /* ========== claim ========== */
    function test__claimCampaignDoesNotExistReverts() public {}

    function test__claimNotCampaignCreatorReverts() public {}

    function test__claimCampaignCancelledReverts() public {}

    function test__claimPledgedLessThanGoalReverts() public {}

    function test__claim() public {}

    function test__claimAlreadyClaimedReverts() public {}

    function test__claimMultipleCampaigns() public {}

    function test__claimEvent() public {}

    /* ========== refund ========== */
    function test__refundCampaignDoesNotExistReverts() public {}

    function test__refundCampaignNotEndedReverts() public {}

    function test__refundCampaignSuccededReverts() public {}

    function test__refund() public {}

    function test__refundAllowsUnpledgeAndRefund() public {}

    function test__refundMultpleCampaigns() public {}

    function test__refundEvent() public {}
}
