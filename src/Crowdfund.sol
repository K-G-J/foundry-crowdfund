// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract Crowdfund is Initializable {
    /* ========== STATE VARIABLES ========== */

    /**
     * @dev struct containing information about each crowdfunding campaign
     * @member id - unique number identifying each campaign
     * @member creator - the address of the person launching the campaign
     * @member goal - the amount of tokens the campaign aims to reach
     * @member pledged - the amount of tokens currently pledged to the campaign
     * @member startAt - the block.timestamp at which the campaign will begin
     * @member endAt - the block.timestamp at which the campaign will be over (must be less than 90 days from when th creator calls the function to launch the campaign)
     * @member claimed - whether or not the crowdfunded tokens for the campaign have been claimed
     * @member cancelled - whether or not the creator has cancelled the campaign
     */

    struct Campaign {
        uint256 id;
        address creator;
        uint256 goal;
        uint256 pledged;
        uint32 startAt;
        uint32 endAt;
        bool claimed;
        bool cancelled;
    }
    /**
     * @dev custom ERC20 which funds take the form of
     * Set in initalize function
     */
    using SafeERC20 for IERC20;
    IERC20 public token;

    /**
     * @dev maximum and minimum length of times a campaign can be
     * Set in initalize function
     */
    uint256 public maxDuration;

    uint256 public minDuration;
    /**
     * @dev used to track and update unique campaign ids
     */
    uint256 public count;
    /**
     * @dev mapping of id to Campaign struct
     */
    mapping(uint256 => Campaign) public campaigns;
    /**
     * @dev mapping of campaign id to pledger to amount pledged
     */
    mapping(uint256 => mapping(address => uint256)) public pledgedAmount;

    /* ========== EVENTS ========== */
    /**
     * dApps using the contract can observe state changes in transaction logs
     */
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

    /* ========== MODIFIERS ========== */

    modifier campaignExists(uint256 _id) {
        require(campaigns[_id].id != 0, "campaign does not exist");
        _;
    }

    modifier notCancelled(uint256 _id) {
        require(!campaigns[_id].cancelled, "campaign cancelled");
        _;
    }

    modifier onlyCreator(uint256 _id) {
        require(campaigns[_id].creator == msg.sender, "not creator");
        _;
    }

    modifier campaignStarted(uint256 _id) {
        require(
            block.timestamp >= campaigns[_id].startAt,
            "campaign not started"
        );
        _;
    }

    modifier campaignNotEnded(uint256 _id) {
        require(block.timestamp <= campaigns[_id].endAt, "campaign ended");
        _;
    }

    modifier campaignEnded(uint256 _id) {
        require(block.timestamp > campaigns[_id].endAt, "campaign not ended");
        _;
    }

    /* ========== INITIALIZER ========== */

    /**
     * @dev dunction from @openzeppelin to initialize this as the base contract for upgrades
     * @dev must be the first function called
     */

    function initialize(
        IERC20 _token,
        uint256 _minDuration,
        uint256 _maxDuration
    ) public initializer {
        require(_minDuration < _maxDuration, "minDuration > maxDuration");
        token = _token;
        minDuration = _minDuration;
        maxDuration = _maxDuration;
    }

    /* ========== EXTERNAL FUNCTIONS ========== */

    /**
     * @dev function called by campaign creator to create the crowdfunding campaign and add Campaign to mapping
     * @param _goal - the amount of tokens the campaign aims to receive
     * @param _startAt - the time the campaign will begin (note: _startAt time is passed in by creator and not necessarily the time the creator calls the launch function)
     * @param _endAt - the block.timestamp at which the campaign will end (note: must be >= starting time + minDuration and <= starting time + maxDuration)
     */

    function launch(uint256 _goal, uint32 _startAt, uint32 _endAt) external {
        require(_startAt >= block.timestamp, "start at < now");
        require(
            _endAt >= _startAt + minDuration &&
                _endAt <= _startAt + maxDuration,
            "not in min & max duration"
        );

        count += 1;
        campaigns[count] = Campaign({
            id: count,
            creator: msg.sender,
            goal: _goal,
            pledged: 0,
            startAt: _startAt,
            endAt: _endAt,
            claimed: false,
            cancelled: false
        });

        emit Launch(count, msg.sender, _goal, _startAt, _endAt);
    }

    /**
     * @dev function called by campaign creator to cancel a crowdfunding campaign
     * @param _id - the uinique uint256 id of the campaign to be cancelled
     */
    function cancel(
        uint256 _id
    ) external campaignExists(_id) onlyCreator(_id) notCancelled(_id) {
        campaigns[_id].cancelled = true;

        emit Cancel(_id);
    }

    /**
     * @dev function to transfer tokens from pledger into the contract
     * @dev sender must first call approve on the ERC20 token for this contract address and _amount
     * @dev campaign must not be cancelled, must be within startAt and endAt times
     * @param _id - the uinique uint256 id of the campaign to be pledged
     * @param _amount - the amount of tokens trasferred from pledger into contract
     */
    function pledge(
        uint256 _id,
        uint256 _amount
    )
        external
        campaignExists(_id)
        notCancelled(_id)
        campaignStarted(_id)
        campaignNotEnded(_id)
    {
        Campaign storage campaign = campaigns[_id];

        campaign.pledged += _amount;
        pledgedAmount[_id][msg.sender] += _amount;
        token.safeTransferFrom(msg.sender, address(this), _amount);

        emit Pledged(_id, msg.sender, _amount);
    }

    /**
     * @dev function for pledger to unpledge their tokens and receive them back BEFORE a campaign has ended (ex: unpledge if campaign cancelled before end time)
     * @dev pledger specifies amount of tokens to unpledge, if a campaign has ended and not met goal, pledger then calls refund function to receive all tokens back
     * @param _id - the uinique uint256 id of the campaign to be unpledged
     * @param _amount - the amount of tokens transferred from contract back to pledger
     */
    function unpledge(
        uint256 _id,
        uint256 _amount
    ) external campaignExists(_id) campaignNotEnded(_id) {
        _refund(msg.sender, _id, _amount);

        emit Unpledged(_id, msg.sender, _amount);
    }

    /**
     * @dev function called by campaign creator to receive funds
     * @dev caller must be creator, creator cannot have cancelled the campaign, campaign must have passed end at time, the campaign goal must have been met or exceeded
     * @dev this function can only be called once by creator
     * @param _id - the uinique uint256 id of the campaign which funds are claimed
     */
    function claim(
        uint256 _id
    )
        external
        campaignExists(_id)
        onlyCreator(_id)
        notCancelled(_id)
        campaignEnded(_id)
    {
        Campaign storage campaign = campaigns[_id];

        require(!campaign.claimed, "claimed");
        require(campaign.pledged >= campaign.goal, "pledged < goal");

        campaign.claimed = true;

        token.safeIncreaseAllowance(msg.sender, campaign.pledged);
        token.safeTransfer(msg.sender, campaign.pledged);

        emit Claim(_id);
    }

    /**
     * @dev function to refund ALL the pledged tokens from pledger in this contract back to the pledger AFTER a campaign has ended and failed
     * @dev when a funding goal is not met, pledgers are be able to get a refund of their pledged funds
     * @param _id - the uinique uint256 id of the campaign to refund from
     */
    function refund(
        uint256 _id
    ) external campaignExists(_id) campaignEnded(_id) {
        Campaign storage campaign = campaigns[_id];

        require(campaign.pledged < campaign.goal, "pledged >= goal");

        uint256 _bal = pledgedAmount[_id][msg.sender];
        _refund(msg.sender, _id, _bal);

        emit Refund(_id, msg.sender, _bal);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /**
     * @dev internal function to safeTransfer tokens from this contract back to a pledger
     * @param _donor - the address of the pledger receiving the refund
     * @param _id - the uinique uint256 id of the campaign being refunded from
     * @param _amount - the amount of tokens transferred from contract back to pledger
     */
    function _refund(address _donor, uint256 _id, uint256 _amount) private {
        require(
            _amount > 0 && _amount <= pledgedAmount[_id][_donor],
            "invalid amount"
        );

        pledgedAmount[_id][_donor] -= _amount;
        campaigns[_id].pledged -= _amount;

        token.safeIncreaseAllowance(_donor, _amount);
        token.safeTransfer(_donor, _amount);
    }
}
