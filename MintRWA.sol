// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

interface IAlpacaOracle {
    function getPrice(address token) external view returns (uint256);
}

contract PaymentMintRWA is Ownable {
    IERC20 public usdtToken;
    AggregatorV3Interface public ethPriceFeed; // ETH/USD
    AggregatorV3Interface public usdtPriceFeed; // USDT/USD
    AggregatorV3Interface public rwaPriceFeed; // RWA price feed (placeholder)
    IAlpacaOracle public alpacaOracle; // Alpaca Finance oracle (optional)
    IRouterClient public ccipRouter; // Chainlink CCIP Router
    IERC20 public dividendToken; // Dividend token (e.g., USDT)
    bytes32 public merkleRoot;

    string public paymentSymbol = "USDT";
    bool public useAlpacaOracle; // Toggle for Alpaca Oracle usage
    mapping(address => uint256) public ethPayments;
    mapping(address => uint256) public usdtPayments;
    mapping(address => mapping(string => uint256)) public balances; // RWA balances
    mapping(address => mapping(string => uint256)) public userMintTimestamps;
    mapping(string => uint256) public totalSupply; // Total supply per RWA
    mapping(address => mapping(address => mapping(string => uint256))) private _allowances; // Allowances
    mapping(string => address[]) public holders; // List of holders per RWA
    mapping(string => mapping(address => bool)) private _isHolder; // Holder status
    mapping(string => uint256) public dividendsPerShare; // Dividends per share
    mapping(string => mapping(address => uint256)) public dividendsWithdrawn; // Withdrawn dividends
    mapping(uint64 => address) public destinationContracts; // CCIP destination contracts

    event PaymentReceived(address indexed user, uint256 amount, string paySymbol);
    event PriceFeedUpdated(address ethPriceFeed, address usdtPriceFeed, address rwaPriceFeed);
    event AlpacaOracleUpdated(address alpacaOracle, bool useAlpaca);
    event MintedWithOracle(address indexed user, string indexed rwaSymbol, uint256 mintedAmount, uint256 timestamp);
    event Burned(address indexed user, string indexed rwaSymbol, uint256 amount, uint256 timestamp);
    event MerkleRootUpdated(bytes32 newRoot);
    event Transferred(address indexed from, address indexed to, string indexed rwaSymbol, uint256 amount);
    event CrossChainTransferInitiated(address indexed from, address indexed to, string indexed rwaSymbol, uint256 amount, uint64 destinationChainSelector, bytes32 messageId);
    event CrossChainTransferReceived(address indexed from, address indexed to, string indexed rwaSymbol, uint256 amount);
    event Approval(address indexed owner, address indexed spender, string indexed rwaSymbol, uint256 amount);
    event DividendsReceived(string indexed rwaSymbol, uint256 amount, uint256 timestamp);
    event DividendsWithdrawn(address indexed holder, string indexed rwaSymbol, uint256 amount);

    constructor(
        address _usdtToken,
        address _ethPriceFeed,
        address _usdtPriceFeed,
        address _rwaPriceFeed,
        address _ccipRouter,
        address _dividendToken,
        address _alpacaOracle,
        bool _useAlpacaOracle
    ) Ownable(msg.sender) {
        usdtToken = IERC20(_usdtToken);
        ethPriceFeed = AggregatorV3Interface(_ethPriceFeed);
        usdtPriceFeed = AggregatorV3Interface(_usdtPriceFeed);
        rwaPriceFeed = AggregatorV3Interface(_rwaPriceFeed);
        ccipRouter = IRouterClient(_ccipRouter);
        dividendToken = IERC20(_dividendToken);
        alpacaOracle = IAlpacaOracle(_alpacaOracle);
        useAlpacaOracle = _useAlpacaOracle;
    }

    function name(string memory rwaSymbol) public pure returns (string memory) {
        return rwaSymbol;
    }

    function symbol(string memory rwaSymbol) public pure returns (string memory) {
        return rwaSymbol;
    }

    function balanceOf(address account, string memory rwaSymbol) public view returns (uint256) {
        return balances[account][rwaSymbol];
    }

    function updatePriceFeeds(address _ethPriceFeed, address _usdtPriceFeed, address _rwaPriceFeed) external onlyOwner {
        ethPriceFeed = AggregatorV3Interface(_ethPriceFeed);
        usdtPriceFeed = AggregatorV3Interface(_usdtPriceFeed);
        rwaPriceFeed = AggregatorV3Interface(_rwaPriceFeed);
        emit PriceFeedUpdated(_ethPriceFeed, _usdtPriceFeed, _rwaPriceFeed);
    }

    function updateAlpacaOracle(address _alpacaOracle, bool _useAlpacaOracle) external onlyOwner {
        alpacaOracle = IAlpacaOracle(_alpacaOracle);
        useAlpacaOracle = _useAlpacaOracle;
        emit AlpacaOracleUpdated(_alpacaOracle, _useAlpacaOracle);
    }

    function updateMintMerkleRoot(bytes32 newRoot) external onlyOwner {
        merkleRoot = newRoot;
        emit MerkleRootUpdated(newRoot);
    }

    function setPaymentSymbol(string calldata newSymbol) external onlyOwner {
        paymentSymbol = newSymbol;
    }

    function payWithETH() external payable {
        require(msg.value > 0, "ETH must be > 0");
        ethPayments[msg.sender] += msg.value;
        emit PaymentReceived(msg.sender, msg.value, "ETH");
    }

    function payWithUSDT(uint256 amount) external {
        require(amount > 0, "Amount must be > 0");
        require(usdtToken.transferFrom(msg.sender, address(this), amount), "USDT transfer failed");
        usdtPayments[msg.sender] += amount;
        emit PaymentReceived(msg.sender, amount, paymentSymbol);
    }

    function getPrice(string memory asset) public view returns (uint256) {
        if (keccak256(abi.encodePacked(asset)) == keccak256(abi.encodePacked("ETH"))) {
            (, int256 price,,,) = ethPriceFeed.latestRoundData();
            require(price > 0, "Invalid ETH price");
            return uint256(price) * 1e10; // Adjust to 18 decimals
        } else if (keccak256(abi.encodePacked(asset)) == keccak256(abi.encodePacked(paymentSymbol))) {
            (, int256 price,,,) = usdtPriceFeed.latestRoundData();
            require(price > 0, "Invalid USDT price");
            return uint256(price) * 1e10; // Adjust to 18 decimals
        } else {
            if (useAlpacaOracle && address(alpacaOracle) != address(0)) {
                // Placeholder: Alpaca Oracle typically requires a token address
                return alpacaOracle.getPrice(address(this)); // Adjust for actual RWA token
            } else {
                (, int256 price,,,) = rwaPriceFeed.latestRoundData();
                require(price > 0, "Invalid RWA price");
                return uint256(price) * 1e10; // Adjust to 18 decimals
            }
        }
    }

    function mintWithOracle(string calldata rwaSymbol, bool useETH, bytes32[] calldata proof) external {
        require(merkleRoot != bytes32(0), "Merkle root not set");
        bytes32 leaf = keccak256(abi.encodePacked(rwaSymbol, ":", useETH ? ethPayments[msg.sender] : usdtPayments[msg.sender]));
        require(MerkleProof.verify(proof, merkleRoot, leaf), "Invalid Merkle proof");

        uint256 payAmount;
        if (useETH) {
            payAmount = ethPayments[msg.sender];
            require(payAmount > 0, "No ETH payment found");
            ethPayments[msg.sender] = 0;
        } else {
            payAmount = usdtPayments[msg.sender];
            require(payAmount > 0, "No USDT payment found");
            usdtPayments[msg.sender] = 0;
        }

        uint256 rwaPrice = getPrice(rwaSymbol);
        uint256 payTokenPrice = useETH ? getPrice("ETH") : getPrice(paymentSymbol);
        uint256 rwaToMint = (payAmount * payTokenPrice) / rwaPrice;
        require(rwaToMint > 0, "Insufficient reserve to mint");

        uint256 mintTimestamp = block.timestamp;
        _updateHolder(msg.sender, rwaSymbol, rwaToMint);
        balances[msg.sender][rwaSymbol] += rwaToMint;
        totalSupply[rwaSymbol] += rwaToMint;
        userMintTimestamps[msg.sender][rwaSymbol] = mintTimestamp;

        emit MintedWithOracle(msg.sender, rwaSymbol, rwaToMint, mintTimestamp);
    }

    function burn(string calldata rwaSymbol, uint256 amount) external {
        require(amount > 0, "Amount must be > 0");
        require(balances[msg.sender][rwaSymbol] >= amount, "Insufficient balance to burn");

        _updateHolder(msg.sender, rwaSymbol, balances[msg.sender][rwaSymbol] - amount);
        balances[msg.sender][rwaSymbol] -= amount;
        totalSupply[rwaSymbol] -= amount;
        userMintTimestamps[msg.sender][rwaSymbol] = block.timestamp;

        emit Burned(msg.sender, rwaSymbol, amount, block.timestamp);
    }

    function transfer(address to, string calldata rwaSymbol, uint256 amount) public returns (bool) {
        require(to != address(0), "Invalid recipient");
        require(balances[msg.sender][rwaSymbol] >= amount, "Insufficient balance");

        _updateHolder(msg.sender, rwaSymbol, balances[msg.sender][rwaSymbol] - amount);
        _updateHolder(to, rwaSymbol, balances[to][rwaSymbol] + amount);
        balances[msg.sender][rwaSymbol] -= amount;
        balances[to][rwaSymbol] += amount;

        emit Transferred(msg.sender, to, rwaSymbol, amount);
        return true;
    }

    function transferCrossChain(
        address to,
        string calldata rwaSymbol,
        uint256 amount,
        uint64 destinationChainSelector
    ) external payable {
        require(destinationContracts[destinationChainSelector] != address(0), "Invalid destination");
        require(balances[msg.sender][rwaSymbol] >= amount, "Insufficient balance");

        _updateHolder(msg.sender, rwaSymbol, balances[msg.sender][rwaSymbol] - amount);
        balances[msg.sender][rwaSymbol] -= amount;
        totalSupply[rwaSymbol] -= amount;

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(destinationContracts[destinationChainSelector]),
            data: abi.encodeWithSelector(
                this.receiveCrossChainTransfer.selector,
                msg.sender,
                to,
                rwaSymbol,
                amount
            ),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: "",
            feeToken: address(0) // Pay with native token
        });

        bytes32 messageId = ccipRouter.ccipSend{value: msg.value}(destinationChainSelector, message);
        emit CrossChainTransferInitiated(msg.sender, to, rwaSymbol, amount, destinationChainSelector, messageId);
    }

    function receiveCrossChainTransfer(address from, address to, string memory rwaSymbol, uint256 amount) external {
        require(msg.sender == address(ccipRouter), "Only CCIP router");
        _updateHolder(to, rwaSymbol, balances[to][rwaSymbol] + amount);
        balances[to][rwaSymbol] += amount;
        totalSupply[rwaSymbol] += amount;
        emit CrossChainTransferReceived(from, to, rwaSymbol, amount);
    }

    function transferFrom(address from, address to, string calldata rwaSymbol, uint256 amount) public returns (bool) {
        require(to != address(0), "Invalid recipient");
        require(balances[from][rwaSymbol] >= amount, "Insufficient balance");
        require(_allowances[from][msg.sender][rwaSymbol] >= amount, "Insufficient allowance");

        _updateHolder(from, rwaSymbol, balances[from][rwaSymbol] - amount);
        _updateHolder(to, rwaSymbol, balances[to][rwaSymbol] + amount);
        balances[from][rwaSymbol] -= amount;
        balances[to][rwaSymbol] += amount;
        _approve(from, msg.sender, _allowances[from][msg.sender][rwaSymbol] - amount, rwaSymbol);

        emit Transferred(from, to, rwaSymbol, amount);
        return true;
    }

    function approve(address spender, string calldata rwaSymbol, uint256 amount) public returns (bool) {
        _approve(msg.sender, spender, amount, rwaSymbol);
        return true;
    }

    function allowance(address owner, address spender, string memory rwaSymbol) public view returns (uint256) {
        return _allowances[owner][spender][rwaSymbol];
    }

    function _approve(address owner, address spender, uint256 amount, string memory rwaSymbol) internal {
        require(owner != address(0), "Invalid owner");
        require(spender != address(0), "Invalid spender");
        _allowances[owner][spender][rwaSymbol] = amount;
        emit Approval(owner, spender, rwaSymbol, amount);
    }

    function receiveDividends(string memory rwaSymbol, uint256 amount) external {
        require(amount > 0, "Amount must be > 0");
        require(dividendToken.transferFrom(msg.sender, address(this), amount), "Dividend transfer failed");
        require(totalSupply[rwaSymbol] > 0, "No RWA tokens issued");

        dividendsPerShare[rwaSymbol] += (amount * 1e18) / totalSupply[rwaSymbol];
        emit DividendsReceived(rwaSymbol, amount, block.timestamp);
    }

    function withdrawDividends(string memory rwaSymbol) external {
        uint256 owed = dividendsOwed(msg.sender, rwaSymbol);
        require(owed > 0, "No dividends to withdraw");

        dividendsWithdrawn[rwaSymbol][msg.sender] = dividendsPerShare[rwaSymbol];
        require(dividendToken.transfer(msg.sender, owed), "Dividend withdrawal failed");
        emit DividendsWithdrawn(msg.sender, rwaSymbol, owed);
    }

    function dividendsOwed(address holder, string memory rwaSymbol) public view returns (uint256) {
        return (balances[holder][rwaSymbol] * (dividendsPerShare[rwaSymbol] - dividendsWithdrawn[rwaSymbol][holder])) / 1e18;
    }

    function setDestinationContract(uint64 chainSelector, address destination) external onlyOwner {
        destinationContracts[chainSelector] = destination;
    }

    function withdrawETH(address payable to, uint256 amount) external onlyOwner {
        require(address(this).balance >= amount, "Insufficient ETH");
        to.transfer(amount);
    }

    function withdrawUSDT(address to, uint256 amount) external onlyOwner {
        require(usdtToken.balanceOf(address(this)) >= amount, "Insufficient USDT");
        require(usdtToken.transfer(to, amount), "USDT transfer failed");
    }

    function _updateHolder(address account, string memory rwaSymbol, uint256 newBalance) internal {
        if (!_isHolder[rwaSymbol][account] && newBalance > 0) {
            holders[rwaSymbol].push(account);
            _isHolder[rwaSymbol][account] = true;
        } else if (_isHolder[rwaSymbol][account] && newBalance == 0) {
            _isHolder[rwaSymbol][account] = false;
            for (uint256 i = 0; i < holders[rwaSymbol].length; i++) {
                if (holders[rwaSymbol][i] == account) {
                    holders[rwaSymbol][i] = holders[rwaSymbol][holders[rwaSymbol].length - 1];
                    holders[rwaSymbol].pop();
                    break;
                }
            }
        }
    }

    receive() external payable {}
}