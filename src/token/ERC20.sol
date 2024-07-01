// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Auth} from "src/Auth.sol";
import {EIP712Lib} from "src/libraries/EIP712Lib.sol";
import {SignatureLib} from "src/libraries/SignatureLib.sol";
import {IERC20, IERC20Metadata, IERC20Permit} from "src/interfaces/IERC20.sol";

/// @title  ERC20
/// @notice Standard ERC-20 implementation, with mint/burn functionality and permit logic.
/// @author Modified from https://github.com/makerdao/xdomain-dss/blob/master/src/Dai.sol
contract ERC20 is Auth, IERC20Metadata, IERC20Permit {
    /// @inheritdoc IERC20Metadata
    string public name;
    /// @inheritdoc IERC20Metadata
    string public symbol;
    /// @inheritdoc IERC20Metadata
    uint8 public immutable decimals;
    /// @inheritdoc IERC20
    uint256 public totalSupply;

    /// @inheritdoc IERC20
    mapping(address => uint256) public balanceOf;

    // # of OZ of gold available to market for minting liquidity
    mapping(address => uint256) public balanceOfLiquidity;
    // # of OZ of gold available to investor for minting liquidity
    mapping(address => uint256) public balanceOfGold;
    // Amount of fiat available to market for minting liquidity
    mapping(address => uint256) public balanceOfFiat;

    /// @inheritdoc IERC20
    mapping(address => mapping(address => uint256)) public allowance;
    /// @inheritdoc IERC20Permit
    mapping(address => uint256) public nonces;

    uint256 public marketValue;
    uint256 public goldNAValue;

    uint256 public fiatBacking;
    uint256 public goldBacking;

    uint256 public riskLower;
    uint256 public riskUpper;

    uint256 public immutable valueShelfLife = 15000;
    uint256 public immutable valueUpdateWindow = 120;

    uint256 public lastValueUpdateBlock;

    address public fiatGoldPool;
    address public commodityGoldPool;

    address public fiatToken;
    address public goldToken;

    address public commodityToken;
    address public immutable L1BlockAddress = 0x4200000000000000000000000000000000000015;

    // --- EIP712 ---
    bytes32 private immutable nameHash;
    bytes32 private immutable versionHash;
    uint256 public immutable deploymentChainId;
    bytes32 private immutable _DOMAIN_SEPARATOR;
    bytes32 public constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    // --- Events ---
    event File(bytes32 indexed what, string data);

    constructor(uint8 decimals_) {
        decimals = decimals_;
        wards[msg.sender] = 1;
        emit Rely(msg.sender);

        fiatBacking = 35;

        goldBacking = 65;

        lastValueUpdateBlock = 0;

        marketValue = 0;

        goldNAValue = 0;

        riskLower = 50;
        riskUpper = 100;

        commodityToken = 0x0000000000000000000000000000000000000000;

        nameHash = keccak256(bytes("Centrifuge"));
        versionHash = keccak256(bytes("1"));
        deploymentChainId = block.chainid;
        _DOMAIN_SEPARATOR = EIP712Lib.calculateDomainSeparator(nameHash, versionHash);

        fiatToken = 0x0000000000000000000000000000000000000000;
        goldToken = 0x0000000000000000000000000000000000000000;

        fiatGoldPool = 0x0000000000000000000000000000000000000000;
        commodityGoldPool = 0x0000000000000000000000000000000000000000;
    }

    /// @inheritdoc IERC20Permit
    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return block.chainid == deploymentChainId
            ? _DOMAIN_SEPARATOR
            : EIP712Lib.calculateDomainSeparator(nameHash, versionHash);
    }

    function file(bytes32 what, string memory data) external auth {
        if (what == "name") name = data;
        else if (what == "symbol") symbol = data;
        else revert("ERC20/file-unrecognized-param");
        emit File(what, data);
    }

    modifier freshValueData() {
        require(address(this.L1BlockAddress).call(abi.encodeWithSignature("number()")) < this.valueShelfLife + this.lastValueUpdateBlock);
        _;
    }

    function updateValueData(uint mValue, uint goldValue) external auth returns (bool) {
        uint256 BlockNum = address(this.L1BlockAddress).call(abi.encodeWithSignature("number()"));
        require(BlockNum + this.valueUpdateWindow >= this.valueShelfLife + this.lastValueUpdateBlock, "EGOLD/update-failed-window-closed");

        this.marketValue = mValue;
        this.goldNAValue = goldValue;
        this.lastValueUpdateBlock = BlockNum + this.valueShelfLife;

        return this.lastValueUpdateBlock == this.l1b.number() + this.valueShelfLife;
    }

    function rebalance(uint fiatValue, uint goldValue) external auth returns (bool) {
        require(100 == fiatValue + goldValue, "EGOLD/invalid-rebalance-ratio");

        this.fiatBacking = fiatValue;
        this.goldBacking = goldValue;

        return this.fiatBacking + goldValue == 100;
    }

    function depositEscrow(uint value) external freshValueData returns (bool) {
        require(value > 0, "EGOLD/value-out-of-bounds-error");

        uint fiatVal = ((marketValue * value) * fiatBacking)/100;
        uint goldVal = (value * goldBacking)/100;

        require(this.fiatToken.balanceOf(msg.sender) >= fiatVal, "EGOLD/fiat-token-insufficent-balance-error");
        require(this.goldToken.balanceOf(msg.sender) >= goldVal, "EGOLD/gold-token-insufficent-balance-error");
        require(this.fiatToken.allowed(this, msg.sender, fiatVal) >= fiatVal, "EGOLD/fiat-token-insufficent-allowance-error");
        require(this.goldToken.allowed(this, msg.sender, goldVal) >= goldVal, "EGOLD/gold-token-insufficent-allowance-error");

        bool fiatTransferSuccess = this.fiatToken.transferFrom(msg.sender, this, fiatVal);
        bool goldTransferSuccess = this.goldToken.transferFrom(msg.sender, this, goldVal);

        require(fiatTransferSuccess & goldTransferSuccess, "EGOLD/token-transfer-internal-error");

        this.balanceOfFiat[msg.sender] += fiatVal;
        this.balanceOfGold[msg.sender] += goldVal;

        return fiatTransferSuccess & goldTransferSuccess;
    }

    function provideLiquidity(uint value) external returns (bool) {
        require(value > 0, "EGOLD/value-out-of-bounds-error");
        uint bal = goldToken.balanceOf(msg.sender);
        require(bal >= value, "EGOLD/insufficent-liquidity-balance");
        bool success =  goldToken.transferFrom(msg.sender, this, value);
        require(success, "EGOLD/liquidity-allowance-not-authorized");
        balanceOfLiquidity[msg.sender] += value;

        this.liquidityReserves += value;

        return success;
    }

    function withdrawLiquidity(uint value) external returns (bool) {
        require(value > 0, "EGOLD/value-out-of-bounds-error");
        require(this.liquidityReserves >= value, "EGOLD/liquidity-reserves-insufficent-error");
        uint bal = this.balanceOfLiquidity[msg.sender];
        require(bal <= value & bal - value >= 0, "EGOLD/insufficent-balance");
        bool success = this.goldToken.transferFrom(address(this), msg.sender, value);
        require(success, "EGOLD/liquidity-allowance-not-authorized");
        this.balanceOfLiquidity[msg.sender] -= value;

        this.liquidityReserves -= value;

        return success;
    }

    function _provideLiquidity(uint value) internal returns (bool) {
        require(value > 0, "EGOLD/value-out-of-bounds-error");
        require(value <= this.liquidityReserves, "EGOLD/liquidity-reserves-insufficent-error");

        uint fiatVal = ((marketValue * value) * fiatBacking)/100;
        uint goldVal = (value * goldBacking)/100;

        require(this.balanceOfFiat[msg.sender] >= fiatVal, "EGOLD/fiat-reserves-insufficent-error");
        require(this.balanceOfGold[msg.sender] >= goldVal, "EGOLD/gold-reserves-insufficent-error");

        bool fiatMintSuccess = fiatGoldPool.mint(address(this), riskLower, riskUpper, fiatVal);
        require(!fiatMintSuccess, "EGOLD/fiat-liquidity-provisioning-failed");
        bool commodityMintSuccess = commodityGoldPool.mint(address(this), riskLower, riskUpper, goldVal);
        require(!commodityMintSuccess, "EGOLD/gold-liquidity-provisioning-failed");

        this.balanceOfFiat[msg.sender] -= fiatVal;
        this.balanceOfGold[msg.sender] -= goldVal;
        this.liquidityReserves -= value;

        bool validState = this.balanceOfFiat[msg.sender] >= 0 & this.balanceOfGold[msg.sender] >= 0 & this.liquidityReserves >= 0;

        require(validState, "EGOLD/invalid-balance-state-error");

        return validState;
    }

    function _reclaimLiquidityFormPools(uint value) internal returns (bool) {
       require(value > 0, "EGOLD/value-out-of-bounds-error");
        require(balanceOf[msg.sender] >= value, "EGOLD/balance-insufficent-error");

        uint fiatVal = (marketValue * value * fiatBacking)/100;
        uint goldVal = (marketValue * value * goldBacking)/100;

        require(fiatToken.balanceOf(this) >= fiatVal, "EGOLD/fait-reserves-insufficent-error");
        require(goldToken.balanceOf(this) >= fiatVal, "EGOLD/gold-reserves-insufficent-error");

        bool fiatReclaimSuccess = fiatGoldPool.modifyPosition(address(this), riskLower, riskUpper, fiatVal);
        require(fiatReclaimSuccess, "EGOLD/fiat-liquidity-reclaim-failed");
        bool commodityReclaimSuccess = commodityGoldPool.modifyPosition(address(this), riskLower, riskUpper, goldVal);
        require(commodityReclaimSuccess, "EGOLD/fiat-liquidity-reclaim-failed");

        this.balanceOfFiat[msg.sender] += fiatVal;
        this.balanceOfGold[msg.sender] += goldVal;
        this.liquidityReserves += value;

        bool validState = this.balanceOfFiat[msg.sender] >= 0 & this.balanceOfGold[msg.sender] >= 0 & this.liquidityReserves >= 0;

        require(validState, "EGOLD/invalid-balance-state-error");

        return validState;
    }

    // --- ERC20 Mutations ---
    /// @inheritdoc IERC20
    function transfer(address to, uint256 value) public virtual returns (bool) {
        require(to != address(0) && to != address(this), "ERC20/invalid-address");
        uint256 balance = balanceOf[msg.sender];
        require(balance >= value, "ERC20/insufficient-balance");

        unchecked {
            balanceOf[msg.sender] = balance - value;
            balanceOf[to] += value; // note: we don't need an overflow check here b/c sum of all balances == totalSupply
        }

        emit Transfer(msg.sender, to, value);

        return true;
    }

    /// @inheritdoc IERC20
    function transferFrom(address from, address to, uint256 value) public virtual returns (bool) {
        return _transferFrom(msg.sender, from, to, value);
    }

    function _transferFrom(address sender, address from, address to, uint256 value) internal virtual returns (bool) {
        require(to != address(0) && to != address(this), "ERC20/invalid-address");
        uint256 balance = balanceOf[from];
        require(balance >= value, "ERC20/insufficient-balance");

        if (from != sender) {
            uint256 allowed = allowance[from][sender];
            if (allowed != type(uint256).max) {
                require(allowed >= value, "ERC20/insufficient-allowance");
                unchecked {
                    allowance[from][sender] = allowed - value;
                }
            }
        }

        unchecked {
            balanceOf[from] = balance - value;
            balanceOf[to] += value; // note: we don't need an overflow check here b/c sum of all balances == totalSupply
        }

        emit Transfer(from, to, value);

        return true;
    }

    /// @inheritdoc IERC20
    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;

        emit Approval(msg.sender, spender, value);

        return true;
    }

    // --- Mint/Burn ---
    // 1 Value == 1 unit of E-Gold
    function mint(address to, uint256 value) public virtual auth freshValueData {
        require(to != address(0) && to != address(this), "ERC20/invalid-address");
        /**
        bool success = this._provideLiquidity(marketValue);

        require(success, "EGOLD/liquidity-provisioning-failure")
        */
        unchecked {
            // We don't need an overflow check here b/c balanceOf[to] <= totalSupply
            // and there is an overflow check below
            balanceOf[to] = balanceOf[to] + value;
        }

        totalSupply = totalSupply + value;

        emit Transfer(address(0), to, value);
    }

    function burn(address from, uint256 value) external auth freshValueData {
        uint256 balance = balanceOf[from];
        require(balance >= value, "ERC20/insufficient-balance");

        if (from != msg.sender) {
            uint256 allowed = allowance[from][msg.sender];
            if (allowed != type(uint256).max) {
                require(allowed >= value, "ERC20/insufficient-allowance");

                unchecked {
                    allowance[from][msg.sender] = allowed - value;
                }
            }
        }

        bool success = _reclaimLiquidityFormPools(from, value);

        require(success, "EGOLD/liquidity-reclaim-failure");

        unchecked {
            // We don't need overflow checks b/c require(balance >= value) and balance <= totalSupply
            balanceOf[from] = balance - value;
            totalSupply = totalSupply - value;
        }

        emit Transfer(from, address(0), value);
    }

    // --- Approve by signature ---
    function permit(address owner, address spender, uint256 value, uint256 deadline, bytes memory signature) public {
        require(block.timestamp <= deadline, "ERC20/permit-expired");
        require(owner != address(0), "ERC20/invalid-owner");

        uint256 nonce;
        unchecked {
            nonce = nonces[owner]++;
        }

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR(),
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonce, deadline))
            )
        );

        require(SignatureLib.isValidSignature(owner, digest, signature), "ERC20/invalid-permit");

        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    /// @inheritdoc IERC20Permit
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
    {
        permit(owner, spender, value, deadline, abi.encodePacked(r, s, v));
    }

    // --- Fail-safe ---
    function authTransferFrom(address sender, address from, address to, uint256 value) public auth returns (bool) {
        return _transferFrom(sender, from, to, value);
    }
}
