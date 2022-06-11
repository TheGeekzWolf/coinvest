// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract GameManager is Ownable {
    address[] private gamePools;
    string[] private gameList;
    string chainName;

    event GamePoolCreated(
        address indexed gamePoolAddress,
        uint256 indexed gameId,
        string indexed gameName
    );

    constructor(string memory _chainName) {
        chainName = _chainName;
    }

    function addGamePool(address newPool, string calldata _gameName)
        external
        onlyOwner
    {
        gameList.push(_gameName);
        gamePools.push(newPool);

        emit GamePoolCreated(newPool, gamePools.length, _gameName);
    }

    function remove(uint index) internal onlyOwner {
        if (index >= gamePools.length) return;

        for (uint i = index; i < gamePools.length - 1; i++) {
            gamePools[i] = gamePools[i + 1];
            gameList[i] = gameList[i + 1];
        }
        gamePools.pop();
        gameList.pop();
    }

    function removeGamePool(string calldata _gameName) external onlyOwner {
        for (uint i = 0; i < gamePools.length - 1; i++) {
            if (
                keccak256(abi.encodePacked(_gameName)) ==
                keccak256(abi.encodePacked(gameList[i]))
            ) {
                remove(i);
            }
        }
    }

    function getData()
        external
        view
        returns (string[] memory, address[] memory)
    {
        return (gameList, gamePools);
    }
}
