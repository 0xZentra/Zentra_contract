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

contract Airdrop {
    address public owner;
    address public operator;

    address[] public supportedTokenList;
    mapping(address => bool) public supportedTokens;
    mapping(address => uint256) public totalDepositedByToken;
    uint256 public airdropEndtime;
    bool public depositEnabled = true;
    bool public evacuateEnabled = false;
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
    mapping(address => uint256) public credits;

    event AirdropEndChanged(uint256 timestamp);
    event AirdropDepositChanged(address indexed user, address token, uint256 amount, uint256 timestamp, address referral);
    event TokenPurchased(address indexed user, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    modifier onlyOperator() {
        require(msg.sender == operator, "Only operator can call this function");
        _;
    }

    constructor(address _aave_proxy) {
        owner = msg.sender;
        operator = msg.sender;
        aaveProxy = _aave_proxy;
    }

    function addToken(address _token_address) public onlyOwner {
        require(_token_address != address(0), "Invalid token address");
        require(!supportedTokens[_token_address], "Token already supported");
        supportedTokens[_token_address] = true;
        supportedTokenList.push(_token_address);
    }

    function deposit(address _stabletoken, uint256 _stabletoken_amount, address referral) public {
        require(!evacuateEnabled, "Evacuate is enabled");
        require(depositEnabled, "Deposit is disabled");
        require(supportedTokens[_stabletoken], "Token not supported");

        IERC20 token = IERC20(_stabletoken);
        token.transferFrom(msg.sender, address(this), _stabletoken_amount);

        Deposit storage user_deposit = deposits[_stabletoken][msg.sender];
        uint256 credit = credits[msg.sender];
        uint256 duration = block.timestamp - user_deposit.timestamp;
        credit += _stabletoken_amount * duration;
        credits[msg.sender] = credit;

        user_deposit.amount += _stabletoken_amount;
        user_deposit.timestamp = block.timestamp;
        totalDepositedByToken[_stabletoken] += _stabletoken_amount;
        deposits[_stabletoken][msg.sender] = user_deposit;
        emit AirdropDepositChanged(msg.sender, _stabletoken, user_deposit.amount, block.timestamp, referral);

        token.approve(aaveProxy, _stabletoken_amount);
        IAave(aaveProxy).supply(_stabletoken, _stabletoken_amount, address(this), 0);
    }

    function withdraw() public {
        for (uint256 i = 0; i < supportedTokenList.length; i++) {
            address _stabletoken = supportedTokenList[i];
            Deposit storage user_deposit = deposits[_stabletoken][msg.sender];
            uint256 _stabletoken_amount = user_deposit.amount;
            withdraw_token(_stabletoken, _stabletoken_amount);
        }
    }

    function withdraw_token(address _stabletoken, uint256 _stabletoken_amount) public {
        Deposit storage user_deposit = deposits[_stabletoken][msg.sender];
        uint256 duration = block.timestamp - user_deposit.timestamp;
        if (duration > 8 hours) {
            user_deposit.amount -= _stabletoken_amount;
            deposits[_stabletoken][msg.sender] = user_deposit;

            uint256 credit = credits[msg.sender];
            credit += _stabletoken_amount * duration;
            credits[msg.sender] = credit;

            totalDepositedByToken[_stabletoken] -= _stabletoken_amount;
            if(!evacuateEnabled) {
                IAave(aaveProxy).withdraw(_stabletoken, _stabletoken_amount, address(this));
            }
            IERC20 token = IERC20(_stabletoken);
            token.transfer(msg.sender, _stabletoken_amount);

            uint256 endtime;
            if(block.timestamp > airdropEndtime) {
                endtime = airdropEndtime;
            } else {
                endtime = block.timestamp;
            }
            emit AirdropDepositChanged(msg.sender, _stabletoken, 0, endtime, address(0));
        }
    }

    function purchase(address _stabletoken, uint256 _stabletoken_amount) public {
        require(supportedTokens[_stabletoken], "Token not supported");
        require(airdropEndtime > 0, "Airdrop is not finished yet");
        require(block.timestamp > airdropEndtime, "Airdrop is not finished yet");

        uint256 credit = credits[msg.sender];
        uint256 zentra_amount = _stabletoken_amount * 10**18 / 10 ** 6 / 100;
        credit -= _stabletoken_amount * 365 days;
        credits[msg.sender] = credit;
        IERC20 token = IERC20(_stabletoken);
        token.transferFrom(msg.sender, address(this), _stabletoken_amount);

        emit TokenPurchased(msg.sender, zentra_amount);
    }


    function changeOwner(address _new_owner) public onlyOwner {
        require(_new_owner != address(0), "Invalid owner address");
        owner = _new_owner;
    }

    function changeOperator(address _new_operator) public onlyOwner {
        require(_new_operator != address(0), "Invalid operator address");
        operator = _new_operator;
    }

    function setDepositEnabled(bool _enabled) public onlyOperator {
        depositEnabled = _enabled;
    }

    function setAirdropEndtime(uint256 _timestamp) public onlyOperator {
        airdropEndtime = _timestamp;
        emit AirdropEndChanged(_timestamp);
    }

    function checkYieldToken(address _token_address) public view returns (uint256) {
        uint256 depositedTotal = totalDepositedByToken[_token_address];
        if(evacuateEnabled){
            uint256 tokenBalance = IERC20(_token_address).balanceOf(address(this));
            if (tokenBalance > depositedTotal) {
                return tokenBalance - depositedTotal;
            }
        }else{
            IERC20 atoken = IERC20(IAave(aaveProxy).getReserveAToken(_token_address));
            uint256 atoken_balance = atoken.balanceOf(address(this));
            if (atoken_balance > depositedTotal) {
                return atoken_balance - depositedTotal;
            }
        }

        return 0;
    }

    function withdrawYieldTokens() public onlyOperator {
        for (uint i = 0; i < supportedTokenList.length; i++) {
            address token_address = supportedTokenList[i];
            uint256 yield_amount = checkYieldToken(token_address);
            if(evacuateEnabled){
                if (yield_amount > 0) {
                    IERC20(token_address).transfer(owner, yield_amount);
                }
            }else{
                IERC20 atoken = IERC20(IAave(aaveProxy).getReserveAToken(token_address));

                if (yield_amount > 0) {
                    atoken.transfer(owner, yield_amount);
                }
            }
        }
    }

    function evacuate(address _token_address) public onlyOperator {
        evacuateEnabled = true;

        IERC20 atoken = IERC20(IAave(aaveProxy).getReserveAToken(_token_address));
        uint256 atoken_balance = atoken.balanceOf(address(this));

        if (atoken_balance > 0) {
            IAave(aaveProxy).withdraw(_token_address, atoken_balance, address(this));
        }
    }
}
