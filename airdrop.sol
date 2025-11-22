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

    constructor(address _aaveProxy) {
        owner = msg.sender;
        operator = msg.sender;
        aaveProxy = _aaveProxy;
    }

    function addToken(address _tokenAddress) public onlyOwner {
        require(_tokenAddress != address(0), "Invalid token address");
        require(!supportedTokens[_tokenAddress], "Token already supported");
        supportedTokens[_tokenAddress] = true;
        supportedTokenList.push(_tokenAddress);
    }

    function deposit(address _token, uint256 _amount, address referral) public {
        require(!evacuateEnabled, "Evacuate is enabled");
        require(depositEnabled, "Deposit is disabled");
        require(supportedTokens[_token], "Token not supported");

        IERC20 token = IERC20(_token);
        token.transferFrom(msg.sender, address(this), _amount);

        Deposit storage userDeposit = deposits[_token][msg.sender];
        userDeposit.amount += _amount;
        userDeposit.timestamp = block.timestamp;
        totalDepositedByToken[_token] += _amount;
        deposits[_token][msg.sender] = userDeposit;
        emit AirdropDepositChanged(msg.sender, _token, userDeposit.amount, block.timestamp, referral);

        token.approve(aaveProxy, _amount);
        IAave(aaveProxy).supply(_token, _amount, address(this), 0);
    }

    function withdraw() public {
        for (uint256 i = 0; i < supportedTokenList.length; i++) {
            address _token = supportedTokenList[i];
            Deposit storage userDeposit = deposits[_token][msg.sender];
            uint256 duration = block.timestamp - userDeposit.timestamp;
            if (duration > 8 hours) {
                uint256 _amount = userDeposit.amount;
                userDeposit.amount = 0;
                deposits[_token][msg.sender] = userDeposit;

                uint256 credit = credits[msg.sender];
                credit += _amount * duration;
                credits[msg.sender] = credit;

                totalDepositedByToken[_token] -= _amount;
                if(!evacuateEnabled) {
                    IAave(aaveProxy).withdraw(_token, _amount, address(this));
                }
                IERC20 token = IERC20(_token);
                token.transfer(msg.sender, _amount);

                uint256 endtime;
                if(block.timestamp > airdropEndtime){
                    endtime = airdropEndtime;
                }else{
                    endtime = block.timestamp;
                }
                emit AirdropDepositChanged(msg.sender, _token, 0, endtime, address(0));
            }
        }
    }

    function purchase(address _token, uint256 _zentra_amount) public {
        require(supportedTokens[_token], "Token not supported");
        require(airdropEndtime > 0, "Airdrop is not finished yet");
        require(block.timestamp > airdropEndtime, "Airdrop is not finished yet");

        uint256 credit = credits[msg.sender];
        credit -= _zentra_amount * 365 days * 100;
        credits[msg.sender] = credit;
        IERC20 token = IERC20(_token);
        token.transferFrom(msg.sender, address(this), _zentra_amount*100*10**6/(10**18));

        emit TokenPurchased(msg.sender, _zentra_amount);
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
        uint256 depositedTotal = totalDepositedByToken[_tokenAddress];
        if(evacuateEnabled){
            uint256 tokenBalance = IERC20(_tokenAddress).balanceOf(address(this));
            if (tokenBalance > depositedTotal) {
                return tokenBalance - depositedTotal;
            }
        }else{
            IERC20 aToken = IERC20(IAave(aaveProxy).getReserveAToken(_tokenAddress));
            uint256 aTokenBalance = aToken.balanceOf(address(this));
            if (aTokenBalance > depositedTotal) {
                return aTokenBalance - depositedTotal;
            }
        }

        return 0;
    }

    function withdrawYieldTokens() public onlyOperator {
        for (uint i = 0; i < supportedTokenList.length; i++) {
            address tokenAddress = supportedTokenList[i];
            uint256 yieldAmount = checkYieldToken(tokenAddress);
            if(evacuateEnabled){
                if (yieldAmount > 0) {
                    IERC20(tokenAddress).transfer(owner, yieldAmount);
                }
            }else{
                IERC20 aToken = IERC20(IAave(aaveProxy).getReserveAToken(tokenAddress));

                if (yieldAmount > 0) {
                    aToken.transfer(owner, yieldAmount);
                }
            }
        }
    }

    function evacuate(address _tokenAddress) public onlyOperator {
        evacuateEnabled = true;

        IERC20 aToken = IERC20(IAave(aaveProxy).getReserveAToken(_tokenAddress));
        uint256 aTokenBalance = aToken.balanceOf(address(this));

        if (aTokenBalance > 0) {
            IAave(aaveProxy).withdraw(_tokenAddress, aTokenBalance, address(this));
        }
    }
}
