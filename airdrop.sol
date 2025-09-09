// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;


interface IERC20 {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

contract Airdrop {
    address public owner;
    address public operator;

    address[] public supportedTokenList;
    mapping(address => bool) public supportedTokens;
    mapping(address => uint256) public totalDepositedByToken;
    uint256 public airdropEndtime;
    uint256 public minDepositAmount;
    uint256 public totalReward;
    bool public depositEnabled;

    struct Deposit {
        address token;
        uint256 amount;
        uint256 lockTime;
        address referral;
    }
    mapping(address => Deposit[]) public deposits;
    mapping(address => uint256) public rewards;

    event TokenTypeAdded(address indexed atoken);
    event AirdropEndChanged(uint256 timestamp);
    event AirdropTokenRewarded(address indexed user, uint256 amount, address referral, uint256 duration);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    modifier onlyOperator() {
        require(msg.sender == operator, "Only operator can call this function");
        _;
    }

    constructor() {
        owner = msg.sender;
        operator = msg.sender;
        minDepositAmount = 20 * 10**6;
        depositEnabled = true;
        totalReward = 0;
    }

    function addToken(address _tokenAddress) public onlyOperator {
        require(_tokenAddress != address(0), "Invalid token address");
        require(!supportedTokens[_tokenAddress], "Token already supported");
        supportedTokens[_tokenAddress] = true;
        supportedTokenList.push(_tokenAddress);
        emit TokenTypeAdded(_tokenAddress);
    }

    function deposit(address _token, uint256 _amount, address _referral) public {
        require(depositEnabled, "Deposits are disabled");
        require(supportedTokens[_token], "Token not supported");
        require(_amount >= minDepositAmount, "Amount not enough");

        IERC20 token = IERC20(_token);
        token.transferFrom(msg.sender, address(this), _amount);

        totalDepositedByToken[_token] += _amount;
        deposits[msg.sender].push(Deposit({
            token: _token,
            amount: _amount,
            lockTime: block.timestamp,
            referral: _referral
        }));
    }

    function withdraw(uint256 _depositIndex) public {
        require(_depositIndex < deposits[msg.sender].length, "Invalid deposit index");

        Deposit storage depositToWithdraw = deposits[msg.sender][_depositIndex];
        require(block.timestamp >= depositToWithdraw.lockTime + 3600, "Lock period not over yet");

        uint256 amount = depositToWithdraw.amount;
        address tokenAddress = depositToWithdraw.token;
        uint256 locktime = depositToWithdraw.lockTime;
        address referral = depositToWithdraw.referral;

        deposits[msg.sender][_depositIndex] = deposits[msg.sender][deposits[msg.sender].length - 1];
        deposits[msg.sender].pop();
        totalDepositedByToken[tokenAddress] -= amount;

        IERC20 token = IERC20(tokenAddress);
        token.transfer(msg.sender, amount);

        uint256 duration;
	    if (airdropEndtime == 0 || airdropEndtime > block.timestamp){
	        duration = block.timestamp - locktime;
	    }else if (airdropEndtime <= block.timestamp){
	        duration = airdropEndtime - locktime;
	    }
        uint256 rewarded_tokens = 10**18 * (amount * duration) / (1000*10**6 * 365 days);
        rewards[msg.sender] += rewarded_tokens;
        totalReward += rewarded_tokens;
        emit AirdropTokenRewarded(msg.sender, rewarded_tokens, referral, duration);
    }

    function getReward(address _user) public view returns (uint256) {
        uint256 reward = rewards[_user];
        for (uint d = 0; d < deposits[_user].length; d ++) {
            Deposit memory depositToWithdraw = deposits[_user][d];
            uint256 amount = depositToWithdraw.amount;
            uint256 locktime = depositToWithdraw.lockTime;
            uint256 duration;
	        if (airdropEndtime == 0 || airdropEndtime > block.timestamp){
	            duration = block.timestamp - locktime;
	        }else if (airdropEndtime <= block.timestamp){
	            duration = airdropEndtime - locktime;
	        }

            uint256 rewarded_tokens = 10**18 * (amount * duration) / ( 1000*10**6 * 365 days);
            reward += rewarded_tokens;
        }

        return reward;
    }

    function getDepositsLength(address _user) public view returns (uint256) {
        return deposits[_user].length;
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

    function setMinDepositAmount(uint256 _newAmount) public onlyOperator {
        minDepositAmount = _newAmount;
    }

    function checkExcessToken(address _tokenAddress) public view returns (uint256) {
        IERC20 token = IERC20(_tokenAddress);
        uint256 contractBalance = token.balanceOf(address(this));
        uint256 depositedAmount = totalDepositedByToken[_tokenAddress];

        if (contractBalance > depositedAmount) {
            return contractBalance - depositedAmount;
        } else {
            return 0;
        }
    }

    function withdrawExcessTokens() public onlyOperator {
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

