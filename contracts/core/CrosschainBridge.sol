// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract CrossChainBridge is Ownable {
    IRouterClient public ccipRouter;
    mapping(uint64 => address) public destinationContracts; // Chain selector to destination contract
    mapping(bytes32 => bool) public processedMessages;

    event TokensBridged(address indexed user, address token, uint256 amount, uint64 destinationChain, bytes32 messageId);
    event CrossChainSwapInitiated(address indexed user, address tokenIn, uint256 amountIn, uint64 destinationChain);
    event CrossChainLoanRequested(address indexed user, address collateralToken, uint256 collateralAmount, uint64 destinationChain);
    event CrossChainRWAMinted(address indexed user, string rwaSymbol, uint256 amount, uint64 destinationChain);

    constructor(address _ccipRouter) Ownable(msg.sender) {
        ccipRouter = IRouterClient(_ccipRouter);
    }

    function setDestinationContract(uint64 chainSelector, address destination) external onlyOwner {
        destinationContracts[chainSelector] = destination;
    }

    function bridgeTokens(address token, uint256 amount, uint64 destinationChainSelector, address receiver) external payable {
        require(destinationContracts[destinationChainSelector] != address(0), "Invalid destination");
        require(IERC20(token).transferFrom(msg.sender, address(this), amount), "Token transfer failed");

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(destinationContracts[destinationChainSelector]),
            data: abi.encode(msg.sender, token, amount, receiver),
            tokenAmounts: new Client.EVMTokenAmount[](1),
            extraArgs: "",
            feeToken: address(0) 
        });

        message.tokenAmounts[0] = Client.EVMTokenAmount({token: token, amount: amount});

        bytes32 messageId = ccipRouter.ccipSend{value: msg.value}(destinationChainSelector, message);
        processedMessages[messageId] = true;

        emit TokensBridged(msg.sender, token, amount, destinationChainSelector, messageId);
    }

    function initiateCrossChainSwap(address tokenIn, uint256 amountIn, uint64 destinationChainSelector, address recipient) external payable {
        require(destinationContracts[destinationChainSelector] != address(0), "Invalid destination");
        require(IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn), "Token transfer failed");

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(destinationContracts[destinationChainSelector]),
            data: abi.encodeWithSelector(bytes4(keccak256("executeCrossChainSwap(address,address,uint256,address)")),
                msg.sender, tokenIn, amountIn, recipient),
            tokenAmounts: new Client.EVMTokenAmount[](1),
            extraArgs: "",
            feeToken: address(0)
        });

        message.tokenAmounts[0] = Client.EVMTokenAmount({token: tokenIn, amount: amountIn});
        bytes32 messageId = ccipRouter.ccipSend{value: msg.value}(destinationChainSelector, message);

        emit CrossChainSwapInitiated(msg.sender, tokenIn, amountIn, destinationChainSelector);
    }

    function requestCrossChainLoan(address collateralToken, uint256 collateralAmount, uint64 destinationChainSelector, address tokenToBorrow, uint256 borrowAmount) external payable {
        require(destinationContracts[destinationChainSelector] != address(0), "Invalid destination");
        require(IERC20(collateralToken).transferFrom(msg.sender, address(this), collateralAmount), "Collateral transfer failed");

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(destinationContracts[destinationChainSelector]),
            data: abi.encodeWithSelector(bytes4(keccak256("executeCrossChainLoan(address,address,uint256,address,uint256)")),
                msg.sender, collateralToken, collateralAmount, tokenToBorrow, borrowAmount),
            tokenAmounts: new Client.EVMTokenAmount[](1),
            extraArgs: "",
            feeToken: address(0)
        });

        message.tokenAmounts[0] = Client.EVMTokenAmount({token: collateralToken, amount: collateralAmount});
        bytes32 messageId = ccipRouter.ccipSend{value: msg.value}(destinationChainSelector, message);

        emit CrossChainLoanRequested(msg.sender, collateralToken, collateralAmount, destinationChainSelector);
    }

    function mintCrossChainRWA(string memory rwaSymbol, uint256 amount, uint64 destinationChainSelector, address recipient) external payable {
        require(destinationContracts[destinationChainSelector] != address(0), "Invalid destination");

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(destinationContracts[destinationChainSelector]),
            data: abi.encodeWithSelector(bytes4(keccak256("executeCrossChainRWAMint(address,string,uint256,address)")),
                msg.sender, rwaSymbol, amount, recipient),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: "",
            feeToken: address(0)
        });

        bytes32 messageId = ccipRouter.ccipSend{value: msg.value}(destinationChainSelector, message);

        emit CrossChainRWAMinted(msg.sender, rwaSymbol, amount, destinationChainSelector);
    }

    function receiveMessage(Client.Any2EVMMessage memory message) external {
        require(msg.sender == address(ccipRouter), "Only CCIP router");
        require(!processedMessages[message.messageId], "Message already processed");
        processedMessages[message.messageId] = true;
        (bool success,) = address(this).call(message.data);
        require(success, "Message execution failed");
    }
}