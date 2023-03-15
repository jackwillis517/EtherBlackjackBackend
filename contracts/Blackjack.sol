// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";

contract Blackjack is VRFConsumerBaseV2, ConfirmedOwner {
    event RequestSent(uint256 requestId, uint32 numWords);
    event RequestFulfilled(uint256 requestId, uint256[] randomWords);
    event PlayerAdded(address indexed player, uint256 betAmount);
    event PlayerWon(address indexed player, uint256 winnings);
    event PlayerLost(address indexed player);

    modifier canAddNewPlayer() {
        require(
            currentPlayer == address(0),
            "A new player cannot be added at this time."
        );
        _;
    }

    struct RequestStatus {
        bool fulfilled;
        bool exists;
        uint256[] randomWords;
    }

    mapping(uint256 => RequestStatus) public s_requests;
    mapping(uint256 => uint256) public cards;
    mapping(address => uint256) bets;

    uint256[] public dealersHand;
    uint256[] public playersHand;
    uint256[] public requestIds;

    VRFCoordinatorV2Interface COORDINATOR;
    uint256 public lastRequestId;
    uint256 cardIdx = 4;
    bytes32 keyHash =
        0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c;
    uint64 s_subscriptionId;
    uint32 callbackGasLimit = 100000;
    uint32 numWords = 52;
    uint16 requestConfirmations = 3;
    bool canRefund = true;
    address currentPlayer;

    /**
     * HARDCODED FOR SEPOLIA
     * COORDINATOR: 0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625
     */
    constructor(
        uint64 subscriptionId,
        address VRFCoordinator
    ) VRFConsumerBaseV2(VRFCoordinator) ConfirmedOwner(msg.sender) {
        COORDINATOR = VRFCoordinatorV2Interface(VRFCoordinator);
        s_subscriptionId = subscriptionId;

        // Mapping each numerical representation of a card to its value
        cards[1] = 2;
        cards[2] = 3;
        cards[3] = 4;
        cards[4] = 5;
        cards[5] = 6;
        cards[6] = 7;
        cards[7] = 8;
        cards[8] = 9;
        cards[9] = 10;
        cards[10] = 10;
        cards[11] = 10;
        cards[12] = 10;
        cards[14] = 2;
        cards[15] = 3;
        cards[16] = 4;
        cards[17] = 5;
        cards[18] = 6;
        cards[19] = 7;
        cards[20] = 8;
        cards[21] = 9;
        cards[22] = 10;
        cards[23] = 10;
        cards[24] = 10;
        cards[25] = 10;
        cards[27] = 2;
        cards[28] = 3;
        cards[29] = 4;
        cards[30] = 5;
        cards[31] = 6;
        cards[32] = 7;
        cards[33] = 8;
        cards[34] = 9;
        cards[35] = 10;
        cards[36] = 10;
        cards[37] = 10;
        cards[38] = 10;
        cards[40] = 2;
        cards[41] = 3;
        cards[42] = 4;
        cards[43] = 5;
        cards[44] = 6;
        cards[45] = 7;
        cards[46] = 8;
        cards[47] = 9;
        cards[48] = 10;
        cards[49] = 10;
        cards[50] = 10;
        cards[51] = 10;
    }

    function requestRandomWords() internal returns (uint256 requestId) {
        requestId = COORDINATOR.requestRandomWords(
            keyHash,
            s_subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );
        s_requests[requestId] = RequestStatus({
            randomWords: new uint256[](0),
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
        s_requests[_requestId].randomWords = _randomWords;
        emit RequestFulfilled(_requestId, _randomWords);
        dealInitialCards();
        canRefund = false;
    }

    function getRequestStatus(
        uint256 _requestId
    ) external view returns (bool fulfilled, uint256[] memory randomWords) {
        require(s_requests[_requestId].exists, "request not found");
        RequestStatus memory request = s_requests[_requestId];
        return (request.fulfilled, request.randomWords);
    }

    function addPlayer() public payable canAddNewPlayer {
        require(msg.value >= 10000000000000, "Your bet is too low!");
        require(msg.value <= 100000000000000, "Your bet is too high!");
        bets[msg.sender] += msg.value;
        requestRandomWords();
        emit PlayerAdded(msg.sender, msg.value);
    }

    // Deals the initial two cards to the dealer and player
    function dealInitialCards() internal {
        playersHand.push(s_requests[lastRequestId].randomWords[0] % 52);
        playersHand.push(s_requests[lastRequestId].randomWords[1] % 52);
        dealersHand.push(s_requests[lastRequestId].randomWords[2] % 52);
        dealersHand.push(s_requests[lastRequestId].randomWords[3] % 52);
    }

    // Allows the player to request a hit
    function hit() public {
        require(
            msg.sender == currentPlayer,
            "Only the current player can request a hit."
        );
        playersHand.push(s_requests[lastRequestId].randomWords[cardIdx++] % 52);
    }

    // Allows the player to stand and determine if they beat the dealer or not
    function stand() public payable {
        // Get the hand value for the player and dealer
        uint playerCount = sumPlayersHand();
        uint dealerCount = sumDealersHand();

        // If the dealer > 21 and player isn't | player wins
        // If the dealers hand < players hand | player wins
        if (
            (dealerCount > 21 && playerCount <= 21) ||
            (dealerCount < 21 && playerCount < 21 && dealerCount < playerCount)
        ) {
            uint256 betAmount = bets[msg.sender];
            bets[msg.sender] = 0;
            (bool sent, ) = payable(msg.sender).call{value: betAmount * 2}("");
            emit PlayerWon(msg.sender, betAmount * 2);
            if (!sent) {
                canRefund = true;
            }

            // If the dealers hand == the players hand | draw
            // If both the dealers and players hands are bust | draw
        } else if (
            (dealerCount > 21 && playerCount > 21) ||
            (dealerCount == playerCount)
        ) {
            uint256 betAmount = bets[msg.sender];
            bets[msg.sender] = 0;
            (bool sent, ) = payable(msg.sender).call{value: betAmount}("");
            emit PlayerLost(msg.sender);
            if (!sent) {
                canRefund = true;
            }
        }
        // If the dealers hand > players hand | player loses
        // If the player > 21 and the dealer isn't | player loses

        // Reset both hands, the card index variable and the currentPlayer
        cardIdx = 4;
        currentPlayer = address(0);
        delete dealersHand;
        delete playersHand;
    }

    // Calculates the total card value of the players hand array
    function sumPlayersHand() internal view returns (uint256) {
        uint256 playerTotal = 0;
        uint256 aceTotal = 0;
        for (uint i = 0; i < playersHand.length; i++) {
            // If the players card is an ace skip and add all non-aces to total
            if (
                playersHand[i] == 0 ||
                playersHand[i] == 13 ||
                playersHand[i] == 26 ||
                playersHand[i] == 39
            ) {
                aceTotal++;
                continue;
            } else {
                playerTotal += cards[playersHand[i]];
            }
        }
        // Add the largest ace value that can fit without busting for every ace in the players hand
        for (uint i = 0; i < aceTotal; i++) {
            if (playerTotal + 11 > 21) {
                playerTotal += 1;
            } else {
                playerTotal += 11;
            }
        }
        return playerTotal;
    }

    // Calculates the total card value of the dealers hand array and adds another card if their hand sums to less then 17
    function sumDealersHand() internal returns (uint256) {
        uint256 dealerTotal = 0;
        dealerTotal += cards[dealersHand[0]];
        dealerTotal += cards[dealersHand[1]];
        if (dealerTotal < 17) {
            dealersHand.push(
                s_requests[lastRequestId].randomWords[cardIdx++] % 52
            );
            dealerTotal += cards[dealersHand[2]];
        }
        return dealerTotal;
    }

    // If an error occurs with the VRFCoordinator or the contract doesn't have enough liquidity this allows the user to request a refund
    function getRefund() public payable {
        require(
            msg.sender == currentPlayer && bets[currentPlayer] > 0,
            "Only the current player with a positive bet can call this"
        );
        require(canRefund, "You cannot request a refund at this time.");
        uint256 funds = bets[msg.sender];
        bets[msg.sender] = 0;
        (bool sent, ) = payable(msg.sender).call{value: funds}("");
        require(sent, "Failed to process refund.");
    }

    function getDealersHand() external view returns (uint256[] memory) {
        return dealersHand;
    }

    function getPlayersHand() external view returns (uint256[] memory) {
        return playersHand;
    }

    function getCurrentPlayer() external view returns (address) {
        return currentPlayer;
    }

    function getCurrentPlayersBet() external view returns (uint256) {
        return bets[currentPlayer];
    }
}
