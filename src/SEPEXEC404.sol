// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { DN404 } from "dn404/src/DN404.sol";
import { DN404Mirror } from "dn404/src/DN404Mirror.sol";
import { FixedPointMathLib } from "solady/utils/FixedPointMathLib.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { LibString } from "solady/utils/LibString.sol";
import { MerkleProofLib } from "solady/utils/MerkleProofLib.sol";
import { IUniswapV3SwapCallback } from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";

interface IUniswapV2Router02 {
    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity);
}

interface IUniswapV3Pool {
    //function token0() external view returns (address);
    //function token1() external view returns (address);
    //function fee() external view returns (uint24);
    //function positions(uint256 tokenId) external view returns (uint128 liquidity, uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128, uint128 tokensOwed0, uint128 tokensOwed1);
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1);
}


//interface INonfungiblePositionManager {
    // function mint(MintParams calldata params) external payable returns (
    //     uint256 tokenId,
    //     uint128 liquidity,
    //     uint256 amount0,
    //     uint256 amount1
    // );

    //function increaseLiquidity(IncreaseLiquidityParams calldata params) external payable returns (uint128 liquidity, uint256 amount0, uint256 amount1);

    // struct MintParams {
    //     address token0;
    //     address token1;
    //     uint24 fee;
    //     int24 tickLower;
    //     int24 tickUpper;
    //     uint256 amount0Desired;
    //     uint256 amount1Desired;
    //     uint256 amount0Min;
    //     uint256 amount1Min;
    //     address recipient;
    //     uint256 deadline;
    // }

    // function positions(uint256 tokenId)
    //     external
    //     view
    //     returns (
    //         uint96 nonce,
    //         address operator,
    //         address token0,
    //         address token1,
    //         uint24 fee,
    //         int24 tickLower,
    //         int24 tickUpper,
    //         uint128 liquidity,
    //         uint256 feeGrowthInside0LastX128,
    //         uint256 feeGrowthInside1LastX128,
    //         uint128 tokensOwed0,
    //         uint128 tokensOwed1
    //     );

    // struct CollectParams {
    //     uint256 tokenId;
    //     address recipient;
    //     uint128 amount0Max;
    //     uint128 amount1Max;
    // }
    
    // function collect(CollectParams calldata params)
    //     external
    //     payable
    //     returns (uint256 amount0, uint256 amount1);
//}


contract SEPEXEC404 is DN404, IUniswapV3SwapCallback {
    //using FixedPointMathLib for uint256;

    // Make CULT address configurable
    address public immutable CULT;
    // Make operator NFT address configurable
    address public immutable OPERATOR_NFT;
    uint256 public constant TAX_RATE = 400; // 4% tax
    address public cultLiquidityPair;

    // Update to Sepolia addresses
    IUniswapV2Router02 public constant router = IUniswapV2Router02(0xeE567Fe1712Faf6149d80dA1E6934E354124CfE3);
    //ISwapRouter public immutable router3 = ISwapRouter(0x3bFA4769FB09eefC5a80d6E87c3B9C650f7Ae48E);//router02//0xE592427A0AEce92De3Edee1F18E0157C05861564);
    //INonfungiblePositionManager public immutable positionManager = INonfungiblePositionManager(0x1238536071E1c677A632429e3655c799b22cDA52);
    address public constant positionManager = 0x1238536071E1c677A632429e3655c799b22cDA52;
    address public immutable factory;
    address public constant factory3 = 0x0227628f3F023bb0B980b67D528571c95c6DaC1c;
    address public constant weth = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;

    address public liquidityPair;

    bytes32[] public tierRoots;
    uint256 public immutable LAUNCH_TIME;

    uint256 public totalBondingSupply;
    uint256 public reserve;

    uint256 public constant INITIAL_PRICE = 0.025 ether;   // Base price per 10M tokens
    uint256 public constant MAX_SUPPLY = 4_440_000_000 ether; // 4.44B tokens
    uint256 public constant maxSupply = 4440; // nft maxSupply for uri hider
    uint256 public constant LIQUIDITY_RESERVE = MAX_SUPPLY * 10 / 100; // 10% reserve for liquidity

        // Constants for operation thresholds
    uint256 public constant MIN_SELL_THRESHOLD = 12000 ether;    // 100 tokens minimum for sell
    uint256 public constant MIN_CULT_THRESHOLD = 8000 ether;    // 500 tokens minimum for CULT ops
    uint256 public constant MIN_LP_THRESHOLD = 4000 ether;     // 1000 tokens minimum for LP ops
    // Add these constants to your contract
    //uint160 public constant MIN_SQRT_RATIO = 4295128739;
    //uint160 public constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;
    
    address public cultPool;
    uint24 public constant POOL_FEE = 10000; // 0.3% fee tier
    
    int24 public constant TICK_SPACING = 60;
    uint256 public cultV3Position;

    event WhitelistInitialized(bytes32[] roots);
    uint256 constant startTokenId = 1;

    bool private swapping;
    mapping(uint256 => uint256) public blockSwaps;
    mapping(address => bool) public freeMint;
    uint256 public freeSupply = 1000 * 1000000 ether; //1000 free mints

    string public uri;
    string public unrevealedUri;
    bool public revealed = false;

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

    // Modify constructor to accept CULT and operator NFT addresses
    constructor(
        bytes32[] memory _tierRoots,
        address _cultToken,
        address _operatorNFT
    ) {
        require(_tierRoots.length == 12, "Bad roots length");
        require(_cultToken != address(0), "Bad CULT addr");
        require(_operatorNFT != address(0), "Bad operator NFT addr");
        
        CULT = _cultToken;
        OPERATOR_NFT = _operatorNFT;
        tierRoots = _tierRoots;
        LAUNCH_TIME = block.timestamp;

        // Store router address in memory before assembly block
        address routerAddr = address(router);
        address factoryAddr;
        assembly {
            // Get factory address using factory() selector: 0xc45a0155
            mstore(0x00, 0xc45a015500000000000000000000000000000000000000000000000000000000)
            let success := staticcall(
                gas(),
                routerAddr,     // use local variable instead of immutable
                0x00,           // input offset
                0x04,           // input size (just selector)
                0x00,           // output offset
                0x20            // output size (32 bytes)
            )
            if iszero(success) {
                revert(0, 0)
            }
            factoryAddr := mload(0x00)  // store in temporary variable
        }
        factory = factoryAddr;  // assign to immutable after assembly block
        //weth = router.WETH();

        // Set CULT V3 pool directly
        //cultPool = factory3.getPool(CULT, weth, POOL_FEE);
        (,bytes memory d) = factory3.staticcall(abi.encodeWithSelector(0x1698ee82, CULT, weth, POOL_FEE));
        cultPool = abi.decode(d, (address));
        require(cultPool != address(0), "CULT pool no exist");
        
        emit WhitelistInitialized(_tierRoots);
        address mirror = address(new DN404Mirror(msg.sender));
        _initializeDN404(MAX_SUPPLY, address(this), mirror);
    }

    function getCurrentTier() public view returns (uint256) {
        if (block.timestamp < LAUNCH_TIME) return 0;
        uint256 hoursSinceLaunch = (block.timestamp - LAUNCH_TIME) / 1 hours;
        return hoursSinceLaunch >= tierRoots.length ? tierRoots.length - 1 : hoursSinceLaunch;
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
            require(isWhitelisted(proof, msg.sender), "Non-white");
        }
        _;
    }

    function _unit() internal pure override returns (uint256) {
        //1,000,000 $EXEC per Executive
        return 1000000 * 10 ** 18;
    }

    function _tokenURI(uint256 tokenId) internal view override returns (string memory) {
        // return "https://example.com/token/1";
        if (!_exists(tokenId) || !revealed) {
            return unrevealedUri;
        }
        return bytes(uri).length != 0 ? string(abi.encodePacked(uri, LibString.concat(_toString(tokenId),".json"))) : "test";
    }

    // Update configure function to use OPERATOR_NFT
    function configure(string memory _uri, string memory _unrevealedUri, bool _revealed) public {
        require(_erc721OwnerOf(OPERATOR_NFT, 1) == msg.sender, "not oper");
        uri = _uri;
        unrevealedUri = _unrevealedUri;
        revealed = _revealed;
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
        uint256 balance = addressData.balance;
        uint256 currentOwnedLength = addressData.ownedLength;
        uint256 maxMintPossible = balance / _unit() - currentOwnedLength;
        require(amount <= maxMintPossible, "NFTs over balance");

        // Calculate amounts
        uint256 amountToMint = amount * _unit();
        // Keep enough tokens to support existing NFTs plus new ones we want to mint
        uint256 amountToHold = balance - (currentOwnedLength + amount) * _unit();
        
        // First transfer the portion we don't want to mint to the contract
        _transfer(msg.sender, address(this), amountToHold);
        
        // Set skipNFT false for minting
        bool originalSkipNFT = getSkipNFT(msg.sender);
        _setSkipNFT(msg.sender, false);
        
        // Self-transfer to trigger mint
        _transfer(msg.sender, msg.sender, amountToMint);
        
        // Reset skipNFT
        _setSkipNFT(msg.sender, originalSkipNFT);
        
        // Return held tokens
        _transfer(address(this), msg.sender, amountToHold);
        
        // Verify final state
        require(addressData.balance == balance, "Balance mismatch");
        require(addressData.ownedLength == currentOwnedLength + amount, "NFT count mismatch");
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
        require(execAmount <= totalBondingSupply, "Exceeds bonding supply");
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
        require(msg.value >= totalCost, "Low ETH value");

        // Only flip skipNFT if it's currently true and user wants to mint
        bool originalSkipNFT = mintNFT ? getSkipNFT(msg.sender) : false;
        if (originalSkipNFT) {
            _setSkipNFT(msg.sender, false);
        }

        if(freeSupply > 1000000 ether && !freeMint[msg.sender]) {
            totalBondingSupply += amount;
            amount += 1000000 ether;
            freeSupply -= 1000000 ether;
            freeMint[msg.sender] = true;
        } else {
            totalBondingSupply += amount;
        }

        _transfer(address(this), msg.sender, amount);
        reserve += totalCost;

        // Store message if provided
        if (bytes(message).length > 0) {
            uint64 scaledAmount = uint64(amount / 1e18);
            require(scaledAmount <= type(uint64).max, "Too size for msg storage");
            
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
        //a requirement that disables selling if the bonding curve is mostly full, say about at 85%+ 
        uint256 balance = balanceOf(msg.sender);
        require(balance >= amount, "Insufficient balance");
        if(freeMint[msg.sender] && (balance - amount < 1000000 ether)) {
            revert("Cannot sell your freebie back into bonding");
        }


        // Calculate refund and validate
        uint256 refund = calculateRefund(amount);
        require(refund >= minRefund && reserve >= refund, "Invalid refund");

        // Transfer tokens first
        _transfer(msg.sender, address(this), amount);
        totalBondingSupply -= amount;
        reserve -= refund;

        // Store message if provided
        if (bytes(message).length > 0) {
            require(amount / 1 ether <= type(uint64).max, "Too size for msg storage");
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
            //IERC721(0xB24BaB1732D34cAD0A7C7035C3539aEC553bF3a0).ownerOf(598), 
            _erc721OwnerOf(OPERATOR_NFT, 1), 
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
        int24 tickSpacing = _staticcallTickSpacing(cultPool);
        (uint160 sqrtPriceX96,int24 currentTick) = _staticcallSlot0Values(cultPool);
        
        // Calculate ticks ±16 spacing units from current tick
        int24 tickRange = tickSpacing * 16;

        // Buy CULT with half the ETH
        uint256 cultBought = _buyCultWithExactEth(0.005 ether);

        // Wrap the other half for the position
        //IWETH(weth).deposit{value: 0.005 ether}();
        _wethDeposit(0.005 ether);

        // Approve tokens for position manager
        _erc20Approve(CULT, address(positionManager), cultBought);
        _erc20Approve(weth, address(positionManager), 0.005 ether);
        
        // try positionManager.mint(INonfungiblePositionManager.MintParams({
        //     token0: CULT,
        //     token1: weth,
        //     fee: POOL_FEE,
        //     tickLower: ((currentTick - tickRange) / tickSpacing) * tickSpacing,
        //     tickUpper: ((currentTick + tickRange) / tickSpacing) * tickSpacing,
        //     amount0Desired: cultBought,
        //     amount1Desired: 0.005 ether,
        //     amount0Min: 0,
        //     amount1Min: 0,
        //     recipient: address(this),
        //     deadline: block.timestamp
        // })) returns (uint256 tokenId, uint128 v3Liquidity, uint256 amount0, uint256 amount1) {
        //     cultV3Position = tokenId;
           
        //     // Refund any unused WETH
        //     uint256 unusedWeth = 0.005 ether - amount1;
        //     if (unusedWeth > 0) {
                
        //         //IWETH(weth).withdraw(unusedWeth);
        //         _wethWithdraw(unusedWeth);
        //     }
        //     return true;
        // } catch Error(string memory reason) {
            
        //     //IWETH(weth).withdraw(0.005 ether);
        //     _wethWithdraw(0.005 ether);
        //     return false;
        // }
        // Calculate tick ranges
        int24 tickLower = ((currentTick - tickRange) / tickSpacing) * tickSpacing;
        int24 tickUpper = ((currentTick + tickRange) / tickSpacing) * tickSpacing;
        address _CULT = CULT;
        address _posMan = address(positionManager);
        bool isToken0 = CULT < weth;
        bool success;
        
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, 0x8831645600000000000000000000000000000000000000000000000000000000)
            
            // Pack parameters with correct token ordering
            switch isToken0 
            case 1 {
                mstore(add(ptr, 0x04), _CULT)
                mstore(add(ptr, 0x24), weth)
                mstore(add(ptr, 0xa4), cultBought)
                mstore(add(ptr, 0xc4), 5000000000000000)
            }
            default {
                mstore(add(ptr, 0x04), weth)
                mstore(add(ptr, 0x24), _CULT)
                mstore(add(ptr, 0xa4), 5000000000000000)
                mstore(add(ptr, 0xc4), cultBought)
            }
            
            mstore(add(ptr, 0x44), POOL_FEE)
            mstore(add(ptr, 0x64), tickLower)
            mstore(add(ptr, 0x84), tickUpper)
            mstore(add(ptr, 0xe4), 0)
            mstore(add(ptr, 0x104), 0)
            mstore(add(ptr, 0x124), address())
            mstore(add(ptr, 0x144), timestamp())

            success := call(
                gas(),
                _posMan,
                0,
                ptr,
                0x164,
                ptr,
                0x80
            )

            if success {
                sstore(cultV3Position.slot, mload(ptr))
                
                let amount1 := mload(add(ptr, 0x80))  // Fixed offset for amount1
                let unusedWeth := sub(5000000000000000, amount1)
                
                if gt(unusedWeth, 0) {
                    mstore(0x00, 0x2e1a7d4d00000000000000000000000000000000000000000000000000000000)
                    mstore(0x04, unusedWeth)
                    pop(call(gas(), weth, 0, 0x00, 0x24, 0x00, 0x00))
                }
            }
            if iszero(success) {
                mstore(0x00, 0x2e1a7d4d00000000000000000000000000000000000000000000000000000000)
                mstore(0x04, 5000000000000000)
                pop(call(gas(), weth, 0, 0x00, 0x24, 0x00, 0x00))
            }
        }
        
        return success;
    }

    // Keep external version for direct calls if needed
    function initializeCultPool() external payable {
        require(_initializeCultPoolLogic(), "Pool init failed");
    }

    function deployLiquidity() external returns (uint256 amountToken, uint256 amountETH, uint256 liquidity) {
        require(block.timestamp >= LAUNCH_TIME + 12 hours, "Too early for liq");
        require(liquidityPair == address(0), "Liq already deployed!");
        
        uint256 ethBalance = address(this).balance;
        require(ethBalance > 0.01 ether, "No ETH to deploy");

        uint256 remainingSupply = MAX_SUPPLY - (totalBondingSupply + (1000000000 ether - freeSupply));
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
    function _selectOperation(uint256 ethBalance, uint256 cultBalance, uint256 execBalance) internal view returns (uint8 operation, uint256 amount) {
        //uint256 execBalance = balanceOf(address(this));
        //uint256 ethBalance = address(this).balance;
        //uint256 cultBalance = _erc20BalanceOf(CULT,address(this));

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
    //event TaxOperation(string opType, uint256 gasUsed);
    function _processTaxes(address from, address to) internal {
        //uint256 gasStart = gasleft();
        // Skip if pair isn't initialized yet (for initial liquidity)
        address liq = liquidityPair;
        if (liq == address(0)) return;
        if (from == address(this) || to == address(this)) return;
        // Only process on sells (when transferring TO the pair)
        uint256 blockSwap = blockSwaps[block.number];
        bool isSell = to == liq;
        if (isSell && !swapping && blockSwap < 3) {
            uint256 execBalance = balanceOf(address(this));
            if (execBalance >= MIN_SELL_THRESHOLD) {
                swapping = true;
                uint256 ethBalance = address(this).balance;
                uint256 cultBalance = _erc20BalanceOf(CULT,address(this));
                (uint8 operation, uint256 amount) = _selectOperation(ethBalance,cultBalance,execBalance);
                if (operation == 0) {
                    _handleSellTax(execBalance);
                    //emit TaxOperation("sell", gasStart - gasleft());
                    
                } else if (operation == 1) {
                    _buyCultWithExactEth(amount);
                    //emit TaxOperation("buy", gasStart - gasleft());
                } else {
                    _handleAddCultLiquidity(ethBalance, cultBalance);
                    //emit TaxOperation("add", gasStart - gasleft());
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

    function _handleSellTax(uint256 tokenBalance) internal {
        if (tokenBalance < MIN_SELL_THRESHOLD) return;

        //interface version
        // address[] memory path = new address[](2);
        // path[0] = address(this);
        // path[1] = weth;
        // _approve(address(this), address(router), tokenBalance);
        // router.swapExactTokensForETHSupportingFeeOnTransferTokens(
        //     tokenBalance,
        //     0,
        //     path,
        //     address(this),
        //     block.timestamp
        // );

        //equivalent assembly 

        _approve(address(this), address(router), tokenBalance);
        assembly {
            let ptr := mload(0x40)
            //swapExactTokensForETHSupportingFeeOnTransferTokens selector
            mstore(ptr, 0x791ac94700000000000000000000000000000000000000000000000000000000)
            mstore(add(ptr, 0x04), tokenBalance)
            mstore(add(ptr, 0x24), 0)              // amountOutMin
            mstore(add(ptr, 0x44), 0xa0)          // path offset
            mstore(add(ptr, 0x64), address())     // recipient
            mstore(add(ptr, 0x84), timestamp())           // deadline at 132 bytes
            mstore(add(ptr, 0xa4), 2)            // array length at 164 bytes (0xa0 + 0x04)
            mstore(add(ptr, 0xc4), address())    // path[0] at 196 bytes (0xc0 + 0x04)
            mstore(add(ptr, 0xe4), weth)  // path[1] at 228 bytes (0xe0 + 0x04)
            let success := call(
                gas(),
                0xeE567Fe1712Faf6149d80dA1E6934E354124CfE3,//sepolia//0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D,//mainnet
                0,
                ptr,
                0x104,
                0,
                0
            )
            if iszero(success) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
        }
    }

    function _buyCultWithExactEth(uint256 ethAmount) internal returns (uint256 cultBought) {
        
        //IWETH(weth).deposit{value: ethAmount}();
        _wethDeposit(ethAmount);
        address pool = cultPool;
        _erc20Approve(weth, pool, ethAmount);
        
        // 3. Swap with 1% fee tier
        // bytes memory path;
        // if (CULT < weth) {
        //     // If CULT is token0
        //     path = abi.encodePacked(
        //         weth,
        //         uint24(POOL_FEE),
        //         CULT
        //     );
        // } else {
        //     // If WETH is token0
        //     path = abi.encodePacked(
        //         weth,
        //         uint24(POOL_FEE),
        //         CULT
        //     );
        // }

        // ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
        //     path: path,
        //     recipient: address(this),
        //     deadline: block.timestamp,
        //     amountIn: ethAmount,
        //     amountOutMinimum: 0
        // });

        // try ISwapRouter(router3).exactInput(params) returns (uint256 amountOut) {
        //     return amountOut;
        // } catch Error(string memory reason) {
        //     //IWETH(weth).withdraw(ethAmount);
        //     _wethWithdraw(ethAmount);
        //     revert(string.concat("Swap failed: ", reason));
        // }
        bool zeroForOne = weth < CULT; // true if WETH is token0
        bytes memory data = ""; // No callback needed
        
        // Execute swap directly with pool
        try IUniswapV3Pool(pool).swap(
            address(this),  // recipient
            zeroForOne,     // WETH -> CULT
            int256(ethAmount),
            //MIN MAX SQRT RATIO
            zeroForOne ? 4295128739 + 1 : 1461446703485210103287273052203988822378723970342 - 1, // Price limit
            data
        ) returns (int256 amount0, int256 amount1) {
            // Return absolute value of the output amount
            return uint256(-(zeroForOne ? amount1 : amount0));
        } catch {
            // Unwrap WETH on failure
            _wethWithdraw(ethAmount);
            return 0;
        }
    }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external override {
        // (address token0, address token1) = (
        //     IUniswapV3Pool(msg.sender).token0(),
        //     IUniswapV3Pool(msg.sender).token1()
        // );
        // Validation: ensure the call came from the expected pool
        require(msg.sender == address(cultPool), "Unauthed pool");

        // // Determine which token we need to send in
        // if (amount0Delta > 0) {
        //     // We're expected to send in token0
        //     //IERC20(token0).transfer(msg.sender, uint256(amount0Delta));
        //     _erc20Transfer(token0, msg.sender, uint256(amount0Delta));
        // } else if (amount1Delta > 0) {
        //     // We're expected to send in token1
        //     //IERC20(token1).transfer(msg.sender, uint256(amount1Delta));
        //     _erc20Transfer(token1, msg.sender, uint256(amount1Delta));
        // }
        assembly {
            // token0() selector: 0x0dfe1681
            mstore(0x00, 0x0dfe168100000000000000000000000000000000000000000000000000000000)
            let token0
            let token1
            
            // Get token0
            if iszero(staticcall(gas(), caller(), 0x00, 0x04, 0x00, 0x20)) {
                revert(0, 0)
            }
            token0 := mload(0x00)
            
            // token1() selector: 0xd21220a7
            mstore(0x00, 0xd21220a700000000000000000000000000000000000000000000000000000000)
            
            // Get token1
            if iszero(staticcall(gas(), caller(), 0x00, 0x04, 0x00, 0x20)) {
                revert(0, 0)
            }
            token1 := mload(0x00)

            // Handle transfers
            switch gt(amount0Delta, 0)
            case 1 {
                // transfer() selector: 0xa9059cbb
                mstore(0x00, 0xa9059cbb00000000000000000000000000000000000000000000000000000000)
                mstore(0x04, caller())
                mstore(0x24, amount0Delta)
                pop(call(gas(), token0, 0, 0x00, 0x44, 0x00, 0x00))
            }
            case 0 {
                if gt(amount1Delta, 0) {
                    mstore(0x00, 0xa9059cbb00000000000000000000000000000000000000000000000000000000)
                    mstore(0x04, caller())
                    mstore(0x24, amount1Delta)
                    pop(call(gas(), token1, 0, 0x00, 0x44, 0x00, 0x00))
                }
            }
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

    function _handleAddCultLiquidity(uint256 ethBalance, uint256 cultBalance) internal {

        //uint256 cultBalance = _erc20BalanceOf(CULT,address(this));

        //uint256 ethBalance = address(this).balance;
        
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
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return 0x150b7a02; // IERC721Receiver.onERC721Received.selector
    }
  
  
    function _increaseCultLiquidity(uint256 cultAmount, uint256 ethAmount) internal returns (bool) {
        if (cultV3Position == 0) {
            return false;
        }

        // Wrap ETH
        //IWETH(weth).deposit{value: ethAmount}();
        _wethDeposit(ethAmount);
        
        // Approve tokens
        //IERC20(CULT).approve(address(positionManager), cultAmount);
        //(bool s,) = (CULT).call(abi.encodeWithSelector(0x095ea7b3, address(positionManager), cultAmount)); require(s);
        _erc20Approve(CULT, address(positionManager), cultAmount);
        //IERC20(weth).approve(address(positionManager), ethAmount);
        //(bool s2,) = (weth).call(abi.encodeWithSelector(0x095ea7b3, address(positionManager), ethAmount)); require(s2);
        _erc20Approve(weth, address(positionManager), ethAmount);

        // try positionManager.increaseLiquidity(INonfungiblePositionManager.IncreaseLiquidityParams({
        //     tokenId: cultV3Position,
        //     amount0Desired: CULT < weth ? cultAmount : ethAmount,
        //     amount1Desired: CULT < weth ? ethAmount : cultAmount,
        //     amount0Min: 0,
        //     amount1Min: 0,
        //     deadline: block.timestamp
        // })) {
        //     // Unwrap any unused WETH
        //     //uint256 unusedWeth = IERC20(weth).balanceOf(address(this));
        //     //(,bytes memory d) = (weth).staticcall(abi.encodeWithSelector(0x70a08231, address(this)));
        //     //uint256 unusedWeth = abi.decode(d, (uint256));
        //     uint256 unusedWeth = _erc20BalanceOf(weth, address(this));
        //     if (unusedWeth > 0) {
        //         //IWETH(weth).withdraw(unusedWeth);
        //         _wethWithdraw(unusedWeth);
        //     }
        //     return true;
        // } catch {
        //     // Unwrap WETH on failure
        //     //IWETH(weth).withdraw(ethAmount);
        //     _wethWithdraw(ethAmount);
        //     return false;
        // }
        // Store immutable values in memory before assembly block
        address posAddr = address(positionManager);
        bool isToken0 = CULT < weth;
        
        assembly {
            // Prepare calldata for increaseLiquidity
            let ptr := mload(0x40)
            
            // increaseLiquidity selector: 0x219f5d17
            mstore(ptr, 0x219f5d1700000000000000000000000000000000000000000000000000000000)
            
            // tokenId
            mstore(add(ptr, 0x04), sload(cultV3Position.slot))
            
            // amount0Desired and amount1Desired based on token ordering
            switch isToken0
            case 1 {
                mstore(add(ptr, 0x24), cultAmount)  // amount0Desired
                mstore(add(ptr, 0x44), ethAmount)   // amount1Desired
            }
            default {
                mstore(add(ptr, 0x24), ethAmount)   // amount0Desired
                mstore(add(ptr, 0x44), cultAmount)  // amount1Desired
            }
            
            // amount0Min and amount1Min (both 0)
            mstore(add(ptr, 0x64), 0)
            mstore(add(ptr, 0x84), 0)
            
            // deadline (block.timestamp)
            mstore(add(ptr, 0xa4), timestamp())

            // Make the call
            let success := call(
                gas(),
                posAddr,  // use local variable instead of immutable
                0,      // value
                ptr,    // input
                0xc4,   // input size (4 + 5 * 32)
                0,      // output offset
                0       // output size
            )

            // Handle unused WETH on success
            if success {
                // Check remaining WETH balance
                let wethPtr := mload(0x40)
                mstore(wethPtr, 0x70a0823100000000000000000000000000000000000000000000000000000000)
                mstore(add(wethPtr, 0x04), address())
                
                pop(staticcall(
                    gas(),
                    weth,
                    wethPtr,
                    0x24,
                    0,
                    0x20
                ))
                
                let unusedWeth := mload(0)
                if gt(unusedWeth, 0) {
                    // Withdraw unused WETH
                    mstore(wethPtr, 0x2e1a7d4d00000000000000000000000000000000000000000000000000000000)
                    mstore(add(wethPtr, 0x04), unusedWeth)
                    pop(call(gas(), weth, 0, wethPtr, 0x24, 0, 0))
                }
                
                return(0, 0)
            }
            
            // On failure, withdraw all WETH
            let wethPtr := mload(0x40)
            mstore(wethPtr, 0x2e1a7d4d00000000000000000000000000000000000000000000000000000000)
            mstore(add(wethPtr, 0x04), ethAmount)
            pop(call(gas(), weth, 0, wethPtr, 0x24, 0, 0))
            
            return(0, 0)
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
        //require(IERC721(0xB24BaB1732D34cAD0A7C7035C3539aEC553bF3a0).ownerOf(598) == msg.sender, "Not operator token owner");
        require(_erc721OwnerOf(OPERATOR_NFT, 1) == msg.sender, "Not oper");
        
        // Require at least one amount to be non-zero (matching V3 requirement)
        require(amount0Max > 0 || amount1Max > 0, "Amount0Max and amount1Max both 0");
        
        // INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager
        //     .CollectParams({
        //         tokenId: cultV3Position,
        //         recipient: msg.sender,
        //         amount0Max: amount0Max,
        //         amount1Max: amount1Max
        //     });
            
        // // Assuming V3_POSITION_MANAGER is defined somewhere in the contract
        // (amount0, amount1) = INonfungiblePositionManager(positionManager).collect{value: msg.value}(params);
        uint256 _cultPosition = cultV3Position;
        assembly {
            // collect function selector: 0xfc6f7865
            let ptr := mload(0x40)
            mstore(ptr, 0xfc6f786500000000000000000000000000000000000000000000000000000000)
            
            // Pack parameters
            mstore(add(ptr, 0x04), _cultPosition)  // tokenId
            mstore(add(ptr, 0x24), caller())        // recipient
            mstore(add(ptr, 0x44), amount0Max)      // amount0Max
            mstore(add(ptr, 0x64), amount1Max)      // amount1Max

            // Make the call
            let success := call(
                gas(),
                positionManager,  // target
                callvalue(),      // forward any ETH value
                ptr,             // input
                0x84,           // input size (4 + 4 * 32)
                ptr,            // output
                0x40            // output size (2 * 32 for two uint256 returns)
            )

            if iszero(success) {
                returndatacopy(0, 0, returndatasize())
                revert(0, 0)
            }

            // Load return values
            amount0 := mload(ptr)
            amount1 := mload(add(ptr, 0x20))
        }
        
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
        require(messageId < totalMessages, "Msg doesnt exist");
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

    function _erc20Approve(address token, address spender, uint256 amount) internal {
        assembly {
            let ptr := mload(0x40) // get free memory pointer
            
            // keccak256("approve(address,uint256)") = 0x095ea7b3...
            mstore(ptr, 0x095ea7b300000000000000000000000000000000000000000000000000000000)
            mstore(add(ptr, 0x04), and(spender, 0xffffffffffffffffffffffffffffffffffffffff))
            mstore(add(ptr, 0x24), amount)
            
            let success := call(
                gas(),    // gas
                token,    // to
                0,       // value
                ptr,     // input offset
                0x44,    // input size (4 + 32 + 32)
                0,       // output offset
                0        // output size
            )
            // If call fails, bubble up the revert
            if iszero(success) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
        }
    }

    function _erc20BalanceOf(address token, address account) internal view returns (uint256 result) {
        assembly {
            // Store the function selector and argument in memory
            mstore(0x00, 0x70a0823100000000000000000000000000000000000000000000000000000000)
            mstore(0x04, and(account, 0xffffffffffffffffffffffffffffffffffffffff))
            
            // Perform the staticcall
            let success := staticcall(
                gas(),    // gas
                token,    // to
                0x00,    // input offset
                0x24,    // input size (4 + 32)
                0x00,    // output offset
                0x20     // output size (32 bytes)
            )
            
            // Check if the call was successful
            if iszero(success) {
                revert(0, 0)
            }

            // Return value is already in memory at 0x00, load it to the named return variable
            result := mload(0x00)
        }
    }

    function _erc20Transfer(address token, address to, uint256 amount) internal {
        assembly {
            let ptr := mload(0x40)

            // Function selector for transfer(address,uint256)
            mstore(ptr, 0xa9059cbb00000000000000000000000000000000000000000000000000000000)
            mstore(add(ptr, 0x04), and(to, 0xffffffffffffffffffffffffffffffffffffffff))
            mstore(add(ptr, 0x24), amount)

            let success := call(
                gas(),
                token,
                0,
                ptr,
                0x44,  // input length = 4 + 32 + 32
                ptr,   // Store output in the same location
                0x20   // Expect 32 bytes (bool) return
            )

            // Check both call success and returned boolean
            if iszero(success) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
            
            // Load the returned boolean
            let returnValue := mload(ptr)
            if iszero(returnValue) {
                revert(0, 0)
            }
        }
    }


    function _erc721OwnerOf(address collection, uint256 tokenId) internal view returns (address owner) {
        assembly {
            // Store the function selector and argument in memory
            // keccak256("ownerOf(uint256)") = 0x6352211e
            mstore(0x00, 0x6352211e00000000000000000000000000000000000000000000000000000000)
            mstore(0x04, tokenId)
            
            // Perform the staticcall
            let success := staticcall(
                gas(),          // gas
                collection,     // to
                0x00,          // input offset
                0x24,          // input size (4 + 32)
                0x00,          // output offset
                0x20           // output size (32 bytes)
            )
            
            // Check if the call was successful
            if iszero(success) {
                revert(0, 0)
            }

            // Load the owner address from memory
            // Note: We mask the upper bits to ensure it's a valid address
            owner := and(mload(0x00), 0xffffffffffffffffffffffffffffffffffffffff)
        }
    }

    function _wethDeposit(uint256 amount) internal {
        assembly {
            // deposit() selector = 0xd0e30db0
            mstore(0x00, 0xd0e30db000000000000000000000000000000000000000000000000000000000)
            
            let success := call(
                gas(),    // gas
                weth,    // to
                amount,  // value (ETH to wrap)
                0x00,    // input offset
                0x04,    // input size (just selector)
                0x00,    // output offset
                0x00     // output size
            )
            
            if iszero(success) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
        }
    }

    function _wethWithdraw(uint256 amount) internal {
        assembly {
            // withdraw(uint256) selector = 0x2e1a7d4d
            mstore(0x00, 0x2e1a7d4d00000000000000000000000000000000000000000000000000000000)
            mstore(0x04, amount)
            
            let success := call(
                gas(),    // gas
                weth,    // to
                0,       // value
                0x00,    // input offset
                0x24,    // input size (4 + 32)
                0x00,    // output offset
                0x00     // output size
            )
            
            if iszero(success) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
        }
    }

    //event Debug(string label, bytes data);

    function getOwnerTokens(address owner) public view returns (uint256[] memory) {
        uint256 ownerBalanceLength = _balanceOfNFT(owner);
        return _ownedIds(owner, 0, ownerBalanceLength);
    }

    function tokenURI(uint256 tokenId) public view returns (string memory) {
        return _tokenURI(tokenId);
    }

    /**
     * @dev Converts a uint256 to its ASCII string decimal representation.
     */
    function _toString(uint256 value) internal view virtual returns (string memory str) {
        assembly {
            // The maximum value of a uint256 contains 78 digits (1 byte per digit), but
            // we allocate 0xa0 bytes to keep the free memory pointer 32-byte word aligned.
            // We will need 1 word for the trailing zeros padding, 1 word for the length,
            // and 3 words for a maximum of 78 digits. Total: 5 * 0x20 = 0xa0.
            let m := add(mload(0x40), 0xa0)
            // Update the free memory pointer to allocate.
            mstore(0x40, m)
            // Assign the `str` to the end.
            str := sub(m, 0x20)
            // Zeroize the slot after the string.
            mstore(str, 0)

            // Cache the end of the memory to calculate the length later.
            let end := str

            // We write the string from rightmost digit to leftmost digit.
            // The following is essentially a do-while loop that also handles the zero case.
            // prettier-ignore
            for { let temp := value } 1 {} {
                str := sub(str, 1)
                // Write the character to the pointer.
                // The ASCII index of the '0' character is 48.
                mstore8(str, add(48, mod(temp, 10)))
                // Keep dividing `temp` until zero.
                temp := div(temp, 10)
                // prettier-ignore
                if iszero(temp) { break }
            }

            let length := sub(end, str)
            // Move the pointer 32 bytes leftwards to make room for the length.
            str := sub(str, 0x20)
            // Store the length.
            mstore(str, length)
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
    x9. fit bytecode limit
    10. gas optimized
    x11. a way to get user nft ids
    */

}
