// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {BytesLib} from "src/libraries/BytesLib.sol";
import {CastLib} from "src/libraries/CastLib.sol";

/// @title  MessagesLib
/// @dev    Library for encoding and decoding messages.
library MessagesLib {
    using BytesLib for bytes;
    using CastLib for *;

    enum Call {
        /// 0 - An invalid message
        Invalid,
        /// 1 - Add an asset id -> EVM address mapping
        AddAsset,
        /// 2 - Add Pool
        AddPool,
        /// 3 - Allow an asset to be used as an asset for investing in pools
        AllowAsset,
        /// 4 - Add a Pool's Tranche Token
        AddTranche,
        /// 5 - Update the price of a Tranche Token
        UpdateTrancheTokenPrice,
        /// 6 - Update the member list of a tranche token with a new member
        UpdateMember,
        /// 7 - A transfer of assets
        Transfer,
        /// 8 - A transfer of tranche tokens
        TransferTrancheTokens,
        /// 9 - Increase an investment order by a given amount
        IncreaseInvestOrder,
        /// 10 - Decrease an investment order by a given amount
        DecreaseInvestOrder,
        /// 11 - Increase a Redeem order by a given amount
        IncreaseRedeemOrder,
        /// 12 - Decrease a Redeem order by a given amount
        DecreaseRedeemOrder,
        /// 13 - Collect investment
        DEPRECATED_CollectInvest,
        /// 14 - Collect Redeem
        DEPRECATED_CollectRedeem,
        /// 15 - Executed Decrease Invest Order
        FulfilledCancelDepositRequest,
        /// 16 - Executed Decrease Redeem Order
        FulfilledCancelRedeemRequest,
        /// 17 - Executed Collect Invest
        FulfilledDepositRequest,
        /// 18 - Executed Collect Redeem
        FulfilledRedeemRequest,
        /// 19 - Cancel an investment order
        CancelInvestOrder,
        /// 20 - Cancel a redeem order
        CancelRedeemOrder,
        /// 21 - Schedule an upgrade contract to be granted admin rights
        ScheduleUpgrade,
        /// 22 - Cancel a previously scheduled upgrade
        CancelUpgrade,
        /// 23 - Update tranche token metadata
        UpdateTrancheTokenMetadata,
        /// 24 - Disallow an asset to be used as an asset for investing in pools
        DisallowAsset,
        /// 25 - Freeze tranche tokens
        Freeze,
        /// 26 - Unfreeze tranche tokens
        Unfreeze,
        /// 27 - Request redeem investor
        TriggerRedeemRequest,
        /// 28 - Proof
        MessageProof,
        /// 29 - Initiate Message Recovery
        InitiateMessageRecovery,
        /// 30 - Dispute Message Recovery
        DisputeMessageRecovery,
        /// 31 - Recover Tokens sent to the wrong contract
        RecoverTokens
    }

    enum Domain {
        Centrifuge,
        EVM
    }

    function messageType(bytes memory _msg) internal pure returns (Call _call) {
        _call = Call(_msg.toUint8(0));
    }

    // Utils
    function formatDomain(Domain domain) internal pure returns (bytes9) {
        return bytes9(bytes1(uint8(domain)));
    }

    function formatDomain(Domain domain, uint64 chainId) internal pure returns (bytes9) {
        return bytes9(BytesLib.slice(abi.encodePacked(uint8(domain), chainId), 0, 9));
    }
}
