pragma solidity ^0.6.6;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {DALP} from "./DALP.sol";

contract DALPManager is Ownable {
    DALP public dalp; // DALP token

    // called by admin on deployment
    function setTokenContract(address _tokenAddress) public onlyOwner {
        dalp = DALP(_tokenAddress);
    }

    function mint() public payable {
        require(msg.value > 0, "Must send ETH");
        uint mintAmount = calculateMintAmount();
        dalp.mint(msg.sender, mintAmount);
    }

    function burn(uint tokensToBurn) public {
        require(tokensToBurn > 0, "Must burn tokens");
        require(dalp.balanceOf(msg.sender) >= tokensToBurn, "Insufficient balance");

        dalp.burn(msg.sender, tokensToBurn);
    }

    function calculateMintAmount() public view returns (uint) {
        return 10; // placeholder logic
    }
}
