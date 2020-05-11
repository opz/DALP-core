pragma solidity ^0.6.7;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract DALP is ERC20("DALP Token", "DALPa"), Ownable {
    // DALPManager contract
    address public manager;

    function mint(address investor, uint mintAmount) external onlyManager {
        _mint(investor, mintAmount);
    }

    function burn(address investor, uint tokensToBurn) external onlyManager {
        _burn(investor, tokensToBurn);
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
