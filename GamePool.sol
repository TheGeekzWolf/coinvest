// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./InvestPool.sol";
import "./GeekzPass.sol";

contract GamePool is Ownable, ReentrancyGuard {
    event InvestPoolCreated(
        address indexed investPoolAddress,
        uint256 indexed gameId,
        uint256 indexed poolNum
    );
    event ClaimStatusChanged(uint256 indexed gameId, bool claimable);
    event PoolClosed(uint256 indexed gameId, uint256 indexed poolNum);

    string public gameName;
    uint public gameId;
    uint public totalPool;
    uint availableForDeployment; // available token for game deployment

    address public tokenAddress;
    address public receiverAddress;
    address public geekzPassAddress;
    address public treasuryAddress;
    address public scholarRewardAddress;
    address public reinvestAddress;

    uint public poolCounter = 0;
    bool public claimable;
    mapping(uint => uint) nftLastClaimedWeek;
    mapping(uint => uint) nftTotalClaimed;
    mapping(address => bool) rewardInjector;

    uint constant PERCENT_DIVIDER = 100;
    uint public rewardBalance;
    uint public collectedTreasuryPercent = 3;
    uint public rewardTreasuryPercent = 20;
    uint public rewardScholarPercent = 20;
    uint public rewardInvestorsPercent = 60;
    uint public rewardReinvestPercent = 0;

    InvestPool[] public investPools;
    mapping(address => bool) isInvestPool;

    struct RewardLog {
        uint weekNum;
        uint amount;
        uint currentPoolSize;
    }

    struct PoolData {
        uint poolId;
        mapping(address => uint) investments;
        uint rewardCount;
        uint closedTime;
        uint amount;
    }

    mapping(uint256 => RewardLog) public rewardLogs;
    mapping(uint256 => PoolData) public investData;

    uint256 public rewardCounter = 0;

    modifier geekzPassSetted() {
        require(geekzPassAddress != address(0), "geekzPassAddress not set");
        _;
    }

    modifier byInvestPool() {
        require(isInvestPool[msg.sender], "Not From Invest Pool");
        _;
    }

    constructor(
        string memory _gameName,
        uint _gameId,
        address _tokenAddress,
        address _receiverAddress,
        address _treasuryAddress,
        address _scholarAddress,
        address _reinvestAddress
    ) {
        require(_tokenAddress != address(0), "Token address shouldn't 0");
        rewardInjector[msg.sender] = true;
        gameName = _gameName;
        gameId = _gameId;
        receiverAddress = _receiverAddress;
        treasuryAddress = _treasuryAddress;
        tokenAddress = _tokenAddress;
        scholarRewardAddress = _scholarAddress;
        reinvestAddress = _reinvestAddress;
    }

    function createPool(
        uint _poolStart,
        uint _poolEnd,
        uint _poolHardcap,
        uint _minInvest
    ) external onlyOwner geekzPassSetted {
        poolCounter += 1;
        InvestPool newPool = new InvestPool(
            address(this),
            poolCounter,
            address(this),
            tokenAddress,
            geekzPassAddress,
            gameName,
            gameId,
            _poolStart,
            _poolEnd,
            _poolHardcap,
            _minInvest
        );
        newPool.setReceiverAddress(receiverAddress);
        newPool.setGeekzPass(geekzPassAddress);
        newPool.transferOwnership(owner());
        investPools.push(newPool);
        isInvestPool[address(newPool)] = true;

        emit InvestPoolCreated(address(newPool), gameId, poolCounter);
    }

    function returnAllPools() external view returns (InvestPool[] memory) {
        return investPools;
    }

    function getAvailableTokenForDeployment()
        external
        view
        onlyOwner
        returns (uint)
    {
        return availableForDeployment;
    }

    function getAllPoolStatus()
        external
        view
        returns (uint[] memory, uint[] memory)
    {
        uint[] memory p = new uint[](investPools.length);
        uint[] memory r = new uint[](investPools.length);

        for (uint i = 0; i < investPools.length; i++) {
            InvestPool ip = InvestPool(investPools[i]);
            p[i] = uint(ip.poolNum());
            r[i] = uint(ip.status());
        }
        return (p, r);
    }

    function setGeekzPass(address _geekzPassAddress) external onlyOwner {
        geekzPassAddress = _geekzPassAddress;
    }

    function setCollectedTreasuryPercent(uint _collectedTreasuryPercent)
        external
        onlyOwner
    {
        collectedTreasuryPercent = _collectedTreasuryPercent;
    }

    function setScholarRewardAddress(address _scholarRewardAddress)
        external
        onlyOwner
    {
        scholarRewardAddress = _scholarRewardAddress;
    }

    function setReinvestAddress(address _reinvestAddress) external onlyOwner {
        reinvestAddress = _reinvestAddress;
    }

    function setTreasuryAddress(address _treasuryAddress) external onlyOwner {
        treasuryAddress = _treasuryAddress;
    }

    function setRewardInjector(address _injector, bool _status)
        external
        onlyOwner
    {
        rewardInjector[_injector] = _status;
    }

    function setRewardShare(
        uint _rewardTreasuryPercent,
        uint _rewardScholarPercent,
        uint _rewardReinvestPercent,
        uint _rewardInvestorsPercent
    ) external onlyOwner {
        require(
            _rewardInvestorsPercent >= 50,
            "Investor Reward should be more than 50%"
        );
        require(
            _rewardTreasuryPercent +
                _rewardScholarPercent +
                _rewardInvestorsPercent +
                _rewardReinvestPercent ==
                100,
            "Not 100%"
        );
        rewardTreasuryPercent = _rewardTreasuryPercent;
        rewardScholarPercent = _rewardScholarPercent;
        rewardReinvestPercent = _rewardReinvestPercent;
        rewardInvestorsPercent = _rewardInvestorsPercent;
    }

    function setReceiverAddress(address _receiverAddress) external onlyOwner {
        receiverAddress = _receiverAddress;
    }

    // called by investpool on finalize
    function deployPool(
        uint _investPoolId,
        uint _investedAmount,
        uint _gameId,
        address[] calldata _investors,
        uint[] calldata _investments
    ) external byInvestPool {
        totalPool += _investedAmount;

        // fee for Treasury
        // uint toTreasury = (collectedTreasuryPercent * _investedAmount) /
        //     PERCENT_DIVIDER;

        // transfer to Treasury
        // IERC20 token = IERC20(tokenAddress);
        // token.transfer(treasuryAddress, toTreasury);

        // Amount for withdrawal to gamerWallet
        // uint forDeployment = _investedAmount - toTreasury;
        // availableForDeployment += forDeployment;

        availableForDeployment += _investedAmount;

        // send data to geekzpass
        GeekzPass _geekzPass = GeekzPass(geekzPassAddress);
        _geekzPass.setGeekzPassData(
            _gameId,
            _investPoolId,
            _investors,
            _investments
        );

        // Save pool data
        PoolData storage poolData = investData[_investPoolId];
        poolData.poolId = _investPoolId;
        poolData.closedTime = block.timestamp;
        poolData.amount = _investedAmount;

        // to store information of reciving reward for geekzpass late minting
        poolData.rewardCount = rewardCounter;

        for (uint i; i < _investors.length; i++) {
            poolData.investments[_investors[i]] += _investments[i];
        }

        emit PoolClosed(gameId, _investPoolId);
    }

    // To initialize last claimed reward
    // based on what the reward whe the pool is created
    function setNftClaimed(uint _tokenId, uint _poolNum) external byInvestPool {
        nftLastClaimedWeek[_tokenId] = investData[_poolNum].rewardCount;
    }

    function getNftClaimedCounter(uint _tokenId)
        external
        view
        byInvestPool
        returns (uint)
    {
        return nftLastClaimedWeek[_tokenId];
    }

    // Input/fill Reward token to GamePool for automatic distribute to
    // treasury, scholar, reinvest
    // while for investor they need to claim manually
    function fillReward(uint _amount, uint _weekNum) public {
        require(rewardInjector[msg.sender], "Not the reward injector");
        require(tokenAddress != address(0), "Token should set");
        require(treasuryAddress != address(0), "Treasury should set");
        require(scholarRewardAddress != address(0), "Scholar should set");
        require(reinvestAddress != address(0), "Reinvest should set");
        require(_amount > 0, "Amount more than 0");

        // share for treasury, scholar, reinvest, investor
        uint toTreasury = (rewardTreasuryPercent * _amount) / PERCENT_DIVIDER;
        uint toScholar = (rewardScholarPercent * _amount) / PERCENT_DIVIDER;
        uint toReinvest = (rewardReinvestPercent * _amount) / PERCENT_DIVIDER;
        uint toInvestors = (rewardInvestorsPercent * _amount) / PERCENT_DIVIDER;
        rewardBalance += toInvestors;

        RewardLog storage rewardDetail = rewardLogs[rewardCounter];
        rewardDetail.weekNum = _weekNum;
        rewardDetail.amount = toInvestors;
        rewardDetail.currentPoolSize = totalPool;
        rewardCounter += 1;

        IERC20 token = IERC20(tokenAddress);
        token.transferFrom(msg.sender, address(this), _amount);

        token.transfer(treasuryAddress, toTreasury);
        token.transfer(scholarRewardAddress, toScholar);
        if (toReinvest > 0) token.transfer(reinvestAddress, toReinvest);
    }

    function getRewardByCounter(uint _counter)
        external
        view
        returns (uint, uint)
    {
        return (
            rewardLogs[_counter].amount,
            rewardLogs[_counter].currentPoolSize
        );
    }

    function claimRewardStatus(bool _claimable) external onlyOwner {
        claimable = _claimable;

        emit ClaimStatusChanged(gameId, claimable);
    }

    // withdraw to game wallet for buying assets, etc
    function deployTokenToGame(uint _amount, address _receiverAddress)
        external
        onlyOwner
    {
        require(availableForDeployment >= _amount, "Not enough for deployment");

        IERC20 token = IERC20(tokenAddress);
        token.transfer(_receiverAddress, _amount);
        availableForDeployment -= _amount;
    }

    function clearStuckBalance() external onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    // to fetch real investorData, use NFT they're currently holding, not by invest addr
    // the investData investments state var only applicable for minting usage.
    function getInvestorData()
        public
        view
        returns (uint[] memory, uint[] memory)
    {
        uint[] memory poolId = new uint[](poolCounter - 1);
        uint[] memory amounts = new uint[](poolCounter - 1);

        // first poolId is 1, not 0. thus removing first 0 array of investData
        uint counter = 0;
        for (uint i = 1; i < poolCounter; i++) {
            poolId[counter] = investData[i].poolId;
            amounts[counter] = investData[i].investments[msg.sender];
            counter++;
        }

        return (poolId, amounts);
    }

    function getAllPoolData()
        public
        view
        returns (
            uint[] memory,
            uint[] memory,
            uint[] memory
        )
    {
        uint[] memory poolId = new uint[](poolCounter - 1);
        uint[] memory amounts = new uint[](poolCounter - 1);
        uint[] memory closedTime = new uint[](poolCounter - 1);

        // first poolId is 1, not 0. thus removing first 0 array of investData
        uint counter = 0;
        for (uint i = 1; i < poolCounter; i++) {
            poolId[counter] = investData[i].poolId;
            amounts[counter] = investData[i].amount;
            closedTime[counter] = investData[i].closedTime;
            counter++;
        }

        return (poolId, amounts, closedTime);
    }

    // Get total claimed Reward
    function getTotalClaimed()
        public
        view
        geekzPassSetted
        returns (uint alreadyClaimed)
    {
        address investor = msg.sender;
        GeekzPass _geekzPass = GeekzPass(geekzPassAddress);
        uint totalNFT = _geekzPass.balanceOf(investor);
        for (uint i = 0; i < totalNFT; i++) {
            uint tokenId = _geekzPass.tokenOfOwnerByIndex(investor, i);
            alreadyClaimed += nftTotalClaimed[tokenId];
        }
    }

    // Get unclaimed reward & total invested
    function getUnclaimed()
        public
        view
        geekzPassSetted
        returns (uint unclaimed, uint investorAmount)
    {
        address investor = msg.sender;
        GeekzPass _geekzPass = GeekzPass(geekzPassAddress);
        uint totalNFT = _geekzPass.balanceOf(investor);

        for (uint i = 0; i < totalNFT; i++) {
            uint tokenId = _geekzPass.tokenOfOwnerByIndex(investor, i);
            uint _amount = _geekzPass.getTokenInvestAmount(tokenId);
            investorAmount += _amount;

            for (uint j = nftLastClaimedWeek[tokenId]; j < rewardCounter; j++) {
                unclaimed +=
                    (_amount * rewardLogs[j].amount) /
                    rewardLogs[j].currentPoolSize;
            }
        }
    }

    // claim all unclaimed reward
    function claimAll() public nonReentrant geekzPassSetted returns (uint) {
        require(claimable, "Not Claimable");
        GeekzPass _geekzPass = GeekzPass(geekzPassAddress);
        uint totalNFT = _geekzPass.balanceOf(msg.sender);
        require(totalNFT > 0, "Not holding any GeekzPass");

        uint unclaimed = 0;

        for (uint i = 0; i < totalNFT; i++) {
            uint tokenId = _geekzPass.tokenOfOwnerByIndex(msg.sender, i);
            uint _amount = _geekzPass.getTokenInvestAmount(tokenId);

            for (uint j = nftLastClaimedWeek[tokenId]; j < rewardCounter; j++) {
                uint _reward = (_amount * rewardLogs[j].amount) /
                    rewardLogs[j].currentPoolSize;
                nftTotalClaimed[tokenId] += _reward;
                unclaimed += _reward;
            }

            // guard
            nftLastClaimedWeek[tokenId] = rewardCounter;
        }

        IERC20 token = IERC20(tokenAddress);
        token.transfer(msg.sender, unclaimed);

        return unclaimed;
    }
}
