// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./GeekzPass.sol";
import "./GamePool.sol";

contract InvestPool is Ownable {
    event PoolStatusChanged(
        uint256 indexed gameId,
        uint256 indexed poolNum,
        PoolStatus status
    );

    address public tokenAddress;
    address public geekzPassAddress;
    address public gamePoolAddress;
    address public receiverAddress;
    uint public poolNum;
    string public poolGame;
    uint public poolGameId;
    uint public poolStart;
    uint public poolEnd;
    uint public poolHardcap;
    uint public minInvest;
    uint public total;

    address[] public investors;
    mapping(address => uint256) private balances;
    mapping(address => bool) minted;

    enum PoolStatus {
        DRAFT,
        OPEN,
        CLOSED,
        DEPLOYED,
        CANCEL
    }
    PoolStatus public status;

    constructor(
        address _ownerAddress,
        uint _poolNum,
        address _gamePoolAddress,
        address _tokenAddress,
        address _geekzPassAddress,
        string memory _poolGame,
        uint _gameId,
        uint _poolStart,
        uint _poolEnd,
        uint _poolHardcap,
        uint _minInvest
    ) {
        transferOwnership(_ownerAddress);
        poolNum = _poolNum;
        gamePoolAddress = _gamePoolAddress;
        tokenAddress = _tokenAddress;
        geekzPassAddress = _geekzPassAddress;
        poolGame = _poolGame;
        poolGameId = _gameId;
        poolStart = _poolStart;
        poolEnd = _poolEnd;
        poolHardcap = _poolHardcap;
        minInvest = _minInvest;
        status = PoolStatus.DRAFT;
    }

    receive() external payable {}

    function invest(uint _amount) public {
        require(tokenAddress != address(0), "Token not set");
        // check if time valid
        require(block.timestamp <= poolEnd, "Expired time");

        // check if not hardcap
        require(_amount + total <= poolHardcap, "Hardcap Reached");

        // check if status open
        require(status == PoolStatus.OPEN, "Not OPEN");

        // check if amount > min
        require(_amount >= minInvest, "Invest Too Small");

        // fees
        GamePool _gamePool = GamePool(gamePoolAddress);
        uint treasuryFeePercent = _gamePool.collectedTreasuryPercent();
        address treasuryAddress = _gamePool.treasuryAddress();
        uint _feeToTreasury = (treasuryFeePercent * _amount) / 100;

        uint _amountPlusFee = _amount + _feeToTreasury;

        IERC20 token = IERC20(tokenAddress);
        uint _allowance = token.allowance(msg.sender, address(this));
        require(
            token.balanceOf(msg.sender) >= _amountPlusFee,
            "Not Enough Token"
        );
        require(_allowance >= _amountPlusFee, "Token allowance not enough");

        if (balances[msg.sender] == 0) {
            investors.push(msg.sender);
        }

        token.transferFrom(msg.sender, address(this), _amount);
        token.transferFrom(msg.sender, treasuryAddress, _feeToTreasury);

        balances[msg.sender] += _amount;
        total += _amount;
    }

    // investor mint nft
    function mintGeekzPass() external {
        require(status == PoolStatus.DEPLOYED);
        require(geekzPassAddress != address(0));
        require(balances[msg.sender] > 0);

        GeekzPass _geekzPass = GeekzPass(geekzPassAddress);
        uint tokenId = _geekzPass.mintPass(
            poolGameId,
            poolNum,
            msg.sender,
            balances[msg.sender]
        );

        GamePool _gamePool = GamePool(gamePoolAddress);

        // set on gamepool nftLastClaimedWeek to track last claimed reward
        _gamePool.setNftClaimed(tokenId, poolNum);
        minted[msg.sender] = true;
    }

    function getInvested() external view returns (uint) {
        return balances[msg.sender];
    }

    function isNftMinted() external view returns (bool) {
        return minted[msg.sender];
    }

    function getInvestorData()
        external
        view
        onlyOwner
        returns (address[] memory, uint[] memory)
    {
        uint[] memory investments = new uint[](investors.length);
        for (uint i = 0; i < investors.length; i++) {
            investments[i] = balances[investors[i]];
        }

        return (investors, investments);
    }

    function clearStuckBalance() external onlyOwner {
        payable(receiverAddress).transfer(address(this).balance);
    }

    // function claimReward() external {
    //     IERC20 token = IERC20(tokenAddress);
    //     (uint unclaimed, uint totalNFT) = getAvailableClaim();
    //     require(unclaimed > 0);

    //     GamePool _gamePool = GamePool(gamePoolAddress);
    //     GeekzPass _geekzPass = GeekzPass(geekzPassAddress);

    //     for (uint i = 0; i < totalNFT; i++) {
    //         uint tokenId = _geekzPass.tokenOfOwnerByIndex(msg.sender, i);

    //         // guard
    //         _gamePool.setNftClaimed(tokenId, poolNum);
    //     }

    //     // this is valid if reward being distributed to investPool
    //     token.transfer(msg.sender, unclaimed);
    // }

    function getAvailableClaim()
        public
        view
        returns (uint unclaimed, uint totalNFT)
    {
        GeekzPass _geekzPass = GeekzPass(geekzPassAddress);

        totalNFT = _geekzPass.balanceOf(msg.sender);
        GamePool _gamePool = GamePool(gamePoolAddress);

        for (uint i = 0; i < totalNFT; i++) {
            uint tokenId = _geekzPass.tokenOfOwnerByIndex(msg.sender, i);
            (, uint _poolNum, uint _amount) = _geekzPass.getTokenData(tokenId);
            if (poolNum == _poolNum) {
                for (
                    uint j = _gamePool.getNftClaimedCounter(tokenId);
                    j < _gamePool.rewardCounter();
                    j++
                ) {
                    (uint amt, uint cps) = _gamePool.getRewardByCounter(j);

                    unclaimed += (_amount * amt) / cps;
                }
            }
        }
    }

    function finalize() external onlyOwner {
        require(receiverAddress != address(0), "Receiver Address not set");
        require(geekzPassAddress != address(0), "GeekzPass not set");
        require(tokenAddress != address(0), "tokenAddress not set");
        require(investors.length > 0, "No Investor yet");

        status = PoolStatus.DEPLOYED;

        IERC20 token = IERC20(tokenAddress);
        uint totalTransfer = token.balanceOf(address(this));
        token.transfer(gamePoolAddress, totalTransfer);

        uint[] memory investments = new uint[](investors.length);
        for (uint i = 0; i < investors.length; i++) {
            investments[i] = balances[investors[i]];
        }

        GamePool _gamePool = GamePool(gamePoolAddress);
        _gamePool.deployPool(
            poolNum,
            totalTransfer,
            poolGameId,
            investors,
            investments
        );
    }

    function setReceiverAddress(address _receiverAddress) external onlyOwner {
        receiverAddress = _receiverAddress;
    }

    function setGeekzPass(address _gp) external onlyOwner {
        geekzPassAddress = _gp;
    }

    function setOpen() external onlyOwner {
        status = PoolStatus.OPEN;

        emit PoolStatusChanged(poolGameId, poolNum, status);
    }

    function setClosed() external onlyOwner {
        status = PoolStatus.CLOSED;

        emit PoolStatusChanged(poolGameId, poolNum, status);
    }

    function setCancel() external onlyOwner {
        status = PoolStatus.CANCEL;

        emit PoolStatusChanged(poolGameId, poolNum, status);
    }

    function setGamePoolAddress(address _gamePoolAddress) external onlyOwner {
        gamePoolAddress = _gamePoolAddress;
    }

    function setTokenAddress(address _tokenAddress) external onlyOwner {
        tokenAddress = _tokenAddress;
    }

    function setPoolGame(string memory _poolGame) external onlyOwner {
        poolGame = _poolGame;
    }

    function setPoolTime(uint _poolStart, uint _poolEnd) external onlyOwner {
        poolStart = _poolStart;
        poolEnd = _poolEnd;
    }

    function setPoolHardcap(uint _poolHardcap) external onlyOwner {
        poolHardcap = _poolHardcap;
    }

    function setMinInvest(uint _minInvest) external onlyOwner {
        minInvest = _minInvest;
    }
}
