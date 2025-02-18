// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { DN404 } from "dn404/src/DN404.sol";
import { DN404Mirror } from "dn404/src/DN404Mirror.sol";
import { Ownable } from "solady/auth/Ownable.sol";
import { LibString } from "solady/utils/LibString.sol";
import { FixedPointMathLib } from "solady/utils/FixedPointMathLib.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { MerkleProofLib } from "solady/utils/MerkleProofLib.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IMulticall} from "@uniswap/v3-periphery/contracts/interfaces/IMulticall.sol";

// Add these interface and state variables after the existing interfaces
interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
}
interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function createPair(address tokenA, address tokenB) external returns (address pair);
}
interface IUniswapV2Router02 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity);

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable;

    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts);
}

// Add this interface
interface IERC721Receiver {
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
}

interface IUniswapV3Pool {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function fee() external view returns (uint24);
    function slot0() external view returns (uint160 sqrtPriceX96, int24 tick, uint16 observationIndex, uint16 observationCardinality, uint16 observationCardinalityNext, uint8 feeProtocol, bool unlocked);
    function positions(uint256 tokenId) external view returns (uint128 liquidity, uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128, uint128 tokensOwed0, uint128 tokensOwed1);
    function tickSpacing() external view returns (int24);
}

interface IUniswapV3Factory {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
    function createPool(address tokenA, address tokenB, uint24 fee) external returns (address pool);
}

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}


interface IERC721 {
    function ownerOf(uint256 tokenId) external view returns (address);
}

interface INonfungiblePositionManager {
    function mint(MintParams calldata params) external payable returns (
        uint256 tokenId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );

    function increaseLiquidity(IncreaseLiquidityParams calldata params) external payable returns (uint128 liquidity, uint256 amount0, uint256 amount1);

    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    struct IncreaseLiquidityParams {
        uint256 tokenId;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    function positions(uint256 tokenId)
        external
        view
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        );

    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }
    
    function collect(CollectParams calldata params)
        external
        payable
        returns (uint256 amount0, uint256 amount1);
}


//TEST
import "forge-std/Test.sol";
import "solady/utils/FixedPointMathLib.sol";

contract TEST404 is DN404, Ownable, Test {
    using FixedPointMathLib for uint256;

    address public constant CULT = 0x0000000000c5dc95539589fbD24BE07c6C14eCa4;
    uint256 public constant TAX_RATE = 400; // 4% tax
    address public cultLiquidityPair;

    IUniswapV2Router02 public immutable router;
    IUniswapV2Factory public immutable factory;
    address public liquidityPair;
    address public immutable weth;

    bytes32[] public tierRoots;
    uint256 public immutable LAUNCH_TIME;

    uint256 public totalBondingSupply;
    uint256 public reserve;

    uint256 public constant INITIAL_PRICE = 0.025 ether;   // Base price per 10M tokens
    uint256 public constant MAX_SUPPLY = 4_440_000_000 ether; // 4.44B tokens
    uint256 public constant LIQUIDITY_RESERVE = MAX_SUPPLY * 10 / 100; // 10% reserve for liquidity

        // Constants for operation thresholds
    uint256 public constant MIN_SELL_THRESHOLD = 100 ether;    // 100 tokens minimum for sell
    uint256 public constant MIN_CULT_THRESHOLD = 500 ether;    // 500 tokens minimum for CULT ops
    uint256 public constant MIN_LP_THRESHOLD = 1000 ether;     // 1000 tokens minimum for LP ops

    ISwapRouter public immutable router3;
    IUniswapV3Factory public immutable factory3;
    address public cultPool;
    uint24 public constant POOL_FEE = 10000; // 0.3% fee tier
        // Add state variables
    INonfungiblePositionManager public immutable positionManager;
    int24 public constant TICK_SPACING = 60;
    uint256 public cultV3Position;

    event WhitelistInitialized(bytes32[] roots);

    bool private swapping;
    mapping(uint256 => uint256) public blockSwaps;

    // Modify constructor to include merkle roots
    constructor(bytes32[] memory _tierRoots, address _router, address _router3) {
        require(_tierRoots.length == 12, "Invalid roots length");
        tierRoots = _tierRoots;
        LAUNCH_TIME = block.timestamp;
        router = IUniswapV2Router02(_router);
        router3 = ISwapRouter(_router3);
        factory = IUniswapV2Factory(router.factory());
        factory3 = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984); //mainnet v3 uniswap factory
        positionManager = INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
        weth = router.WETH();

        // Set CULT V3 pool directly
        cultPool = factory3.getPool(CULT, weth, POOL_FEE);
        require(cultPool != address(0), "CULT pool doesn't exist");
        
        emit WhitelistInitialized(_tierRoots);
        address mirror = address(new DN404Mirror(msg.sender));
        _initializeDN404(MAX_SUPPLY, address(this), mirror);
    }

    function getCurrentTier() public view returns (uint256) {
        if (block.timestamp < LAUNCH_TIME) return 0;
        uint256 daysSinceLaunch = (block.timestamp - LAUNCH_TIME) / 1 days;
        return daysSinceLaunch >= tierRoots.length ? tierRoots.length - 1 : daysSinceLaunch;
    }

    function currentRoot() public view returns (bytes32) {
        return tierRoots[getCurrentTier()];
    }

    function isWhitelisted(bytes32[] calldata proof, address account) public view returns (bool) {
        return MerkleProofLib.verify(
            proof,
            currentRoot(),
            keccak256(abi.encodePacked(account))
        );
    }

    modifier whitelistGated(bytes32[] calldata proof) {
        uint256 currentTier = getCurrentTier();
        if (currentTier < tierRoots.length - 1) {
            require(isWhitelisted(proof, msg.sender), "Not whitelisted");
        }
        _;
    }

    function _unit() internal pure override returns (uint256) {
        //1,000,000 $EXEC per Executive
        return 1000000 * 10 ** 18;
    }

    function _tokenURI(uint256 id) internal pure override returns (string memory) {
        return "https://example.com/token/1";
    }

    function name() public view override returns (string memory) {
        return "TEST404";
    }

    function symbol() public view override returns (string memory) {
        return "TEST404";
    }

    /// @dev Override to set skip NFT default to On (true)
    function _skipNFTDefault() internal view override returns (SkipNFTDefault) {
        return SkipNFTDefault.On;
    }

    function balanceMint(uint256 amount) public {
        DN404Storage storage $ = _getDN404Storage();
        AddressData storage addressData = $.addressData[msg.sender];
        
        // Check if they have enough token balance to support the NFTs
        uint256 currentOwnedLength = addressData.ownedLength;
        uint256 maxMintPossible = addressData.balance / _unit() - currentOwnedLength;
        require(amount <= maxMintPossible, "Cannot mint more NFTs than token balance allows");

        // Only flip skipNFT if it's currently true
        bool originalSkipNFT = getSkipNFT(msg.sender);
        if (originalSkipNFT) {
            _setSkipNFT(msg.sender, false);
        }
        
        // Perform a self-transfer to trigger NFT minting
        _transfer(msg.sender, msg.sender, amount * _unit());
        
        // Only flip back if we changed it
        if (originalSkipNFT) {
            _setSkipNFT(msg.sender, true);
        }
    }

    function getPrice(uint256 supply) public pure returns (uint256) {
        uint256 scaledSupply = supply / 1e24;
        uint256 basePrice = INITIAL_PRICE;
        uint256 scaledSupplyWad = scaledSupply * 1e18;
        
        uint256 cubicTerm = FixedPointMathLib.mulWad(
            4 gwei,
            FixedPointMathLib.mulWad(
                FixedPointMathLib.mulWad(scaledSupplyWad, scaledSupplyWad),
                scaledSupplyWad
            )
        );
        
        uint256 quadraticTerm = FixedPointMathLib.mulWad(
            4 gwei,
            FixedPointMathLib.mulWad(scaledSupplyWad, scaledSupplyWad)
        );
        
        uint256 linearTerm = FixedPointMathLib.mulWad(4 gwei, scaledSupplyWad);
        
        return basePrice + cubicTerm + quadraticTerm + linearTerm;
    }

    function calculateIntegral(uint256 lowerBound, uint256 upperBound) internal pure returns (uint256) {
        require(upperBound >= lowerBound, "Invalid bounds");
        return _calculateIntegralFromZero(upperBound) - _calculateIntegralFromZero(lowerBound);
    }

    function _calculateIntegralFromZero(uint256 supply) internal pure returns (uint256) {
        // Scale down supply by 1e25 to match getPrice scaling
        uint256 scaledSupply = supply / 1e25;
        uint256 scaledSupplyWad = scaledSupply * 1e18;
        
        // Integrate base price: 0.025x
        uint256 basePart = (INITIAL_PRICE * supply) / 1e25;
        
        // Integrate 4e-9x^3 -> (4e-9/4)x^4
        uint256 quarticTerm = FixedPointMathLib.mulWad(
            1 gwei, // 4e9/4 = 1e9
            FixedPointMathLib.mulWad(
                FixedPointMathLib.mulWad(
                    FixedPointMathLib.mulWad(scaledSupplyWad, scaledSupplyWad),
                    scaledSupplyWad
                ),
                scaledSupplyWad
            )
        );
        
        // Integrate 4e-9x^2 -> (4e-9/3)x^3
        uint256 cubicTerm = FixedPointMathLib.mulWad(
            FixedPointMathLib.mulDiv(4 gwei, 3, 1e18),  // 4e9/3
            FixedPointMathLib.mulWad(
                FixedPointMathLib.mulWad(scaledSupplyWad, scaledSupplyWad),
                scaledSupplyWad
            )
        );
        
        // Integrate 4e-9x -> (4e-9/2)x^2
        uint256 quadraticTerm = FixedPointMathLib.mulWad(
            2 gwei,  // 4e9/2 = 2e9
            FixedPointMathLib.mulWad(scaledSupplyWad, scaledSupplyWad)
        );
        
        return basePart + quarticTerm + cubicTerm + quadraticTerm;
    }

    function calculateCost(uint256 amount) public view returns (uint256) {
        return calculateIntegral(totalBondingSupply, totalBondingSupply + amount);
    }

    function buyBonding(uint256 amount, uint256 maxCost, bool mintNFT, bytes32[] calldata proof) external payable whitelistGated(proof) {
        require(totalBondingSupply + amount <= MAX_SUPPLY - LIQUIDITY_RESERVE, "Exceeds bonding supply");

        uint256 totalCost = calculateCost(amount);
        require(totalCost <= maxCost, "Slippage exceeded");
        require(msg.value >= totalCost, "Insufficient ETH sent");

        // Only flip skipNFT if it's currently true and user wants to mint
        bool originalSkipNFT = mintNFT ? getSkipNFT(msg.sender) : false;
        if (originalSkipNFT) {
            _setSkipNFT(msg.sender, false);
        }

        _transfer(address(this), msg.sender, amount );
        totalBondingSupply += amount;
        reserve += totalCost;

        // Only flip back if we changed it
        if (originalSkipNFT) {
            _setSkipNFT(msg.sender, true);
        }

        if (msg.value > totalCost) {
            SafeTransferLib.safeTransferETH(msg.sender, msg.value - totalCost);
        }
    }

    function sellBonding(uint256 amount, uint256 minRefund, bytes32[] calldata proof) external whitelistGated(proof) {
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");

        uint256 endSupply = totalBondingSupply - amount;
        uint256 refund = calculateIntegral(endSupply, totalBondingSupply);

        require(refund >= minRefund, "Slippage exceeded");
        require(reserve >= refund, "Insufficient reserve");

        // Calculate tax amounts (4% total tax)
        uint256 totalTax = (refund * 400) / 10000; // 4% tax
        uint256 operatorShare = totalTax / 4;       // 1% of total (25% of tax)
        uint256 protocolTax = totalTax - operatorShare; // 3% of total (75% of tax)
        uint256 userRefund = refund - totalTax;     // Remaining 96%

        // Transfer tokens from user to contract
        _transfer(msg.sender, address(this), amount);
        totalBondingSupply -= amount;
        reserve -= refund;

        // Send operator share to NFT owner
        address operatorOwner = IERC721(0xB24BaB1732D34cAD0A7C7035C3539aEC553bF3a0).ownerOf(598);
        SafeTransferLib.safeTransferETH(operatorOwner, operatorShare);

        // Send user their refund minus taxes
        SafeTransferLib.safeTransferETH(msg.sender, userRefund);

        // Protocol tax stays in contract
    }

    function _initializeCultPoolLogic() private returns (bool) {
        console.log("\n=== Starting CULT Pool Initialization ===");
        console.log("Current cultPool address:", cultPool);
        console.log("Current cultV3Position:", cultV3Position);
        console.log("ETH available:", msg.value);

        if (cultV3Position != 0) {
            console.log("Early exit: Pool or position already exists");
            return false;
        }
        
        if (cultPool == address(0)) {
            console.log("Early exit: Pool doesn't exist");
            return false;
        }

        // Get current tick and calculate proper range
        (uint160 sqrtPriceX96, int24 currentTick,,,,, ) = IUniswapV3Pool(cultPool).slot0();
        int24 tickSpacing = IUniswapV3Pool(cultPool).tickSpacing();
        
        // Calculate ticks ±16 spacing units from current tick
        int24 tickRange = tickSpacing * 16;
        int24 tickLower = ((currentTick - tickRange) / tickSpacing) * tickSpacing;
        int24 tickUpper = ((currentTick + tickRange) / tickSpacing) * tickSpacing;

        console.log("\nPool Info:");
        console.log("Current tick:", currentTick);
        console.log("Tick spacing:", tickSpacing);
        console.log("Lower tick:", tickLower);
        console.log("Upper tick:", tickUpper);

        // Buy CULT with half the ETH
        uint256 ethForPosition = 0.01 ether;
        uint256 halfEth = ethForPosition / 2;
        uint256 cultBought = _buyCultWithExactEth(halfEth);

        // Wrap the other half for the position
        IWETH(weth).deposit{value: halfEth}();

        console.log("\nDebug amounts before mint:");
        console.log("Half ETH (in wei):", halfEth);
        console.log("CULT bought:", cultBought);
        console.log("WETH balance:", IERC20(weth).balanceOf(address(this)));
        console.log("CULT balance:", IERC20(CULT).balanceOf(address(this)));

        // Approve tokens for position manager
        IERC20(CULT).approve(address(positionManager), cultBought);
        IERC20(weth).approve(address(positionManager), halfEth);
        
        console.log("\nAttempting to mint position...");
        try positionManager.mint(INonfungiblePositionManager.MintParams({
            token0: CULT,
            token1: weth,
            fee: POOL_FEE,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: cultBought,
            amount1Desired: halfEth,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp
        })) returns (uint256 tokenId, uint128 v3Liquidity, uint256 amount0, uint256 amount1) {
            cultV3Position = tokenId;
            console.log("\nPosition successfully minted:");
            console.log("Token ID:", tokenId);
            console.log("Liquidity:", v3Liquidity);
            console.log("Amount0 used:", amount0);
            console.log("Amount1 used:", amount1);
            
            // Refund any unused WETH
            uint256 unusedWeth = halfEth - amount1;
            if (unusedWeth > 0) {
                console.log("\nRefunding unused WETH:", unusedWeth);
                IWETH(weth).withdraw(unusedWeth);
            }
            return true;
        } catch Error(string memory reason) {
            console.log("\nMinting failed with reason:", reason);
            IWETH(weth).withdraw(halfEth);
            return false;
        }
    }

    // Keep external version for direct calls if needed
    function initializeCultPool() external payable {
        require(_initializeCultPoolLogic(), "Pool initialization failed");
    }

    function deployLiquidity() external returns (uint256 amountToken, uint256 amountETH, uint256 liquidity) {
        require(block.timestamp >= LAUNCH_TIME + 12 days, "Too early for liquidity deployment");
        require(liquidityPair == address(0), "Liquidity already deployed");
        
        uint256 ethBalance = address(this).balance;
        require(ethBalance > 0, "No ETH to deploy");

        uint256 remainingSupply = MAX_SUPPLY - totalBondingSupply;
        require(remainingSupply > 0, "No tokens to deploy");

        // Create and store the pair address
        liquidityPair = factory.createPair(address(this), weth);

        // Set aside small amount for CULT pool initialization
        uint256 ethForCult = 0.01 ether;
        uint256 ethForV2 = ethBalance - ethForCult;

        // Deploy V2 liquidity first
        _approve(address(this), address(router), remainingSupply);
        (amountToken, amountETH, liquidity) = router.addLiquidityETH{value: ethForV2}(
            address(this),
            remainingSupply,
            0,
            0,
            address(this),
            block.timestamp
        );

        // Try to initialize CULT pool with remaining ETH
        if (!_initializeCultPoolLogic()) {
            console.log("CULT pool initialization failed");
        }

        return (amountToken, amountETH, liquidity);
    }

    // Operation types: 0 = sell EXEC, 1 = buy CULT, 2 = add liquidity
    function _selectOperation() internal view returns (uint256 operation, uint256 amount) {
        uint256 execBalance = balanceOf(address(this));
        uint256 ethBalance = address(this).balance;
        uint256 cultBalance = IERC20(CULT).balanceOf(address(this));

        // Debug logs
        console.log("\nBalances:");
        console.log("EXEC:", execBalance);
        console.log("ETH:", ethBalance);
        console.log("CULT:", cultBalance);

        // Priority 1: If we have EXEC and low ETH, sell EXEC
        if (execBalance >= MIN_SELL_THRESHOLD && ethBalance < 0.01 ether) {
            console.log("Low on ETH, selling EXEC:", execBalance);
            return (0, execBalance);
        }

        // Priority 2: If we have ETH but low CULT, buy CULT with ALL available ETH
        if (ethBalance >= 0.01 ether && cultBalance < MIN_CULT_THRESHOLD) {
            // Use ALL available ETH (minus gas buffer)
            uint256 ethToUse = ethBalance - 0.005 ether; // Leave 0.005 ETH for gas
            console.log("Using all ETH to buy CULT:", ethToUse);
            return (1, ethToUse);
        }

        // Priority 3: If we have both ETH and CULT, add ALL liquidity
        if (ethBalance >= 0.01 ether && cultBalance >= MIN_LP_THRESHOLD) {
            // Get optimal ratio for our ETH
            (uint256 optimalCult,) = _getOptimalCultRatio(ethBalance);
            // Use the maximum amount possible while maintaining ratio
            uint256 cultToUse = cultBalance > optimalCult ? optimalCult : cultBalance;
            console.log("Adding max liquidity with CULT:", cultToUse);
            return (2, cultToUse);
        }

        console.log("No valid operation found");
        return (0, 0);
    }

    // Add this internal function to handle tax logic
    function _beforeTransfer(address from, address to, uint256 amount) internal view returns (uint256) {
        // Don't tax if liquidity pair isn't set yet (initial deployment)
        if (liquidityPair == address(0)) return amount;
        
        // Don't tax if contract is involved in the transfer
        if (from == address(this) || to == address(this)) return amount;
        
        // Apply tax on liquidity pair interactions
        if (to == liquidityPair || from == liquidityPair) {
            uint256 taxAmount = (amount * TAX_RATE) / 10000;
            return amount - taxAmount;
        }
          
        return amount;
    }

    function _processTaxes(address from, address to) internal {
        // Skip if pair isn't initialized yet (for initial liquidity)
        if (liquidityPair == address(0)) return;
        if (from == address(this) || to == address(this)) return;
        
        // Only process on sells (when transferring TO the pair)
        bool isSell = to == liquidityPair;
        if (isSell && !swapping && blockSwaps[block.number] < 3) {
            uint256 existingBalance = balanceOf(address(this));
            if (existingBalance >= MIN_SELL_THRESHOLD) {
                swapping = true;
                (uint256 operation, uint256 amount) = _selectOperation();
                if (operation == 0) {
                    console.log("Selling EXEC");
                    _handleSellTax();
                } else if (operation == 1) {
                    console.log("Buying CULT:", amount);
                    _handleBuyCult(amount);
                } else {
                    console.log("Adding CULT Liquidity");
                    _handleAddCultLiquidity();
                }
                swapping = false;
                blockSwaps[block.number] = blockSwaps[block.number] + 1;
            }
        }
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        // First calculate the tax amount
        uint256 taxAmount = amount - _beforeTransfer(msg.sender, to, amount);
        
        _processTaxes(msg.sender, to);

        // Finally perform the transfers
        if (taxAmount > 0) {
            _transfer(msg.sender, address(this), taxAmount);
        }
        _transfer(msg.sender, to, amount - taxAmount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {

        // Calculate tax and perform transfers
        uint256 taxAmount = amount - _beforeTransfer(from, to, amount);
        
        _processTaxes(from, to);

        if (taxAmount > 0) {
            _transfer(from, address(this), taxAmount);
        }
        return super.transferFrom(from, to, amount - taxAmount);
    }

    function _handleSellTax() internal {
        uint256 tokenBalance = balanceOf(address(this));
        if (tokenBalance < MIN_SELL_THRESHOLD) return;

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = weth;

        _approve(address(this), address(router), tokenBalance);
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenBalance,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function _buyCultWithExactEth(uint256 ethAmount) internal returns (uint256 cultBought) {
        
        // 1. Wrap ETH
        IWETH(weth).deposit{value: ethAmount}();
        
        // 2. Approve WETH
        IERC20(weth).approve(address(router3), ethAmount);
        
        // 3. Swap with 1% fee tier
        bytes memory path = abi.encodePacked(
            weth,
            uint24(10000),  // 1% fee tier
            CULT
        );

        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: path,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: ethAmount,
            amountOutMinimum: 0
        });

        try ISwapRouter(router3).exactInput(params) returns (uint256 amountOut) {
            return amountOut;
        } catch Error(string memory reason) {
            IWETH(weth).withdraw(ethAmount);
            revert(string.concat("Swap failed: ", reason));
        }
    }

    // Helper function to calculate optimal CULT/ETH ratio based on current pool price
    function _getOptimalCultRatio(uint256 ethAmount) internal view returns (uint256 optimalCult, uint256 price) {
        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(cultPool).slot0();
        uint256 priceX96 = uint256(sqrtPriceX96) * uint256(sqrtPriceX96);
        price = (priceX96 * (10**18)) >> 192; // Convert to WAD
        
        // Calculate how much CULT we should have for this amount of ETH
        optimalCult = (ethAmount * price) / 1e18;
    }

    function _handleBuyCult(uint256 ethAmount) internal {
        // Buy CULT with the ETH amount passed in
        _buyCultWithExactEth(ethAmount);
    }

    function _handleAddCultLiquidity() internal {
        uint256 cultBalance = IERC20(CULT).balanceOf(address(this));
        uint256 ethBalance = address(this).balance;
        
        if (cultBalance == 0 || ethBalance < 0.005 ether) {
            return;
        }

        // Use everything except gas buffer
        uint256 ethToUse = ethBalance - 0.005 ether;
        
        uint256 amount0;
        uint256 amount1;
        
        if (CULT < weth) {
            amount0 = cultBalance;    // All CULT
            amount1 = ethToUse;       // All ETH
        } else {
            amount0 = ethToUse;       // All ETH
            amount1 = cultBalance;     // All CULT
        }

        // Get current price for reference
        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(cultPool).slot0();
        uint256 priceX96 = uint256(sqrtPriceX96) * uint256(sqrtPriceX96);
        uint256 price = (priceX96 * 1e18) >> 192;
        
        if (amount0 > 0 && amount1 > 0.01 ether) {
            console.log("=== Adding Liquidity ===");
            _increaseCultLiquidity(amount0, amount1);
        }
    }

    /// @dev Override receive to accept ETH transfers
    receive() external payable override {
    // Accept ETH transfers silently
    }

    // Add this function to the contract
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata
    ) external returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
  
  
    function _increaseCultLiquidity(uint256 cultAmount, uint256 ethAmount) internal returns (bool) {

        if (cultV3Position == 0) {
            console.log("No existing position to increase");
            return false;
        }

        // Wrap ETH
        IWETH(weth).deposit{value: ethAmount}();
        
        // Approve tokens
        IERC20(CULT).approve(address(positionManager), cultAmount);
        IERC20(weth).approve(address(positionManager), ethAmount);

        try positionManager.increaseLiquidity(INonfungiblePositionManager.IncreaseLiquidityParams({
            tokenId: cultV3Position,
            amount0Desired: CULT < weth ? cultAmount : ethAmount,
            amount1Desired: CULT < weth ? ethAmount : cultAmount,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp
        })) returns (uint128 liquidity, uint256 amount0, uint256 amount1) {

            // Unwrap any unused WETH
            uint256 unusedWeth = IERC20(weth).balanceOf(address(this));
            if (unusedWeth > 0) {
                IWETH(weth).withdraw(unusedWeth);
            }
            return true;
        } catch Error(string memory reason) {
            console.log("\nIncreasing liquidity failed:", reason);
            // Unwrap WETH on failure
            IWETH(weth).withdraw(ethAmount);
            return false;
        }
    }

    /// @notice Collects fees from the V3 liquidity position
    /// @dev Only callable by the owner of OPERATOR_TOKEN_ID
    /// @param amount0Max The maximum amount of token0 to collect
    /// @param amount1Max The maximum amount of token1 to collect
    /// @return amount0 The amount of token0 collected
    /// @return amount1 The amount of token1 collected
    function collectV3Fees(uint128 amount0Max, uint128 amount1Max) external payable returns (uint256 amount0, uint256 amount1) {
        // Check if caller owns the operator token
        require(IERC721(0xB24BaB1732D34cAD0A7C7035C3539aEC553bF3a0).ownerOf(598) == msg.sender, "Not operator token owner");
        
        // Require at least one amount to be non-zero (matching V3 requirement)
        require(amount0Max > 0 || amount1Max > 0, "Amount0Max and amount1Max cannot both be 0");
        
        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager
            .CollectParams({
                tokenId: cultV3Position,
                recipient: msg.sender,
                amount0Max: amount0Max,
                amount1Max: amount1Max
            });
            
        // Assuming V3_POSITION_MANAGER is defined somewhere in the contract
        (amount0, amount1) = INonfungiblePositionManager(positionManager).collect{value: msg.value}(params);
        
        emit V3FeesCollected(msg.sender, amount0, amount1);
    }

    /// @notice Emitted when V3 fees are collected
    event V3FeesCollected(address indexed collector, uint256 amount0, uint256 amount1);


    /*
    This contract needs

    X1. sequential merkle tree by day, 12 days
    X2. Automatic liquidity deployment after 12 days of presale bonding curve
    X3. buy/sell tax to pool that are converted to liqudiity for $CULT
    X4. setSkipNFT default true 
    X5. balanceMint 
    X6. ability for the owner of a specified NFT to collect the fees from the liquidity position
    7. in deploying liquidity, a fraction must go to the owner of that same NFT

    */

}
