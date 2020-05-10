pragma solidity ^0.6.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "./DALP.sol";

contract DALPManager is Ownable {
    DALP public dalp; // DALP token

    // called by admin on deployment
    function setTokenContract(address _tokenAddress) public onlyOwner {
        dalp = DALP(_tokenAddress);
    }

    function mint() public payable {
        require(msg.value > 0, "Must send ETH");
        dalp.mint.value(msg.value)(msg.sender);
    }

    function burn(uint tokensToBurn) public {
        require(tokensToBurn > 0, "Must burn tokens");
        require(dalp.balanceOf(msg.sender) >= tokensToBurn, "Insufficient balance");

        dalp.burn(msg.sender, tokensToBurn);
    }
}