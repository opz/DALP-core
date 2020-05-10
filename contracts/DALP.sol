pragma solidity ^0.6.7;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract DALP is ERC20("DALP Token", "DALPa"), Ownable {
    // DALPManager contract
    address public manager;

    function mint(address investor) external payable onlyManager {
        _mint(investor);
    }

    function _mint(address investor) internal {
        uint mintAmount = calculateMintAmount();
        return super._mint(investor, mintAmount);
    }

    function burn(address investor, uint tokensToBurn) external onlyManager {
        _burn(investor, tokensToBurn);
    }

    function _burn(address investor, uint tokensToBurn) internal override {
        return super._burn(investor, tokensToBurn);
    }

    function calculateMintAmount() public view returns(uint){
        return 10; // placeholder logic
    }

    modifier onlyManager {
        require(msg.sender == manager, "Only Manager contract can call");
        _;
    }

    // admin call on deployment
    function setManagerContractAddress(address _manager) public onlyOwner {
        manager = _manager;
    }
}