pragma solidity ^0.8.7;
//SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";

interface ERC20 {
    function allowance(address _owner, address _spender)
        external
        view
        returns (uint256 remaining);

    function transferFrom(
        address _from,
        address _to,
        uint256 _value
    ) external returns (bool success);

    function balanceOf(address _owner) external view returns (uint256 balance);

    function transfer(address _to, uint256 _value)
        external
        returns (bool success);
}

contract RockPaperScissors is VRFConsumerBaseV2, ConfirmedOwner {
    event RequestSent(uint256 requestId, uint32 numWords);
    event RequestFulfilled(uint256 requestId, uint256 randomNumber);
    event GameEnd(uint256 requestId, address player, uint8 result);

    struct Game {
        uint8 choice;
        address player;
        uint256 bet;
        address token;
        uint8 result;
    }

    mapping(address => uint256) public isClaimedToday;

    receive() external payable {}

    struct RequestStatus {
        bool fulfilled; // whether the request has been successfully fulfilled
        bool exists; // whether a requestId exists
        uint256 randomNumber;
    }
    mapping(uint256 => RequestStatus) public s_requests; /* requestId --> requestStatus */
    mapping(uint256 => Game) public games; /* requestId --> choice */
    VRFCoordinatorV2Interface COORDINATOR;

    uint64 s_subscriptionId;

    uint256[] public requestIds;
    uint256 public lastRequestId;

    bytes32 keyHash =
        0xd4bb89654db74673a187bd804519e65e3f71a52bc55f11da7601a13dcf505314;

    uint32 callbackGasLimit = 100000;

    uint16 requestConfirmations = 3;

    uint32 numWords = 1;

    constructor(uint64 subscriptionId)
        VRFConsumerBaseV2(0x6A2AAd07396B36Fe02a22b33cf443582f682c82f)
        ConfirmedOwner(msg.sender)
    {
        COORDINATOR = VRFCoordinatorV2Interface(
            0x6A2AAd07396B36Fe02a22b33cf443582f682c82f
        );
        s_subscriptionId = subscriptionId;
        addToken(0xee8908AB53993e596A373ddbcb3AC5656aD6Aa38);
        addToken(0x1541dAF6e7Fa4C32d11e70Ad95259f4139eFFCd7);
        addToken(0x44A1Ec8DB904275899d788b6b27b86a549216577);
    }

    function requestRandomNumber() internal returns (uint256 requestId) {
        requestId = COORDINATOR.requestRandomWords(
            keyHash,
            s_subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );
        s_requests[requestId] = RequestStatus({
            randomNumber: 0,
            exists: true,
            fulfilled: false
        });
        requestIds.push(requestId);
        lastRequestId = requestId;
        emit RequestSent(requestId, numWords);
        return requestId;
    }

    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] memory _randomWords
    ) internal override {
        require(s_requests[_requestId].exists, "request not found");
        s_requests[_requestId].fulfilled = true;
        uint256 randomNumber = (_randomWords[0] % 3) + 1;
        s_requests[_requestId].randomNumber = randomNumber;
        emit RequestFulfilled(_requestId, randomNumber);

        calculateWinner(randomNumber, _requestId);
    }

    function getRequestStatus(uint256 _requestId)
        external
        view
        returns (bool fulfilled, uint256 randomNumber)
    {
        require(s_requests[_requestId].exists, "request not found");
        RequestStatus memory request = s_requests[_requestId];
        return (request.fulfilled, request.randomNumber);
    }

    address[] public allowedTokens;
    mapping(address => bool) public allowedTokensMapping;

    function addToken(address _token) public onlyOwner {
        require(!allowedTokensMapping[_token], "token already using");
        allowedTokens.push(_token);
        allowedTokensMapping[_token] = true;
    }

    function getTestTokens(address _token) public {
        uint256 timeDifference = block.timestamp - isClaimedToday[msg.sender];
        require(
            ERC20(_token).balanceOf(address(this)) >= 100 ether,
            "insufficent funds on the contract"
        );
        require(
            timeDifference >= (24 hours),
            "You already claimed some tokens this day"
        );

        (bool sent, ) = _token.call(
            abi.encodeWithSignature(
                "transfer(address,uint256)",
                msg.sender,
                100 ether
            )
        );
        require(sent, "Failed to send token");

        isClaimedToday[msg.sender] = block.timestamp;
    }

    function removeToken(uint256 _index) external onlyOwner {
        require(_index < allowedTokens.length, "index out of range");

        allowedTokensMapping[allowedTokens[_index]] = false;
        for (uint256 i = _index; i < allowedTokens.length - 1; i++) {
            allowedTokens[i] = allowedTokens[i + 1];
        }

        allowedTokens.pop();
    }

    function startGameBnb(uint8 _choice) public payable {
        require(_choice >= 1 && _choice <= 3, "invalid choice");
        require(
            address(this).balance >= msg.value * 2,
            "insufficent funds on the contract"
        );

        uint256 requestId = requestRandomNumber();
        games[requestId] = Game({
            bet: msg.value,
            choice: _choice,
            player: msg.sender,
            token: 0x0000000000000000000000000000000000000000,
            result: 4
        });
    }

    function startGame(
        address _token,
        uint8 _choice,
        uint256 _bet
    ) public {
        require(_choice >= 1 && _choice <= 3, "invalid choice");
        require(allowedTokensMapping[_token] == true, "invalid token");
        require(
            ERC20(_token).allowance(msg.sender, address(this)) >= _bet,
            "need to approve token"
        );
        require(
            ERC20(_token).balanceOf(address(this)) >= _bet * 2,
            "insufficent funds on the contract"
        );
        require(
            ERC20(_token).balanceOf(msg.sender) >= _bet,
            "insufficent funds"
        );

        (bool sent, ) = _token.call(
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                msg.sender,
                address(this),
                _bet
            )
        );
        require(sent, "Failed to send token");

        uint256 requestId = requestRandomNumber();
        games[requestId] = Game({
            bet: _bet,
            choice: _choice,
            player: msg.sender,
            token: _token,
            result: 4
        });
    }

    // 0 is lose, 1 is nobody, 2 is win
    function calculateWinner(uint256 _randomNumber, uint256 _requestId)
        internal
    {
        uint8 choice = games[_requestId].choice;
        uint8 result;

        //calculating result
        if (_randomNumber == choice) result = 1;
        if (_randomNumber == 1) {
            if (choice == 2) result = 0;
            else if (choice == 3) result = 2;
        }
        if (_randomNumber == 2) {
            if (choice == 3) result = 0;
            else if (choice == 1) result = 2;
        }
        if (_randomNumber == 3) {
            if (choice == 1) result = 0;
            else if (choice == 2) result = 2;
        }

        //action with bet
        Game memory game = games[_requestId];
        if (game.token == 0x0000000000000000000000000000000000000000) {
            if (result == 1) {
                (bool sent, ) = game.player.call{value: game.bet}("");
                require(sent, "Failed to send Ether");
            }
            if (result == 2) {
                (bool sent, ) = game.player.call{value: game.bet * 2}("");
                require(sent, "Failed to send Ether");
            }
        } else {
            if (result == 1) {
                (bool sent, ) = game.token.call(
                    abi.encodeWithSignature(
                        "transfer(address,uint256)",
                        game.player,
                        game.bet
                    )
                );
                require(sent, "Failed to send token");
            }
            if (result == 2) {
                (bool sent, ) = game.token.call(
                    abi.encodeWithSignature(
                        "transfer(address,uint256)",
                        game.player,
                        game.bet * 2
                    )
                );
                require(sent, "Failed to send token");
            }
        }

        emit GameEnd(_requestId, game.player, result);
        games[_requestId].result = result;
    }

    function withdraw() public onlyOwner {
        uint256 amount = address(this).balance;
        require(amount > 0, "Nothing to withdraw; contract balance empty");

        address _owner = owner();
        (bool sent, ) = _owner.call{value: amount}("");
        require(sent, "Failed to send Ether");
    }

    function withdrawToken(address _token) public onlyOwner {
        uint256 amount = ERC20(_token).balanceOf(address(this));
        require(amount > 0, "Nothing to withdraw; contract balance empty");

        address _owner = owner();
        (bool sent, ) = _token.call(
            abi.encodeWithSignature("transfer(address,uint256)", _owner, amount)
        );
        require(sent, "Failed to send token");
    }
}