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
    uint256 pledgeAmount = 3 ether;

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

    modifier mintAndApproveTokenTransfer(uint256 _amount) {
        mockToken.mint(pledger1, _amount);
        mockToken.mint(pledger2, _amount);

        vm.prank(pledger1);
        mockToken.approve(address(crowdfund), _amount);
        vm.prank(pledger2);
        mockToken.approve(address(crowdfund), _amount);
        _;
    }

    modifier pledgeToCampaign(uint256 _id, uint256 _amount) {
        vm.prank(pledger1);
        vm.warp(startAt);
        crowdfund.pledge(_id, _amount);
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
    function test__pledgeCampaignDoesNotExistReverts()
        public
        mintAndApproveTokenTransfer(pledgeAmount)
    {
        vm.expectRevert("campaign does not exist");
        vm.warp(startAt);
        vm.prank(pledger1);
        crowdfund.pledge(1, pledgeAmount);
        assertEq(mockToken.balanceOf(address(crowdfund)), 0);
        assertEq((crowdfund.getCampaign(1)).pledged, 0);
    }

    function test__pledgeCampaignCancelledReverts()
        public
        launchCampaignsBefore(1)
        mintAndApproveTokenTransfer(pledgeAmount)
    {
        crowdfund.cancel(1);
        assertTrue((crowdfund.getCampaign(1)).cancelled);

        vm.expectRevert("campaign cancelled");
        vm.warp(startAt);
        vm.prank(pledger1);
        crowdfund.pledge(1, pledgeAmount);
        assertEq(mockToken.balanceOf(address(crowdfund)), 0);
        assertEq((crowdfund.getCampaign(1)).pledged, 0);
    }

    function test__pledgeCampaignNotStartedReverts()
        public
        launchCampaignsBefore(1)
        mintAndApproveTokenTransfer(pledgeAmount)
    {
        vm.expectRevert("campaign not started");
        vm.prank(pledger1);
        crowdfund.pledge(1, pledgeAmount);
        assertEq(mockToken.balanceOf(address(crowdfund)), 0);
        assertEq((crowdfund.getCampaign(1)).pledged, 0);
    }

    function test__pledgeCampaignEndedReverts()
        public
        launchCampaignsBefore(1)
        mintAndApproveTokenTransfer(pledgeAmount)
    {
        vm.expectRevert("campaign ended");
        vm.warp(endAt + 100);
        vm.prank(pledger1);
        crowdfund.pledge(1, pledgeAmount);
        assertEq(mockToken.balanceOf(address(crowdfund)), 0);
        assertEq((crowdfund.getCampaign(1)).pledged, 0);
    }

    function test__pledge()
        public
        launchCampaignsBefore(1)
        mintAndApproveTokenTransfer(pledgeAmount)
    {
        vm.warp(startAt);
        vm.prank(pledger1);
        crowdfund.pledge(1, pledgeAmount);
        assertEq(mockToken.balanceOf(address(crowdfund)), pledgeAmount);
        assertEq((crowdfund.getCampaign(1)).pledged, pledgeAmount);
        assertEq((crowdfund.getPledgedAmount(1, pledger1)), pledgeAmount);
    }

    function test__pledgeMultipledCampaigns()
        public
        launchCampaignsBefore(3)
        mintAndApproveTokenTransfer(pledgeAmount * 2)
    {
        vm.warp(startAt);
        vm.prank(pledger1);
        crowdfund.pledge(1, pledgeAmount);
        assertEq(mockToken.balanceOf(address(crowdfund)), pledgeAmount);
        assertEq((crowdfund.getCampaign(1)).pledged, pledgeAmount);
        assertEq((crowdfund.getPledgedAmount(1, pledger1)), pledgeAmount);

        vm.prank(pledger2);
        crowdfund.pledge(2, pledgeAmount);
        assertEq(mockToken.balanceOf(address(crowdfund)), pledgeAmount * 2);
        assertEq((crowdfund.getCampaign(2)).pledged, pledgeAmount);
        assertEq((crowdfund.getPledgedAmount(2, pledger2)), pledgeAmount);

        vm.prank(pledger1);
        crowdfund.pledge(3, pledgeAmount);
        assertEq(mockToken.balanceOf(address(crowdfund)), pledgeAmount * 3);
        assertEq((crowdfund.getCampaign(3)).pledged, pledgeAmount);
        assertEq((crowdfund.getPledgedAmount(3, pledger1)), pledgeAmount);

        vm.prank(pledger2);
        crowdfund.pledge(1, pledgeAmount);
        assertEq(mockToken.balanceOf(address(crowdfund)), pledgeAmount * 4);
        assertEq((crowdfund.getCampaign(1)).pledged, pledgeAmount * 2);
        assertEq((crowdfund.getPledgedAmount(1, pledger2)), pledgeAmount);
    }

    function test__pledgeEvent()
        public
        launchCampaignsBefore(1)
        mintAndApproveTokenTransfer(pledgeAmount)
    {
        vm.warp(startAt);
        vm.prank(pledger1);
        vm.expectEmit(true, true, false, true, address(crowdfund));
        emit Pledged(1, pledger1, pledgeAmount);
        crowdfund.pledge(1, pledgeAmount);
        assertEq((crowdfund.getCampaign(1)).pledged, pledgeAmount);
    }

    /* ========== unpledge ========== */
    function test__unpledgeCampaignDoesNotExistReverts() public {
        vm.expectRevert("campaign does not exist");
        crowdfund.unpledge(1, 1 ether);
    }

    function test__unpledgeCampaignEndedReverts()
        public
        launchCampaignsBefore(1)
        mintAndApproveTokenTransfer(pledgeAmount)
        pledgeToCampaign(1, pledgeAmount)
    {
        vm.expectRevert("campaign ended");
        vm.warp(endAt + 100);
        vm.prank(pledger1);
        crowdfund.unpledge(1, 1 ether);

        assertEq((crowdfund.getCampaign(1)).pledged, pledgeAmount);
        assertEq(crowdfund.getPledgedAmount(1, pledger1), pledgeAmount);
    }

    function test__unpledgeInvalidAmount()
        public
        launchCampaignsBefore(1)
        mintAndApproveTokenTransfer(pledgeAmount)
        pledgeToCampaign(1, pledgeAmount)
    {
        vm.expectRevert("invalid amount");
        vm.prank(pledger1);
        crowdfund.unpledge(1, 0);

        vm.expectRevert("invalid amount");
        vm.prank(pledger1);
        crowdfund.unpledge(1, 8 ether);

        assertEq((crowdfund.getCampaign(1)).pledged, pledgeAmount);
        assertEq(crowdfund.getPledgedAmount(1, pledger1), pledgeAmount);
    }

    function test_unpledge()
        public
        launchCampaignsBefore(1)
        mintAndApproveTokenTransfer(pledgeAmount)
        pledgeToCampaign(1, pledgeAmount)
    {
        vm.prank(pledger1);
        crowdfund.unpledge(1, 1 ether);

        assertEq((crowdfund.getCampaign(1)).pledged, pledgeAmount - 1 ether);
        assertEq(
            crowdfund.getPledgedAmount(1, pledger1),
            pledgeAmount - 1 ether
        );
    }

    function test__unpledgeMultpleCampaign()
        public
        launchCampaignsBefore(3)
        mintAndApproveTokenTransfer(pledgeAmount * 4)
    {
        vm.warp(startAt);
        vm.startPrank(pledger1);
        crowdfund.pledge(1, pledgeAmount);
        crowdfund.pledge(2, pledgeAmount);
        crowdfund.unpledge(1, 1 ether);
        crowdfund.unpledge(2, 1 ether);
        vm.stopPrank();

        vm.startPrank(pledger2);
        crowdfund.pledge(1, pledgeAmount);
        crowdfund.pledge(3, pledgeAmount);
        crowdfund.unpledge(1, 1 ether);
        crowdfund.unpledge(3, 1 ether);
        vm.stopPrank();

        assertEq(
            (crowdfund.getCampaign(1)).pledged,
            (pledgeAmount * 2) - (1 ether * 2)
        );
        assertEq(
            crowdfund.getPledgedAmount(1, pledger1),
            pledgeAmount - 1 ether
        );
        assertEq(
            crowdfund.getPledgedAmount(1, pledger2),
            pledgeAmount - 1 ether
        );
        assertEq((crowdfund.getCampaign(2)).pledged, pledgeAmount - 1 ether);
        assertEq(
            crowdfund.getPledgedAmount(2, pledger1),
            pledgeAmount - 1 ether
        );
        assertEq((crowdfund.getCampaign(3)).pledged, pledgeAmount - 1 ether);
        assertEq(
            crowdfund.getPledgedAmount(3, pledger2),
            pledgeAmount - 1 ether
        );
    }

    function test__unpledgeEvent()
        public
        launchCampaignsBefore(1)
        mintAndApproveTokenTransfer(pledgeAmount)
        pledgeToCampaign(1, pledgeAmount)
    {
        vm.expectEmit(true, true, false, true, address(crowdfund));
        vm.prank(pledger1);
        emit Unpledged(1, pledger1, 1 ether);
        crowdfund.unpledge(1, 1 ether);

        assertEq((crowdfund.getCampaign(1)).pledged, pledgeAmount - 1 ether);
    }

    /* ========== claim ========== */
    function test__claimCampaignDoesNotExistReverts() public {
        vm.expectRevert("campaign does not exist");
        crowdfund.claim(1);
    }

    function test__claimNotCampaignCreatorReverts()
        public
        launchCampaignsBefore(1)
        mintAndApproveTokenTransfer(campaignGoal)
        pledgeToCampaign(1, campaignGoal)
    {
        vm.warp(endAt + 100);
        vm.expectRevert("not creator");
        vm.prank(pledger1);
        crowdfund.claim(1);
    }

    function test__claimCampaignCancelledReverts()
        public
        launchCampaignsBefore(1)
        mintAndApproveTokenTransfer(campaignGoal)
        pledgeToCampaign(1, campaignGoal)
    {
        crowdfund.cancel(1);

        vm.warp(endAt + 100);
        vm.expectRevert("campaign cancelled");
        crowdfund.claim(1);
    }

    function test__claimCampaignNotEnded()
        public
        launchCampaignsBefore(1)
        mintAndApproveTokenTransfer(campaignGoal)
        pledgeToCampaign(1, campaignGoal)
    {
        vm.expectRevert("campaign not ended");
        crowdfund.claim(1);
    }

    function test__claimPledgedLessThanGoalReverts()
        public
        launchCampaignsBefore(1)
        mintAndApproveTokenTransfer(campaignGoal - 2 ether)
        pledgeToCampaign(1, campaignGoal - 2 ether)
    {
        vm.warp(endAt + 100);
        vm.expectRevert("pledged < goal");
        crowdfund.claim(1);
    }

    function test__claim()
        public
        launchCampaignsBefore(1)
        mintAndApproveTokenTransfer(campaignGoal)
        pledgeToCampaign(1, campaignGoal)
    {
        vm.warp(endAt + 100);
        crowdfund.claim(1);

        assertTrue((crowdfund.getCampaign(1)).claimed);
        assertEq(mockToken.balanceOf(address(this)), campaignGoal);
        assertEq(mockToken.balanceOf(address(crowdfund)), 0);
    }

    function test__claimAlreadyClaimedReverts()
        public
        launchCampaignsBefore(1)
        mintAndApproveTokenTransfer(campaignGoal)
        pledgeToCampaign(1, campaignGoal)
    {
        vm.warp(endAt + 100);
        crowdfund.claim(1);
        assertTrue((crowdfund.getCampaign(1)).claimed);

        vm.expectRevert("claimed");
        crowdfund.claim(1);
    }

    function test__claimMultipleCampaigns()
        public
        launchCampaignsBefore(3)
        mintAndApproveTokenTransfer(campaignGoal * 3)
        pledgeToCampaign(1, campaignGoal)
        pledgeToCampaign(2, campaignGoal)
        pledgeToCampaign(3, campaignGoal)
    {
        vm.warp(endAt + 100);
        crowdfund.claim(1);
        crowdfund.claim(2);
        crowdfund.claim(3);

        assertTrue((crowdfund.getCampaign(1)).claimed);
        assertTrue((crowdfund.getCampaign(2)).claimed);
        assertTrue((crowdfund.getCampaign(3)).claimed);
        assertEq(mockToken.balanceOf(address(this)), campaignGoal * 3);
        assertEq(mockToken.balanceOf(address(crowdfund)), 0);
    }

    function test__claimEvent()
        public
        launchCampaignsBefore(1)
        mintAndApproveTokenTransfer(campaignGoal)
        pledgeToCampaign(1, campaignGoal)
    {
        vm.warp(endAt + 100);
        vm.expectEmit(true, false, false, true, address(crowdfund));
        emit Claim(1);
        crowdfund.claim(1);
        assertTrue((crowdfund.getCampaign(1)).claimed);
    }

    /* ========== refund ========== */
    function test__refundCampaignDoesNotExistReverts() public {
        vm.expectRevert("campaign does not exist");
        vm.prank(pledger1);
        crowdfund.refund(1);
    }

    function test__refundCampaignNotEndedReverts()
        public
        launchCampaignsBefore(1)
        mintAndApproveTokenTransfer(pledgeAmount)
        pledgeToCampaign(1, pledgeAmount)
    {
        vm.expectRevert("campaign not ended");
        vm.prank(pledger1);
        crowdfund.refund(1);

        assertEq((crowdfund.getCampaign(1)).pledged, pledgeAmount);
        assertEq((crowdfund.getPledgedAmount(1, pledger1)), pledgeAmount);
        assertEq(mockToken.balanceOf(address(crowdfund)), pledgeAmount);
        assertEq(mockToken.balanceOf(pledger1), 0);
    }

    function test__refundCampaignSuccededReverts()
        public
        launchCampaignsBefore(1)
        mintAndApproveTokenTransfer(campaignGoal)
        pledgeToCampaign(1, campaignGoal)
    {
        vm.warp(endAt + 100);
        vm.prank(pledger1);
        vm.expectRevert("pledged >= goal");
        crowdfund.refund(1);

        assertEq((crowdfund.getCampaign(1)).pledged, campaignGoal);
        assertEq((crowdfund.getPledgedAmount(1, pledger1)), campaignGoal);
        assertEq(mockToken.balanceOf(address(crowdfund)), campaignGoal);
        assertEq(mockToken.balanceOf(pledger1), 0);
    }

    function test__refund()
        public
        launchCampaignsBefore(1)
        mintAndApproveTokenTransfer(pledgeAmount)
        pledgeToCampaign(1, pledgeAmount)
    {
        vm.warp(endAt + 100);
        vm.prank(pledger1);
        crowdfund.refund(1);

        assertEq((crowdfund.getCampaign(1)).pledged, 0);
        assertEq(mockToken.balanceOf(address(crowdfund)), 0);
        assertEq((crowdfund.getPledgedAmount(1, pledger1)), 0);
        assertEq(mockToken.balanceOf(pledger1), pledgeAmount);
    }

    function test__refundAllowsUnpledgeAndRefund()
        public
        launchCampaignsBefore(1)
        mintAndApproveTokenTransfer(campaignGoal)
        pledgeToCampaign(1, campaignGoal)
    {
        vm.prank(pledger1);
        crowdfund.unpledge(1, 1 ether);
        assertEq((crowdfund.getCampaign(1)).pledged, campaignGoal - 1 ether);
        assertEq(
            (crowdfund.getPledgedAmount(1, pledger1)),
            campaignGoal - 1 ether
        );
        assertEq(mockToken.balanceOf(pledger1), 1 ether);

        vm.warp(endAt + 100);
        vm.prank(pledger1);
        crowdfund.refund(1);
        assertEq((crowdfund.getCampaign(1)).pledged, 0);
        assertEq((crowdfund.getPledgedAmount(1, pledger1)), 0);
        assertEq(mockToken.balanceOf(address(crowdfund)), 0);
        assertEq(mockToken.balanceOf(pledger1), campaignGoal);
    }

    function test__refundMultpleCampaigns()
        public
        launchCampaignsBefore(3)
        mintAndApproveTokenTransfer(pledgeAmount * 3)
        pledgeToCampaign(1, pledgeAmount)
        pledgeToCampaign(2, pledgeAmount)
    {
        vm.prank(pledger2);
        crowdfund.pledge(3, pledgeAmount);

        vm.warp(endAt + 100);
        vm.startPrank(pledger1);
        crowdfund.refund(1);
        crowdfund.refund(2);
        vm.stopPrank();
        vm.prank(pledger2);
        crowdfund.refund(3);

        assertEq((crowdfund.getCampaign(1)).pledged, 0);
        assertEq((crowdfund.getCampaign(2)).pledged, 0);
        assertEq((crowdfund.getCampaign(3)).pledged, 0);
        assertEq((crowdfund.getPledgedAmount(1, pledger1)), 0);
        assertEq((crowdfund.getPledgedAmount(2, pledger1)), 0);
        assertEq((crowdfund.getPledgedAmount(3, pledger2)), 0);
        assertEq(mockToken.balanceOf(address(crowdfund)), 0);
        assertEq(mockToken.balanceOf(pledger1), pledgeAmount * 3);
        assertEq(mockToken.balanceOf(pledger2), pledgeAmount * 3);
    }

    function test__refundEvent()
        public
        launchCampaignsBefore(1)
        mintAndApproveTokenTransfer(pledgeAmount)
        pledgeToCampaign(1, pledgeAmount)
    {
        vm.warp(endAt + 100);
        vm.expectEmit(true, true, false, true, address(crowdfund));
        vm.prank(pledger1);
        emit Refund(1, pledger1, pledgeAmount);
        crowdfund.refund(1);
        assertEq((crowdfund.getCampaign(1)).pledged, 0);
        assertEq(mockToken.balanceOf(pledger1), pledgeAmount);
    }
}
