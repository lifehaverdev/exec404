// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { DN404 } from "dn404/src/DN404.sol";
import { DN404Mirror } from "dn404/src/DN404Mirror.sol";
import { FixedPointMathLib } from "solady/utils/FixedPointMathLib.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { MerkleProofLib } from "solady/utils/MerkleProofLib.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IMulticall} from "@uniswap/v3-periphery/contracts/interfaces/IMulticall.sol";

//import "forge-std/Test.sol";

// Add these interface and state variables after the existing interfaces
// interface IERC20 {
//     function balanceOf(address account) external view returns (uint256);
//     function transfer(address to, uint256 amount) external returns (bool);
//     function approve(address spender, uint256 amount) external returns (bool);
//     function allowance(address owner, address spender) external view returns (uint256);
// }
// interface IUniswapV2Factory {
//     function getPair(address tokenA, address tokenB) external view returns (address pair);
//     function createPair(address tokenA, address tokenB) external returns (address pair);
// }
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
    //function slot0() external view returns (uint160 sqrtPriceX96, int24 tick, uint16 observationIndex, uint16 observationCardinality, uint16 observationCardinalityNext, uint8 feeProtocol, bool unlocked);
    function positions(uint256 tokenId) external view returns (uint128 liquidity, uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128, uint128 tokensOwed0, uint128 tokensOwed1);
    //function tickSpacing() external view returns (int24);
}

// interface IUniswapV3Factory {
//     function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
//     function createPool(address tokenA, address tokenB, uint24 fee) external returns (address pool);
// }

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

contract EXEC404 is DN404 {
    using FixedPointMathLib for uint256;

    address public constant CULT = 0x0000000000c5dc95539589fbD24BE07c6C14eCa4;
    uint256 public constant TAX_RATE = 400; // 4% tax
    address public cultLiquidityPair;

    IUniswapV2Router02 public immutable router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    ISwapRouter public immutable router3 = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    INonfungiblePositionManager public immutable positionManager = INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    //IUniswapV2Factory public immutable factory;
    address public immutable factory;
    //IUniswapV3Factory public immutable factory3 = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    address public constant factory3 = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

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
    
    address public cultPool;
    uint24 public constant POOL_FEE = 10000; // 0.3% fee tier
    
    int24 public constant TICK_SPACING = 60;
    uint256 public cultV3Position;

    event WhitelistInitialized(bytes32[] roots);

    bool private swapping;
    mapping(uint256 => uint256) public blockSwaps;

    struct BondingMessage {
        address sender;      // 20 bytes
        uint96 packedData;  // 12 bytes (contains timestamp:32 | amount:63 | isBuy:1)
        string message;     // variable length
    }

    mapping(uint256 => BondingMessage) public bondingMessages;
    uint256 public totalMessages;

    // Helper functions for packing/unpacking data
    function packData(uint32 timestamp, uint64 amount, bool isBuy) internal pure returns (uint96) {
        return uint96(
            (uint96(timestamp) << 64) |  // timestamp in highest 32 bits
            (uint96(amount) << 1) |      // amount in middle 63 bits
            (isBuy ? 1 : 0)             // isBuy flag in lowest bit
        );
    }

    function unpackData(uint96 packed) internal pure returns (uint32 timestamp, uint64 amount, bool isBuy) {
        timestamp = uint32(packed >> 64);
        amount = uint64(packed >> 1);
        isBuy = packed & 1 == 1;
    }

    // Modify constructor to include merkle roots
    constructor(bytes32[] memory _tierRoots) {
        require(_tierRoots.length == 12, "Invalid roots length");
        tierRoots = _tierRoots;
        LAUNCH_TIME = block.timestamp;
        //factory = IUniswapV2Factory(router.factory());
        factory = router.factory();
        weth = router.WETH();

        // Set CULT V3 pool directly
        //cultPool = factory3.getPool(CULT, weth, POOL_FEE);
        (,bytes memory d) = factory3.staticcall(abi.encodeWithSelector(0x1698ee82, CULT, weth, POOL_FEE));
        cultPool = abi.decode(d, (address));
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
            // keccak256(abi.encodePacked(account))
            keccak256(abi.encodePacked(bytes20(account)))
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

    function name() public pure override returns (string memory) {
        return "TEST404";
    }

    function symbol() public pure override returns (string memory) {
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
        // Scale down by 1e26 (divide by 100T tokens) to get into a manageable range
        // This means 4.44B tokens becomes 44.4
        // uint256 scaledSupply = supply / 1e25;
        // uint256 scaledSupplyWad = scaledSupply * 1e18;
        uint256 scaledSupplyWad = supply / 1e7;
        
        // Calculate terms with scaled numbers
        uint256 cubicTerm = FixedPointMathLib.mulWad(
            12 gwei,
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
        
        return INITIAL_PRICE + cubicTerm + quadraticTerm + linearTerm;
    }

    function getExecForEth(uint256 ethAmount) public view returns (uint256 execAmount) {
        // If price is too low, return max possible
        uint256 remainingSupply = MAX_SUPPLY - LIQUIDITY_RESERVE - totalBondingSupply;
        if (calculateCost(remainingSupply) <= ethAmount) {
            return remainingSupply;
        }

        // Binary search for the amount of EXEC that costs closest to ethAmount
        uint256 low = 0;
        uint256 high = remainingSupply;
        
        while (low < high) {
            uint256 mid = (low + high + 1) / 2;
            uint256 cost = calculateCost(mid);
            
            if (cost <= ethAmount) {
                low = mid;
            } else {
                high = mid - 1;
            }
        }
        
        return low;
    }

    function getEthForExec(uint256 execAmount) public view returns (uint256 ethAmount) {
        require(execAmount <= totalBondingSupply, "Amount exceeds bonding supply");
        return calculateRefund(execAmount);
    }

    function calculateIntegral(uint256 lowerBound, uint256 upperBound) internal pure returns (uint256) {
        require(upperBound >= lowerBound, "Invalid bounds");
        return _calculateIntegralFromZero(upperBound) - _calculateIntegralFromZero(lowerBound);
    }

    function _calculateIntegralFromZero(uint256 supply) internal pure returns (uint256) {
        // Scale down to hundreds since price curve is per 10M tokens
        // uint256 scaledSupply = supply / 1e26;
        // uint256 scaledSupplyWad = scaledSupply * 1e18;
        uint256 scaledSupplyWad = supply / 1e7;
        
        // Base price integral dewadded by 1e18
        uint256 basePart = INITIAL_PRICE * scaledSupplyWad / 1e18;
        
        // Calculate integral terms with scaled numbers
        uint256 quarticTerm = FixedPointMathLib.mulWad(
            //12 / 4 
            3 gwei,
            FixedPointMathLib.mulWad(
                FixedPointMathLib.mulWad(
                    FixedPointMathLib.mulWad(scaledSupplyWad, scaledSupplyWad),
                    scaledSupplyWad
                ),
                scaledSupplyWad
            )
        );
        
        uint256 cubicTerm = FixedPointMathLib.mulWad(
            1333333333, //4/3 * 1gwei
            FixedPointMathLib.mulWad(
                FixedPointMathLib.mulWad(scaledSupplyWad, scaledSupplyWad),
                scaledSupplyWad
            )
        );
        
        uint256 quadraticTerm = FixedPointMathLib.mulWad(
            2 gwei,
            FixedPointMathLib.mulWad(scaledSupplyWad, scaledSupplyWad)
        );
        
        // Scale the result back up by 1e8
        return basePart + quarticTerm + cubicTerm + quadraticTerm;
    }

    function calculateCost(uint256 amount) public view returns (uint256) {
        return calculateIntegral(totalBondingSupply, totalBondingSupply + amount);
    }

    function calculateRefund(uint256 amount) public view returns (uint256) {
        return calculateIntegral(totalBondingSupply - amount, totalBondingSupply);
    }

    function buyBonding(
        uint256 amount, 
        uint256 maxCost, 
        bool mintNFT, 
        bytes32[] calldata proof,
        string calldata message
    ) external payable whitelistGated(proof) {
        // Check for overflow before adding
        require(totalBondingSupply <= MAX_SUPPLY - LIQUIDITY_RESERVE - amount, "Exceeds bonding supply");
        uint256 totalCost = calculateCost(amount);
        require(maxCost >= totalCost, "Cost exceeds maxCost");
        require(msg.value >= totalCost, "Insufficient ETH sent");

        // Only flip skipNFT if it's currently true and user wants to mint
        bool originalSkipNFT = mintNFT ? getSkipNFT(msg.sender) : false;
        if (originalSkipNFT) {
            _setSkipNFT(msg.sender, false);
        }

        _transfer(address(this), msg.sender, amount);
        totalBondingSupply += amount;
        reserve += totalCost;

        // Store message if provided
        if (bytes(message).length > 0) {
            uint64 scaledAmount = uint64(amount / 1e18);
            require(scaledAmount <= type(uint64).max, "Amount too large for message storage");
            
            bondingMessages[totalMessages++] = BondingMessage({
                sender: msg.sender,
                packedData: packData(
                    uint32(block.timestamp),
                    scaledAmount,
                    true  // isBuy
                ),
                message: message
            });
        }

        // Only flip back if we changed it
        if (originalSkipNFT) {
            _setSkipNFT(msg.sender, true);
        }

        if (msg.value > totalCost) {
            SafeTransferLib.safeTransferETH(msg.sender, msg.value - totalCost);
        }
    }

    function sellBonding(
        uint256 amount, 
        uint256 minRefund, 
        bytes32[] calldata proof,
        string calldata message
    ) external whitelistGated(proof) {
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");

        // Calculate refund and validate
        uint256 refund = calculateRefund(amount);
        require(refund >= minRefund && reserve >= refund, "Invalid refund");

        // Transfer tokens first
        _transfer(msg.sender, address(this), amount);
        totalBondingSupply -= amount;
        reserve -= refund;

        // Store message if provided
        if (bytes(message).length > 0) {
            require(amount / 1 ether <= type(uint64).max, "Amount too large for message storage");
            bondingMessages[totalMessages++] = BondingMessage({
                sender: msg.sender,
                packedData: packData(
                    uint32(block.timestamp),
                    uint64(amount  /  1 ether),
                    false  // isBuy
                ),
                message: message
            });
        }

        // Calculate and distribute refund with tax (4% total tax)
        // 1% to operator (25% of tax), 3% to protocol (75% of tax)
        uint256 userRefund = (refund * 9600) / 10000; // 96% to user
        SafeTransferLib.safeTransferETH(
            IERC721(0xB24BaB1732D34cAD0A7C7035C3539aEC553bF3a0).ownerOf(598), 
            (refund * 100) / 10000  // 1% to operator
        );
        SafeTransferLib.safeTransferETH(msg.sender, userRefund);
    }

    /// @notice Reads sqrtPriceX96 and tick from a Uniswap V3 pool using a static call
    /// @param pool The address of the V3 pool
    /// @return sqrtPriceX96 The current price as a Q64.96
    /// @return tick The current tick function _staticcallSlot0Values(ad
    function _staticcallSlot0Values(address pool) internal view returns (uint160 sqrtPriceX96, int24 tick) {
        // slot0() function selector: 3850c7bd
        assembly {
            // Prepare calldata for staticcall (4 bytes for function selector)
            mstore(0x0, 0x3850c7bd00000000000000000000000000000000000000000000000000000000)
            
            // Perform staticcall
            // First 32 bytes: sqrtPriceX96 (uint160)
            // Next 32 bytes: tick (int24)
            let success := staticcall(gas(), pool, 0x0, 0x4, 0x0, 0x40)
            
            // Revert if call failed
            if iszero(success) {
                revert(0, 0)
            }

            // Load results
            sqrtPriceX96 := mload(0x0)    // First 32 bytes contain sqrtPriceX96
            tick := mload(0x20)           // Next 32 bytes contain tick
        }
    }

    function _staticcallTickSpacing(address pool) internal view returns (int24 spacing) {
        assembly {
            // Store the function selector for tickSpacing()
            mstore(0, 0xd0c93a7c00000000000000000000000000000000000000000000000000000000)
            
            // Make the call
            let success := staticcall(gas(), pool, 0, 4, 0, 32)
            if iszero(success) { revert(0, 0) }
            
            // Load the result
            spacing := mload(0)
        }
    }

    function _initializeCultPoolLogic() private returns (bool) {
        
        if (cultV3Position != 0 || cultPool == address(0)) {
            return false;
        }

        // Get current tick and calculate proper range
        //(, int24 currentTick) = _staticcallSlot0Values(cultPool);
        int24 tickSpacing = _staticcallTickSpacing(cultPool);

        //interface way
        //(, int24 currentTick,,,,, ) = IUniswapV3Pool(cultPool).slot0();
            //staticcall way optimized
            (uint160 sqrtPriceX96,int24 currentTick) = _staticcallSlot0Values(cultPool);
            // console.log("staticcall version - sqrtPrice:", sqrtPriceX96);
            // console.log("staticcall version - tick:", currentTick);
        // low level call abi decode way
        //(,bytes memory d) = cultPool.staticcall(abi.encodeWithSelector(0x3850c7bd));
        //(uint160 sqrtPriceX96, int24 currentTick,,,,,) = abi.decode(d, (uint160,int24,uint16,uint16,uint16,uint8,bool));
        // console.log("low level version - sqrtPrice:", sqrtPriceX96);
        // console.log("low level version - tick:", currentTick);
        // First let's log everything from the working version
        //(,bytes memory d) = cultPool.staticcall(abi.encodeWithSelector(0x3850c7bd));
        //console.log("Low level call - raw data length:", d.length);
        // Log the raw bytes in 32-byte chunks
        // for(uint i = 0; i < d.length; i += 32) {
        //     bytes32 chunk;
        //     assembly {
        //         chunk := mload(add(add(d, 32), i))
        //     }
        //     console.log("Chunk %s:", i / 32, uint256(chunk));
        // }
        // // Then decode and log the actual values
        // (uint160 sqrtPriceX96, int24 currentTick,,,,,) = abi.decode(d, (uint160,int24,uint16,uint16,uint16,uint8,bool));
        // console.log("After decode - sqrtPrice:", sqrtPriceX96);
        // console.log("After decode - tick:", currentTick);

        // Now let's compare with our assembly version
        //(uint160 price2, int24 tick2) = _staticcallSlot0Values(cultPool);
        //console.log("Assembly version - sqrtPrice:", price2);
        //console.log("Assembly version - tick:", tick2);

        
        //int24 tickSpacing = IUniswapV3Pool(cultPool).tickSpacing();
        // (,bytes memory d2) = cultPool.staticcall(abi.encodeWithSelector(0xd0c93a7c));
        // int24 tickSpacing = abi.decode(d2, (int24));
        
        // Calculate ticks ±16 spacing units from current tick
        int24 tickRange = tickSpacing * 16;
        //int24 tickLower = ((currentTick - tickRange) / tickSpacing) * tickSpacing;
        //int24 tickUpper = ((currentTick + tickRange) / tickSpacing) * tickSpacing;

        // Buy CULT with half the ETH
        uint256 cultBought = _buyCultWithExactEth(0.005 ether);

        // Wrap the other half for the position
        IWETH(weth).deposit{value: 0.005 ether}();

        // Approve tokens for position manager
        //IERC20(CULT).approve(address(positionManager), cultBought);
        (bool s,) = (CULT).call(abi.encodeWithSelector(0x095ea7b3, address(positionManager), cultBought)); require(s);
        //IERC20(weth).approve(address(positionManager), halfEth);
        (bool s2,) = (weth).call(abi.encodeWithSelector(0x095ea7b3, address(positionManager), 0.005 ether)); require(s2);
        
        try positionManager.mint(INonfungiblePositionManager.MintParams({
            token0: CULT,
            token1: weth,
            fee: POOL_FEE,
            tickLower: ((currentTick - tickRange) / tickSpacing) * tickSpacing,
            tickUpper: ((currentTick + tickRange) / tickSpacing) * tickSpacing,
            amount0Desired: cultBought,
            amount1Desired: 0.005 ether,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp
        })) returns (uint256 tokenId, uint128 v3Liquidity, uint256 amount0, uint256 amount1) {
            cultV3Position = tokenId;
           
            // Refund any unused WETH
            uint256 unusedWeth = 0.005 ether - amount1;
            if (unusedWeth > 0) {
                
                IWETH(weth).withdraw(unusedWeth);
            }
            return true;
        } catch Error(string memory reason) {
            
            IWETH(weth).withdraw(0.005 ether);
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
        //liquidityPair = factory.createPair(address(this), weth);
        (,bytes memory d) = factory.call(abi.encodeWithSelector(0xc9c65396, address(this), weth));
        liquidityPair = abi.decode(d, (address));

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
            
        }

        return (amountToken, amountETH, liquidity);
    }

    // Operation types: 0 = sell EXEC, 1 = buy CULT, 2 = add liquidity
    function _selectOperation() internal view returns (uint256 operation, uint256 amount) {
        uint256 execBalance = balanceOf(address(this));
        uint256 ethBalance = address(this).balance;
        //uint256 cultBalance = IERC20(CULT).balanceOf(address(this));
        (,bytes memory d) = (CULT).staticcall(abi.encodeWithSelector(0x70a08231, address(this)));
        uint256 cultBalance = abi.decode(d, (uint256));

        // Priority 1: If we have EXEC and low ETH, sell EXEC
        if (execBalance >= MIN_SELL_THRESHOLD && ethBalance < 0.01 ether) {
            
            return (0, execBalance);
        }

        // Priority 2: If we have ETH but low CULT, buy CULT with ALL available ETH
        if (ethBalance >= 0.01 ether && cultBalance < MIN_CULT_THRESHOLD) {
            // Use ALL available ETH (minus gas buffer)
            uint256 ethToUse = ethBalance - 0.005 ether; // Leave 0.005 ETH for gas
            
            return (1, ethToUse);
        }

        // Priority 3: If we have both ETH and CULT, add ALL liquidity
        if (ethBalance >= 0.01 ether && cultBalance >= MIN_LP_THRESHOLD) {
            // Get optimal ratio for our ETH
            (uint256 optimalCult,) = _getOptimalCultRatio(ethBalance);
            // Use the maximum amount possible while maintaining ratio
            uint256 cultToUse = cultBalance > optimalCult ? optimalCult : cultBalance;
            
            return (2, cultToUse);
        }

       
        return (0, 0);
    }

    // Add this internal function to handle tax logic
    function _beforeTransfer(address from, address to, uint256 amount) internal view returns (uint256) {
        // Don't tax if liquidity pair isn't set yet (initial deployment)
        address liq = liquidityPair;
        if (liq == address(0)) return amount;
        
        // Don't tax if contract is involved in the transfer
        if (from == address(this) || to == address(this)) return amount;
        
        // Apply tax on liquidity pair interactions
        if (to == liq || from == liq) {
            // uint256 taxAmount = (amount * TAX_RATE) / 10000;
            // return amount - taxAmount;
            assembly {
                // amount - ((amount * TAX_RATE) / 10000)
                let tax := div(mul(amount, TAX_RATE), 10000)
                amount := sub(amount, tax)
            }
        }
        return amount;
    }

    function _processTaxes(address from, address to) internal {
        // Skip if pair isn't initialized yet (for initial liquidity)
        address liq = liquidityPair;
        uint256 blockSwap = blockSwaps[block.number];
        if (liq == address(0)) return;
        if (from == address(this) || to == address(this)) return;
        // Only process on sells (when transferring TO the pair)
        bool isSell = to == liq;
        if (isSell && !swapping && blockSwap < 3) {
            uint256 existingBalance = balanceOf(address(this));
            if (existingBalance >= MIN_SELL_THRESHOLD) {
                swapping = true;
                (uint256 operation, uint256 amount) = _selectOperation();
                if (operation == 0) {
                    _handleSellTax();
                } else if (operation == 1) {
                    //_handleBuyCult(amount);
                    _buyCultWithExactEth(amount);
                } else {
                    _handleAddCultLiquidity();
                }
                swapping = false;
                blockSwaps[block.number] = blockSwap + 1;
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
        //IERC20(weth).approve(address(router3), ethAmount);
        (bool s,) = (weth).call(abi.encodeWithSelector(0x095ea7b3, address(router3), ethAmount)); require(s);
        //incorrect assembly
        // assembly {
        //     // keccak256("approve(address,uint256)")[:4] = 0x095ea7b3
        //     mstore(0x0, 0x095ea7b300000000000000000000000000000000000000000000000000000000)
        //     mstore(0x04, shr(96, shl(96, 0xE592427A0AEce92De3Edee1F18E0157C05861564)))  // router3 address padded to 32 bytes
        //     mstore(0x24, ethAmount)
        //     let success := call(gas(), 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, 0, 0x0, 0x44, 0x0, 0x0) //weth address
        //     if iszero(success) { revert(0, 0) }
        // }
        
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
        //(uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(cultPool).slot0();
        (uint160 sqrtPriceX96,) = _staticcallSlot0Values(cultPool);
        //(,bytes memory d) = cultPool.staticcall(abi.encodeWithSelector(0x3850c7bd));
        //uint160 sqrtPriceX96 = abi.decode(d, (uint160));

        //uint256 priceX96 = uint256(sqrtPriceX96) * uint256(sqrtPriceX96);
        //price = (priceX96 * (10**18)) >> 192; // Convert to WAD
        // Calculate how much CULT we should have for this amount of ETH
        //optimalCult = (ethAmount * price) / 1e18;

        assembly {
            // Calculate price = (sqrtPriceX96 * sqrtPriceX96 * 1e18) >> 192
            let priceX96 := mul(sqrtPriceX96, sqrtPriceX96)
            price := shr(192, mul(priceX96, exp(10, 18)))
            
            // Calculate optimalCult = (ethAmount * price) / 1e18
            optimalCult := div(mul(ethAmount, price), exp(10, 18))
        }
    }

    // redundant
    // function _handleBuyCult(uint256 ethAmount) internal {
    //     // Buy CULT with the ETH amount passed in
    //     _buyCultWithExactEth(ethAmount);
    // }

    function _handleAddCultLiquidity() internal {
        //uint256 cultBalance = IERC20(CULT).balanceOf(address(this));
        //(,bytes memory d) = (CULT).staticcall(abi.encodeWithSelector(0x70a08231, address(this)));
        //uint256 cultBalance = abi.decode(d, (uint256));
        uint256 cultBalance;
        assembly {
            // keccak256("balanceOf(address)")[:4] = 0x70a08231
            mstore(0x0, 0x70a0823100000000000000000000000000000000000000000000000000000000)
            mstore(0x04, address())
            
            let success := staticcall(gas(), CULT, 0x0, 0x24, 0x0, 0x20)
            if iszero(success) { revert(0, 0) }
            cultBalance := mload(0x0)
        }
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
        //(uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(cultPool).slot0();
        (uint160 sqrtPriceX96,) = _staticcallSlot0Values(cultPool);
        //(,bytes memory d) = cultPool.staticcall(abi.encodeWithSelector(0x3850c7bd));
        //uint160 sqrtPriceX96 = abi.decode(d, (uint160));
        uint256 priceX96 = uint256(sqrtPriceX96) * uint256(sqrtPriceX96);
        uint256 price = (priceX96 * 1e18) >> 192;
        
        if (amount0 > 0 && amount1 > 0.01 ether) {
          
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
         
            return false;
        }

        // Wrap ETH
        IWETH(weth).deposit{value: ethAmount}();
        
        // Approve tokens
        //IERC20(CULT).approve(address(positionManager), cultAmount);
        (bool s,) = (CULT).call(abi.encodeWithSelector(0x095ea7b3, address(positionManager), cultAmount)); require(s);
        //IERC20(weth).approve(address(positionManager), ethAmount);
        (bool s2,) = (weth).call(abi.encodeWithSelector(0x095ea7b3, address(positionManager), ethAmount)); require(s2);

        try positionManager.increaseLiquidity(INonfungiblePositionManager.IncreaseLiquidityParams({
            tokenId: cultV3Position,
            amount0Desired: CULT < weth ? cultAmount : ethAmount,
            amount1Desired: CULT < weth ? ethAmount : cultAmount,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp
        })) returns (uint128 liquidity, uint256 amount0, uint256 amount1) {

            // Unwrap any unused WETH
            //uint256 unusedWeth = IERC20(weth).balanceOf(address(this));
            (,bytes memory d) = (weth).staticcall(abi.encodeWithSelector(0x70a08231, address(this)));
            uint256 unusedWeth = abi.decode(d, (uint256));
            if (unusedWeth > 0) {
                IWETH(weth).withdraw(unusedWeth);
            }
            return true;
        } catch Error(string memory reason) {
         
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

    // Helper function to get message details
    function getMessageDetails(uint256 messageId) external view returns (
        address sender,
        uint32 timestamp,
        uint64 amount,
        bool isBuy,
        string memory message
    ) {
        require(messageId < totalMessages, "Message does not exist");
        BondingMessage memory bondingMsg = bondingMessages[messageId];  // Changed variable name to avoid shadowing
        (timestamp, amount, isBuy) = unpackData(bondingMsg.packedData);
        return (bondingMsg.sender, timestamp, amount, isBuy, bondingMsg.message);
    }

    // Optimized batch retrieval
    function getMessagesBatch(uint256 start, uint256 end) external view returns (
        address[] memory senders,
        uint32[] memory timestamps,
        uint64[] memory amounts,
        bool[] memory isBuys,
        string[] memory messages
    ) {
        require(end >= start, "Invalid range");
        require(end < totalMessages, "End out of bounds");
        
        uint256 size = end - start + 1;
        senders = new address[](size);
        timestamps = new uint32[](size);
        amounts = new uint64[](size);
        isBuys = new bool[](size);
        messages = new string[](size);
        
        for (uint256 i = 0; i < size; i++) {
            BondingMessage memory bondingMsg = bondingMessages[start + i];  // Changed variable name to avoid shadowing
            senders[i] = bondingMsg.sender;
            (timestamps[i], amounts[i], isBuys[i]) = unpackData(bondingMsg.packedData);
            messages[i] = bondingMsg.message;
        }
    }

    /*
    This contract needs

    X1. sequential merkle tree by day, 12 days
    X2. Automatic liquidity deployment after 12 days of presale bonding curve
    X3. buy/sell tax to pool that are converted to liqudiity for $CULT
    X4. setSkipNFT default true 
    X5. balanceMint 
    X6. ability for the owner of a specified NFT to collect the fees from the liquidity position
    x7. in deploying liquidity, a fraction must go to the owner of that same NFT
    x8. message system
    */

}
