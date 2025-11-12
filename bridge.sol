// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

interface IAave {
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
    function getReserveAToken(address asset) external view returns (address);
}

contract Bridge {
    address public owner;
    address public operator;

    address[] public supportedTokenList;
    mapping(address => bool) public supportedTokens;
    mapping(address => uint256) public totalDepositedByToken;
    uint256 public airdropEndtime;
    bool public depositEnabled;
    address public aaveProxy;
    // 0xA238Dd80C259a72e81d7e4664a9801593F98d1c5 for base
    // 0x794a61358D6845594F94dc1DB02A252b5b4814aD for op
    // 0x794a61358D6845594F94dc1DB02A252b5b4814aD for arb
    // 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2 for eth

    struct Deposit {
        uint256 amount;
        uint256 timestamp;
    }
    mapping(address => mapping(address => Deposit)) public deposits;

    event AirdropEndChanged(uint256 timestamp);
    event AirdropDepositChanged(address indexed user, address token, uint256 amount, uint256 timestamp);
    event BridgeEvent(address addr, uint256 value);
    event ReleaseEvent(address addr, uint256 value, bytes32 txhash);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    modifier onlyOperator() {
        require(msg.sender == operator, "Only operator can call this function");
        _;
    }

    constructor(address _aaveProxy) {
        owner = msg.sender;
        operator = msg.sender;
        depositEnabled = true;
        aaveProxy = _aaveProxy;
    }

    function addToken(address _tokenAddress) public onlyOwner {
        require(_tokenAddress != address(0), "Invalid token address");
        require(!supportedTokens[_tokenAddress], "Token already supported");
        supportedTokens[_tokenAddress] = true;
        supportedTokenList.push(_tokenAddress);
    }

    function bridge(address _token, uint256 _amount) public {
        require(depositEnabled, "Deposits are disabled");
        require(supportedTokens[_token], "Token not supported");

        IERC20 token = IERC20(_token);
        token.transferFrom(msg.sender, address(this), _amount);

        Deposit memory userDeposit = deposits[_token][msg.sender];
        userDeposit.amount += _amount;
        userDeposit.timestamp = block.timestamp;
        totalDepositedByToken[_token] += _amount;
        deposits[_token][msg.sender] = userDeposit;

        token.approve(aaveProxy, _amount);
        IAave(aaveProxy).supply(_token, _amount, address(this), 0);
        emit AirdropDepositChanged(msg.sender, _token, userDeposit.amount, block.timestamp);
        emit BridgeEvent(msg.sender, _amount);
    }

    function release(address _token, uint256 _amount, address _to, bytes32 _bridge_hash) public onlyOperator {
        require(supportedTokens[_token], "Token not supported");

        Deposit storage userDeposit = deposits[_token][_to];  // <- bug here
        userDeposit.amount -= _amount;
        require(userDeposit.timestamp + 8 hours < block.timestamp, "Needs 8 hours before withdraw");

        deposits[_token][_to] = userDeposit;
        totalDepositedByToken[_token] -= _amount;
        IAave(aaveProxy).withdraw(_token, _amount, address(this));

        IERC20 token = IERC20(_token);
        token.transfer(_to, _amount);

        emit AirdropDepositChanged(_to, _token, userDeposit.amount, block.timestamp);
        emit ReleaseEvent(_to, _amount, _bridge_hash);
    }


    function changeOwner(address _newOwner) public onlyOwner {
        require(_newOwner != address(0), "Invalid owner address");
        owner = _newOwner;
    }

    function changeOperator(address _newOperator) public onlyOwner {
        require(_newOperator != address(0), "Invalid operator address");
        operator = _newOperator;
    }

    function setDepositEnabled(bool _enabled) public onlyOperator {
        depositEnabled = _enabled;
    }

    function setAirdropEndtime(uint256 _timestamp) public onlyOperator {
        airdropEndtime = _timestamp;
        emit AirdropEndChanged(_timestamp);
    }

    function checkYieldToken(address _tokenAddress) public view returns (uint256) {
        IERC20 aToken = IERC20(IAave(aaveProxy).getReserveAToken(_tokenAddress));
        uint256 aTokenBalance = aToken.balanceOf(address(this));
        uint256 depositedTotal = totalDepositedByToken[_tokenAddress];

        if (aTokenBalance > depositedTotal) {
            return aTokenBalance - depositedTotal;
        } else {
            return 0;
        }
    }

    function withdrawYieldTokens() public onlyOperator {
        for (uint i = 0; i < supportedTokenList.length; i++) {
            address tokenAddress = supportedTokenList[i];
            IERC20 aToken = IERC20(IAave(aaveProxy).getReserveAToken(tokenAddress));
            uint256 yieldAmount = checkYieldToken(tokenAddress);

            if (yieldAmount > 0) {
                aToken.transfer(owner, yieldAmount);
            }
        }
    }
}
