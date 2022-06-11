// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract GeekzPass is Ownable, ERC721, ERC721Enumerable, ReentrancyGuard {
    using Counters for Counters.Counter;
    string public gameName;
    address public gamePool;
    string baseUri = "https://gpass.geekzwolf.com/";

    Counters.Counter private _tokenIdCounter;

    struct Investment {
        uint gameId;
        uint poolNum;
        uint amount;
    }

    struct PoolData {
        uint gameId;
        uint poolNum;
        address[] investors;
        uint[] amounts;
        bool[] minted;
    }

    mapping(uint256 => Investment) tokenIdInvestment;
    mapping(uint256 => mapping(uint256 => PoolData)) poolList;

    constructor(
        string memory nftName,
        string memory nftSymbol,
        string memory baseTokenURI,
        string memory _gameName,
        address _gamePool,
        address _owner
    ) ERC721(nftName, nftSymbol) {
        transferOwnership(_owner);
        baseUri = baseTokenURI;
        gameName = _gameName;
        gamePool = _gamePool;
    }

    function setBaseUri(string memory uri) external onlyOwner {
        baseUri = uri;
    }

    function _baseURI() internal view override returns (string memory) {
        return baseUri;
    }

    function mintPass(
        uint256 _gameId,
        uint256 _poolNum,
        address to,
        uint256 _invest
    ) public nonReentrant returns (uint) {
        PoolData storage pool = poolList[_gameId][_poolNum];

        address[] memory investors = pool.investors;
        bool[] storage minted = pool.minted;

        for (uint i = 0; i < investors.length; i++) {
            if (to == investors[i]) {
                if (!minted[i]) {
                    _tokenIdCounter.increment();
                    uint256 tokenId = _tokenIdCounter.current();
                    _safeMint(to, tokenId);

                    Investment storage investmentDetail = tokenIdInvestment[
                        tokenId
                    ];
                    investmentDetail.gameId = _gameId;
                    investmentDetail.amount = _invest;
                    investmentDetail.poolNum = _poolNum;

                    minted[i] = true;
                    return tokenId;
                } else {
                    revert("ALREADY MINT");
                }
            }
        }
        return 0;
    }

    function getTokenData(uint tokenId)
        public
        view
        returns (
            uint,
            uint,
            uint
        )
    {
        Investment storage investmentDetail = tokenIdInvestment[tokenId];
        return (
            investmentDetail.gameId,
            investmentDetail.poolNum,
            investmentDetail.amount
        );
    }

    function getTokenInvestAmount(uint tokenId) public view returns (uint) {
        return (tokenIdInvestment[tokenId].amount);
    }

    // call from GamePoll to init data after pool closed
    function setGeekzPassData(
        uint _gameId,
        uint _poolNum,
        address[] memory _investors,
        uint[] memory _investments
    ) public {
        require(msg.sender == gamePool, "Not From GamePool");

        bool[] memory minted = new bool[](_investors.length);
        // for (uint256 i = 0; i < _investors.length - 1; i++) {
        //     minted[i] = false;
        // }
        PoolData memory pool = PoolData(
            _gameId,
            _poolNum,
            _investors,
            _investments,
            minted
        );
        // poolList.push(pool);
        poolList[_gameId][_poolNum] = pool;
    }

    function getMintStatus(
        uint256 gameId,
        uint256 poolNum,
        address userAddress
    ) public view returns (bool minted) {
        PoolData memory selectedPoolData = poolList[gameId][poolNum];

        for (uint256 i = 0; i < selectedPoolData.investors.length; i++) {
            if (selectedPoolData.investors[i] == userAddress) {
                return selectedPoolData.minted[i];
            }
        }

        return false;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
