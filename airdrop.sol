// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;


interface IERC20 {
    // event Transfer(address indexed from, address indexed to, uint256 value);
    // event Approval(address indexed owner, address indexed spender, uint256 value);

    // function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    // function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

interface IAave {
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
}

contract Airdrop {
    address public owner;
    address public operator;

    address[] public supportedTokenList;
    mapping(address => bool) public supportedTokens;
    mapping(address => uint256) public totalDepositedByToken;
    uint256 public airdropEndtime;
    bool public depositEnabled;
    address aaveProxy; // 0xA238Dd80C259a72e81d7e4664a9801593F98d1c5
    // uint256 public minDepositAmount;
    // uint256 public totalReward;

    struct Deposit {
        address token;
        uint256 amount;
        // uint256 lockTime;
        // address referral;
    }
    mapping(address => Deposit) public deposits;
    // mapping(address => uint256) public rewards;

    event TokenTypeAdded(address indexed token);
    event AirdropEndChanged(uint256 timestamp);
    event AirdropDepositChanged(address indexed user, uint256 amount, uint256 timestamp);

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
        // minDepositAmount = 20 * 10**6;
        // totalReward = 0;
    }

    function addToken(address _tokenAddress) public onlyOperator {
        require(_tokenAddress != address(0), "Invalid token address");
        require(!supportedTokens[_tokenAddress], "Token already supported");
        supportedTokens[_tokenAddress] = true;
        supportedTokenList.push(_tokenAddress);
        emit TokenTypeAdded(_tokenAddress);
    }

    function deposit(address _token, uint256 _amount) public {
        require(depositEnabled, "Deposits are disabled");
        require(supportedTokens[_token], "Token not supported");
        // require(_amount >= minDepositAmount, "Amount not enough");

        IERC20 token = IERC20(_token);
        token.transferFrom(msg.sender, address(this), _amount);

        totalDepositedByToken[_token] += _amount;
        deposits[msg.sender] = Deposit({
            token: _token,
            amount: _amount
            // lockTime: block.timestamp,
            // referral: _referral
        });
        aaveDeposit(_token, _amount);
    }

    function withdraw(uint256 _amount) public {
        // require(_depositIndex < deposits[msg.sender].length, "Invalid deposit index");

        Deposit storage userDeposit = deposits[msg.sender];
        // require(block.timestamp >= userDeposit.lockTime + 3600, "Lock period not over yet");
        userDeposit.amount -= _amount;
        address tokenAddress = userDeposit.token;
        aaveWithdraw(tokenAddress, _amount);
        // uint256 locktime = userDeposit.lockTime;
        // address referral = userDeposit.referral;

        deposits[msg.sender] = userDeposit;
        // deposits[msg.sender].pop();
        totalDepositedByToken[tokenAddress] -= _amount;

        IERC20 token = IERC20(tokenAddress);
        token.transfer(msg.sender, _amount);

        // uint256 duration;
	    // if (airdropEndtime == 0 || airdropEndtime > block.timestamp){
	    //     duration = block.timestamp - locktime;
	    // }else if (airdropEndtime <= block.timestamp){
	    //     duration = airdropEndtime - locktime;
	    // }
        // uint256 rewarded_tokens = 10**18 * (amount * duration) / (1000*10**6 * 365 days);
        // rewards[msg.sender] += rewarded_tokens;
        // totalReward += rewarded_tokens;
        emit AirdropDepositChanged(msg.sender, userDeposit.amount, block.timestamp);
    }

    // function getReward(address _user) public view returns (uint256) {
    //     uint256 reward = rewards[_user];
    //     for (uint d = 0; d < deposits[_user].length; d ++) {
    //         Deposit memory depositToWithdraw = deposits[_user][d];
    //         uint256 amount = depositToWithdraw.amount;
    //         uint256 locktime = depositToWithdraw.lockTime;
    //         uint256 duration;
	//         if (airdropEndtime == 0 || airdropEndtime > block.timestamp){
	//             duration = block.timestamp - locktime;
	//         }else if (airdropEndtime <= block.timestamp){
	//             duration = airdropEndtime - locktime;
	//         }

    //         uint256 rewarded_tokens = 10**18 * (amount * duration) / ( 1000*10**6 * 365 days);
    //         reward += rewarded_tokens;
    //     }

    //     return reward;
    // }

    // function getDepositsLength(address _user) public view returns (uint256) {
    //     return deposits[_user].length;
    // }


    function aaveDeposit(address _asset, uint256 _amount) internal {
        // require(msg.sender == operator, OPERATOR_REQUIRED_ERROR);
        IERC20(_asset).approve(aaveProxy, _amount);
        IAave(aaveProxy).supply(_asset, _amount, address(this), 0);
    }

    function aaveWithdraw(address _asset, uint256 _amount) internal {
        // require(msg.sender == operator, OPERATOR_REQUIRED_ERROR);
        IAave(aaveProxy).withdraw(_asset, _amount, address(this));
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

    // function setMinDepositAmount(uint256 _newAmount) public onlyOperator {
    //     minDepositAmount = _newAmount;
    // }

    function checkYieldToken(address _tokenAddress) public view returns (uint256) {
        IERC20 token = IERC20(_tokenAddress);
        uint256 contractBalance = token.balanceOf(address(this));
        uint256 depositedAmount = totalDepositedByToken[_tokenAddress];

        if (contractBalance > depositedAmount) {
            return contractBalance - depositedAmount;
        } else {
            return 0;
        }
    }

    function withdrawYieldTokens() public onlyOperator {
        for (uint i = 0; i < supportedTokenList.length; i++) {
            address tokenAddress = supportedTokenList[i];
            IERC20 token = IERC20(tokenAddress);
            uint256 contractBalance = token.balanceOf(address(this));
            uint256 depositedAmount = totalDepositedByToken[tokenAddress];

            if (contractBalance > depositedAmount) {
                uint256 excessAmount = contractBalance - depositedAmount;
                token.transfer(owner, excessAmount);
            }
        }
    }
}

