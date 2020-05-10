pragma solidity ^0.6.7;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DALP is ERC20("DALP Token", "DALPa") {
    function _mint() public payable {
        uint mintAmount = calculateMintAmount();
        return super._mint(msg.sender, mintAmount);
    }

    function _burn(uint tokensToBurn) public {
        return super._burn(msg.sender, tokensToBurn);
    }

    function calculateMintAmount() public view returns(uint){
        return 10; // placeholder logic
    }
}