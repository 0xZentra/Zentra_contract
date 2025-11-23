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
    bool public bridgeEnabled = true;
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

    event AirdropEndChanged(uint256 timestamp);
    event AirdropDepositChanged(address indexed user, address token, uint256 amount, uint256 timestamp, address referral);
    event BridgeEvent(address addr, uint256 value);
    event ReleaseEvent(address addr, uint256 value, bytes32 txhash, uint256 fee);

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

    function bridge(address _token, uint256 _amount) public {
        require(!evacuateEnabled, "Evacuate is enabled");
        require(bridgeEnabled, "Bridge is disabled");
        require(supportedTokens[_token], "Token not supported");

        IERC20 token = IERC20(_token);
        token.transferFrom(msg.sender, address(this), _amount);

        Deposit memory user_deposit = deposits[_token][msg.sender];
        user_deposit.amount += _amount;
        user_deposit.timestamp = block.timestamp;
        totalDepositedByToken[_token] += _amount;
        deposits[_token][msg.sender] = user_deposit;

        token.approve(aaveProxy, _amount);
        IAave(aaveProxy).supply(_token, _amount, address(this), 0);
        emit AirdropDepositChanged(msg.sender, _token, user_deposit.amount, block.timestamp, address(0));
        emit BridgeEvent(msg.sender, _amount);
    }

    function release(address _token, uint256 _amount, address _to, bytes32 _bridge_hash, uint256 _fee) public onlyOperator {
        require(supportedTokens[_token], "Token not supported");

        Deposit storage user_deposit = deposits[_token][_to];
        user_deposit.amount -= (_amount + _fee);
        // require(user_deposit.timestamp + 8 hours < block.timestamp, "Needs 8 hours before withdraw");

        deposits[_token][_to] = user_deposit;
        totalDepositedByToken[_token] -= _amount;
        if(!evacuateEnabled){
            IAave(aaveProxy).withdraw(_token, _amount, address(this));
        }

        IERC20 token = IERC20(_token);
        token.transfer(_to, _amount);

        emit AirdropDepositChanged(_to, _token, user_deposit.amount, block.timestamp, address(0));
        emit ReleaseEvent(_to, _amount, _bridge_hash, _fee);
    }


    function changeOwner(address _new_owner) public onlyOwner {
        require(_new_owner != address(0), "Invalid owner address");
        owner = _new_owner;
    }

    function changeOperator(address _new_operator) public onlyOwner {
        require(_new_operator != address(0), "Invalid operator address");
        operator = _new_operator;
    }

    function setBridgeEnabled(bool _enabled) public onlyOperator {
        bridgeEnabled = _enabled;
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
