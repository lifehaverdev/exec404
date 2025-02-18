// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { DN404MS2 } from "dn404/src/DN404MS2.sol";
import { DN404Mirror } from "dn404/src/DN404Mirror.sol";
import { Ownable } from "solady/auth/Ownable.sol";
import { LibString } from "solady/utils/LibString.sol";
import { FixedPointMathLib } from "solady/utils/FixedPointMathLib.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

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

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

//TEST
import "forge-std/Test.sol";

contract TEST404 is DN404MS2, Ownable, Test {

    //
    // CONSTANTS
    //

    address internal constant SWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    uint256 internal constant WHITELISTED_BITPOS = 1;
    uint256 internal constant BLACKLISTED_BITPOS = 87;
    uint256 internal immutable tax;

    //
    // ERRORS
    //

    error Locked();

    error MaxBalanceLimitReached();

    error NotLive();

    error TradingLocked();

    error MaxBalanceLocked();

    error Blacklisted();

    //
    // STORAGE
    //

    string private _name;
    string private _symbol;
    string private _baseURI;
    string private _dataURI;
    string private _preURI;
    string private _desc;
    string private _website = "https://genai.build/";

    bool public maxBalanceLocked;
    bool public whitelistLocked;
    bool public tradingLocked;
    bool public revealed;
    bool public live;
    bool public buyTax = true;
    bool public restricted;// = true;
    uint8 public maxBalanceLimit;
    address public pool;

    //AB TESTING
    bool public test;
    mapping (address => bool) blaklist;
    
    //
    // CONSTRUCTOR
    //

constructor(
        string memory name_,
        string memory symbol_,
        uint96 initialTokenSupply,
        address initialSupplyOwner,
        uint16 tax_ // out of 1000; 5 = .5%
    ) {
        _initializeOwner(msg.sender);
        _setWhitelisted(msg.sender,true);
        _setWhitelisted(address(this),true);

        _name = name_;
        _symbol = symbol_;
        maxBalanceLimit = 10;
        tax = tax_;

        address mirror = address(new DN404Mirror(msg.sender));
        _initializeDN404(initialTokenSupply, initialSupplyOwner, mirror);
    }

    //
    // TEST
    //

    function setTest(bool status) public {
        test = status;
    }


    //
    // PUBLIC
    //

    // function balanceMint(uint256 amount) public {
    //     DN404Storage storage $ = _getDN404Storage();

    //     AddressData storage toAddressData = _addressData(msg.sender);

    //     uint256 toOwnedLength = toAddressData.ownedLength;
    //     console2.log('address balance in balanceMint',toAddressData.balance);
    //     console2.log('to owned length',toOwnedLength);
    //     _PackedLogs memory packedLogs = _packedLogsMalloc(amount);
        
    //     if (amount > (toAddressData.balance / _WAD) - toOwnedLength) { revert InsufficientBalance();}
    //     else {
    //             Uint32Map storage toOwned = $.owned[msg.sender];
    //             uint256 toIndex = toOwnedLength;
    //             uint256 toEnd = toIndex + amount;
    //             uint32 toAlias = _registerAndResolveAlias(toAddressData, msg.sender);
    //             uint256 maxNFTId = $.totalSupply / _WAD;
    //             uint256 id = $.nextTokenId;
    //             $.totalNFTSupply += uint32(amount);
    //             toAddressData.ownedLength = uint32(toEnd);
    //             // Mint loop.
    //             do {
    //                 while (_get($.oo, _ownershipIndex(id)) != 0) {
    //                     if (++id > maxNFTId) id = 1;
    //                 }
    //                 _set(toOwned, toIndex, uint32(id));
    //                 _setOwnerAliasAndOwnedIndex($.oo, id, toAlias, uint32(toIndex++));
    //                 _packedLogsAppend(packedLogs, msg.sender, id, 0);
    //                 if (++id > maxNFTId) id = 1;
    //             } while (toIndex != toEnd);
    //             $.nextTokenId = uint32(id);
    //     }

    //     if (packedLogs.logs.length != 0) {
    //         _packedLogsSend(packedLogs, $.mirrorERC721);
    //     }
    // }

    //
    // TRANSFERS
    //

    function _applyMaxBalanceLimit(address from, uint256 toBalance, uint88 toAux) internal view {
        unchecked {
            uint256 limit = maxBalanceLimit;
            if (limit == 0) return;
            if (toBalance <= _WAD * limit) return;
            if (isWhitelisted_(toAux)) return;
            if (from == owner()) return;
            revert MaxBalanceLimitReached();
        }
    }
    function _applyBasicMaxBalanceLimit(address from, address to) internal view {
        unchecked {
            uint256 limit = maxBalanceLimit;
            if (limit == 0) return;
            if (balanceOf(to) <= _WAD * limit) return;
            if (isWhitelisted_(_getAux(to))) return;
            if (from == owner()) return;
            revert MaxBalanceLimitReached();
        }
    }
    //Changes to DN404
    //trading live revert
    //blacklist revert
    //maxWalletLimit
    //pool buy taxes sent to contract
    function _transfer(address from, address to, uint256 amount) internal override {
    if(!test){
        if (to == address(0)) revert TransferToZeroAddress();
        if(!live && from != owner()) revert NotLive();

        DN404Storage storage $ = _getDN404Storage();

        AddressData storage fromAddressData = _addressData(from);
        AddressData storage toAddressData = _addressData(to);

        _TransferTemps memory t;
        t.fromOwnedLength = fromAddressData.ownedLength;
        t.toOwnedLength = toAddressData.ownedLength;
        t.fromBalance = fromAddressData.balance;

        bool taxedBuy = (buyTax && from == pool && to != address(this));

        if (amount > t.fromBalance) revert InsufficientBalance();

        unchecked {
            if(restricted && (isBlacklisted_(toAddressData.aux) || isBlacklisted_(fromAddressData.aux))){ revert Blacklisted();}
            
            t.fromBalance -= amount;
            fromAddressData.balance = uint96(t.fromBalance);
            
            if(taxedBuy){
                $.addressData[address(this)].balance = uint96(_addressData(address(this)).balance + FixedPointMathLib.fullMulDiv(amount, (tax), 1000));
                amount = FixedPointMathLib.fullMulDiv(amount, (1000 - tax), 1000);
                toAddressData.balance = uint96(t.toBalance = toAddressData.balance + amount);
            } else {
                toAddressData.balance = uint96(t.toBalance = toAddressData.balance + amount);
            }
            
            t.nftAmountToBurn = _zeroFloorSub(t.fromOwnedLength, t.fromBalance / _WAD);
            //console.log('amount to burn ',t.nftAmountToBurn);
            if (toAddressData.flags & _ADDRESS_DATA_GET_NFT_FLAG != 0) {
                if (from == to) t.toOwnedLength = t.fromOwnedLength - t.nftAmountToBurn;
                t.nftAmountToMint = _zeroFloorSub(t.toBalance / _WAD, t.toOwnedLength);
                //if(from == to) t.toOwnedLength  += t.nftAmountToMint;
            }
            //console2.log('fromOwnedLength after getnft condit', t.fromOwnedLength);
            //console2.log('toOwnedLength after getnft condit',t.toOwnedLength);
            _PackedLogs memory packedLogs = _packedLogsMalloc(t.nftAmountToBurn + t.nftAmountToMint);

            if (t.nftAmountToBurn != 0) {
                Uint32Map storage fromOwned = $.owned[from];
                uint256 fromIndex = t.fromOwnedLength;
                uint256 fromEnd = fromIndex - t.nftAmountToBurn;
                $.totalNFTSupply -= uint32(t.nftAmountToBurn);
                fromAddressData.ownedLength = uint32(fromEnd);
                // Burn loop.
                do {
                    uint256 id = _get(fromOwned, --fromIndex);
                    _setOwnerAliasAndOwnedIndex($.oo, id, 0, 0);
                    delete $.tokenApprovals[id];
                    _packedLogsAppend(packedLogs, from, id, 1);
                } while (fromIndex != fromEnd);
            }

            if (t.nftAmountToMint != 0) {
                Uint32Map storage toOwned = $.owned[to];
                uint256 toIndex = t.toOwnedLength;
                uint256 toEnd = toIndex + t.nftAmountToMint;
                uint32 toAlias = _registerAndResolveAlias(toAddressData, to);
                uint256 maxNFTId = $.totalSupply / _WAD;
                uint256 id = $.nextTokenId;
                $.totalNFTSupply += uint32(t.nftAmountToMint);
                toAddressData.ownedLength = uint32(toEnd);
                // Mint loop.
                do {
                    while (_get($.oo, _ownershipIndex(id)) != 0) {
                        if (++id > maxNFTId) id = 1;
                    }
                    _set(toOwned, toIndex, uint32(id));
                    _setOwnerAliasAndOwnedIndex($.oo, id, toAlias, uint32(toIndex++));
                    _packedLogsAppend(packedLogs, to, id, 0);
                    if (++id > maxNFTId) id = 1;
                } while (toIndex != toEnd);
                $.nextTokenId = uint32(id);
            }

            if (packedLogs.logs.length != 0) {
                _packedLogsSend(packedLogs, $.mirrorERC721);
            }
        }
        _applyMaxBalanceLimit(from, toAddressData.balance, toAddressData.aux);
        if(!taxedBuy){
            emit Transfer(from, to, amount);
        }else {
            emit Transfer(from, address(this), FixedPointMathLib.fullMulDiv(amount, (tax), 1000));
            emit Transfer(from, to, amount);
        }
    } else {
        // address deploy = owner();
        // if(from != deploy && !live) revert NotLive();
        // if(restricted){
        //     if(blaklist[to] || blaklist[from]){revert Blacklisted();}
        // }
        // if(from == pool && to != address(this) && buyTax){
        //     amount = _applyTaxPeriod(from, amount,deploy);
        // }
        // DN404._transfer(from, to, amount);
        // _applyBasicMaxBalanceLimit(from, to);
        if (to == address(0)) revert TransferToZeroAddress();
        if(!live && from != owner()) revert NotLive();

        DN404Storage storage $ = _getDN404Storage();

        AddressData storage fromAddressData = _addressData(from);
        AddressData storage toAddressData = _addressData(to);

        _TransferTemps memory t;
        t.fromOwnedLength = fromAddressData.ownedLength;
        t.toOwnedLength = toAddressData.ownedLength;
        t.fromBalance = fromAddressData.balance;

        bool taxedBuy = (buyTax && from == pool && to != address(this));

        if (amount > t.fromBalance) revert InsufficientBalance();
        if(restricted && (isBlacklisted_(toAddressData.aux) || isBlacklisted_(fromAddressData.aux))){ revert Blacklisted();}

        unchecked {
            t.fromBalance -= amount;
            fromAddressData.balance = uint96(t.fromBalance);
            
            if(taxedBuy){
                $.addressData[address(this)].balance = uint96(_addressData(address(this)).balance + FixedPointMathLib.fullMulDiv(amount, (tax), 1000));
                toAddressData.balance = uint96(t.toBalance = toAddressData.balance + FixedPointMathLib.fullMulDiv(amount, (1000 - tax), 1000));
            } else {
                toAddressData.balance = uint96(t.toBalance = toAddressData.balance + amount);
            }
            
            t.nftAmountToBurn = _zeroFloorSub(t.fromOwnedLength, t.fromBalance / _WAD);
            //console.log('amount to burn ',t.nftAmountToBurn);
            if (toAddressData.flags & _ADDRESS_DATA_GET_NFT_FLAG != 0) {
                if (from == to) t.toOwnedLength = t.fromOwnedLength - t.nftAmountToBurn;
                t.nftAmountToMint = _zeroFloorSub(t.toBalance / _WAD, t.toOwnedLength);
                //if(from == to) t.toOwnedLength  += t.nftAmountToMint;
            }
            //console2.log('fromOwnedLength after getnft condit', t.fromOwnedLength);
            //console2.log('toOwnedLength after getnft condit',t.toOwnedLength);
            _PackedLogs memory packedLogs = _packedLogsMalloc(t.nftAmountToBurn + t.nftAmountToMint);

            if (t.nftAmountToBurn != 0) {
                Uint32Map storage fromOwned = $.owned[from];
                uint256 fromIndex = t.fromOwnedLength;
                uint256 fromEnd = fromIndex - t.nftAmountToBurn;
                $.totalNFTSupply -= uint32(t.nftAmountToBurn);
                fromAddressData.ownedLength = uint32(fromEnd);
                // Burn loop.
                do {
                    uint256 id = _get(fromOwned, --fromIndex);
                    _setOwnerAliasAndOwnedIndex($.oo, id, 0, 0);
                    delete $.tokenApprovals[id];
                    _packedLogsAppend(packedLogs, from, id, 1);
                } while (fromIndex != fromEnd);
            }

            if (t.nftAmountToMint != 0) {
                Uint32Map storage toOwned = $.owned[to];
                uint256 toIndex = t.toOwnedLength;
                uint256 toEnd = toIndex + t.nftAmountToMint;
                uint32 toAlias = _registerAndResolveAlias(toAddressData, to);
                uint256 maxNFTId = $.totalSupply / _WAD;
                uint256 id = $.nextTokenId;
                $.totalNFTSupply += uint32(t.nftAmountToMint);
                toAddressData.ownedLength = uint32(toEnd);
                // Mint loop.
                do {
                    while (_get($.oo, _ownershipIndex(id)) != 0) {
                        if (++id > maxNFTId) id = 1;
                    }
                    _set(toOwned, toIndex, uint32(id));
                    _setOwnerAliasAndOwnedIndex($.oo, id, toAlias, uint32(toIndex++));
                    _packedLogsAppend(packedLogs, to, id, 0);
                    if (++id > maxNFTId) id = 1;
                } while (toIndex != toEnd);
                $.nextTokenId = uint32(id);
            }

            if (packedLogs.logs.length != 0) {
                _packedLogsSend(packedLogs, $.mirrorERC721);
            }
        }
        _applyMaxBalanceLimit(from, toAddressData.balance, toAddressData.aux);
        if(!taxedBuy){
            emit Transfer(from, to, amount);
        }else {
            emit Transfer(from, address(this), FixedPointMathLib.fullMulDiv(amount, (tax), 1000));
            emit Transfer(from, to, amount);
        }
    }
    }

    // function _applyTaxPeriod(address from, uint256 amount, address deploy_) internal returns (uint256 amountless) {
    //     unchecked {
    //         address _pool = pool;
    //         if (from != _pool) return amount;
    //         DN404._transfer(from,deploy_,(amount * tax / 1000));  
    //         return amount * (1000 - tax) / 1000;
    //     }
    // }

    function _transferFromNFT(address from, address to, uint256 id, address msgSender)
        internal
        override
    {
        AddressData memory toAddressData = _addressData(to);
        DN404MS2._transferFromNFT(from, to, id, msgSender);
        _applyMaxBalanceLimit(from, toAddressData.balance, toAddressData.aux);
    }

    //
    // META
    //

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (bytes(_baseURI).length > 0) {
            return string.concat(_baseURI, LibString.toString(tokenId));
        } else {
            return _dataURI;
        }
    }

    //
    // VIEW
    //

    function isWhitelisted(address target) public view returns (bool) {
        return isWhitelisted_(_getAux(target));
    }

    function isBlacklisted(address target) public view returns (bool) {
        return isWhitelisted_(_getAux(target));
    }

    //
    // OPERATIONS
    //

    function setWhitelist(address target, bool status) public onlyOwner {
        if (whitelistLocked) revert Locked();
        _setWhitelisted(target, status);
    }

    function setBlacklist(address[] calldata targets, bool status) public onlyOwner {
        for(uint160 i; i < targets.length;) {
            _setBlacklisted(targets[i],status);
            unchecked {
                ++i;
            }
        }
    }

    function setRestricted(bool status) public onlyOwner {
        restricted = status;
    }

    function setPool(address _pool, bool status) public onlyOwner {
        pool = _pool;
        _setWhitelisted(_pool, status);
    }

    function enableTrading( bool status) public onlyOwner {
        if(tradingLocked) revert TradingLocked();
        restricted = true;
        live = status;
    }

    function reveal(bool status) public onlyOwner {
        revealed = status;
    }

    function setWalletHoldingMax(uint8 limit) public onlyOwner {
        if(maxBalanceLocked) revert MaxBalanceLocked();
        maxBalanceLimit = limit;
    }

    function setBaseURI(string calldata baseURI_) public onlyOwner {
        _baseURI = baseURI_;
    }

    function setDataURI(string calldata dataURI_) public onlyOwner {
        _dataURI = dataURI_;
    }

    function setPreURI(string calldata preURI_) public onlyOwner {
        _preURI = preURI_;
    }

    function setDesc(string calldata desc_) public onlyOwner {
        _desc = desc_;
    }

    function setWebsite(string calldata website_) public onlyOwner {
        _website = website_;
    }

    function collectTaxes() public onlyOwner {
        
        DN404Storage storage $ = _getDN404Storage();

        uint256 balance = $.addressData[address(this)].balance;

        $.allowance[address(this)][SWAP_ROUTER] = balance;

        emit Approval(address(this), SWAP_ROUTER, balance);

        taxSwap(balance);

    }

    function taxSwitch(bool status) public onlyOwner {
        buyTax = status;
    }

    function lockContract() public onlyOwner {
        tradingLocked = true;
        maxBalanceLocked = true;
        whitelistLocked = true;
    }

    function withdraw() public onlyOwner {
        SafeTransferLib.safeTransferAllETH(msg.sender);
    }

    function withdrawTaxes(uint256 amount) public onlyOwner {
        if(amount > balanceOf(address(this))){revert InsufficientBalance();}
        _transfer(address(this),owner(),amount);
    }

    //
    // INTERNAL
    //

    function taxSwap(uint256 contractBalance) internal {
        if (contractBalance == 0) {
            return;
        }
        //only allowed to 1% sell MAX
        if (contractBalance > totalSupply() / 100) {
            contractBalance = totalSupply() / 100;
        }
        _swapTokensForEth(contractBalance);
    }

    function _swapTokensForEth(uint256 tokenAmount) internal {

        uint160 dline = uint160(block.timestamp + 10 minutes);
        // ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
        //     .ExactInputSingleParams({
        //         tokenIn: address(this),
        //         tokenOut: WETH,
        //         fee: 10000,
        //         recipient: owner(),
        //         deadline: dline,
        //         amountIn: tokenAmount,
        //         amountOutMinimum: 0,
        //         sqrtPriceLimitX96: 0
        //     });
        //ISwapRouter(SWAP_ROUTER).exactInputSingle(params);
    }

    function _setWhitelisted(address target, bool status) internal {
        _setAux(target, setWhitelisted_(_getAux(target),status));
    }

    function _setBlacklisted(address target, bool status) internal {
        _setAux(target, setBlacklisted_(_getAux(target),status));
    }

    function setWhitelisted_(uint88 packed, bool status) internal pure returns (uint88) {
        if (isWhitelisted_(packed) != status) {
            packed ^= uint88(1 << WHITELISTED_BITPOS);
        }
        return packed;
    }

    function setBlacklisted_(uint88 packed, bool status) internal pure returns (uint88) {
        if (isBlacklisted_(packed) != status) {
            packed ^= uint88(1 << BLACKLISTED_BITPOS);
        }
        return packed;
    }

     function isWhitelisted_(uint88 packed) internal pure returns (bool) {
        return packed >> WHITELISTED_BITPOS != 0;
    }

    function isBlacklisted_(uint88 packed) internal pure returns (bool) {
        return packed >> BLACKLISTED_BITPOS != 0;
    }

}