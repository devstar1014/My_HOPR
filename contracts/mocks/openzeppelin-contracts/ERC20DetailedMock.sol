pragma solidity ^0.5.0;

import "../../ERC20Token.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Detailed.sol";


contract ERC20DetailedMock is ERC20Token, ERC20Detailed {
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals
    ) public ERC20Detailed(name, symbol, decimals) {
        // solhint-disable-previous-line no-empty-blocks
    }
}
