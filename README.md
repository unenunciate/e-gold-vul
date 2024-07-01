# Liquidity Pools [![Github Actions][gha-badge]][gha] [![Foundry][foundry-badge]][foundry] [![License: AGPL v3]

## How it works

Investors can deposit in multiple commodity liquidity pools for each type of warrant which is equvilant the e-gold stablecoin in everyway execpt it can be burned in exchange for liquidity to be returned to the investor so they may recieve better loan rates and reduced volitility without a taxable sale event. Each of these tranches is a separate deployment of an [ERC-7540](https://eips.ethereum.org/EIPS/eip-7540) Vault and a Tranche Token.
- [**ERC7540Vault**](https://github.com/centrifuge/liquidity-pools/blob/main/src/ERC7540Vault.sol): An [ERC-7540](https://eips.ethereum.org/EIPS/eip-7540) (extension of [ERC-4626](https://ethereum.org/en/developers/docs/standards/tokens/erc-4626/)) compatible contract that enables investors to deposit and withdraw commodities to invest in gold denominated liquidity pools in exchange for E-gold warrants.
- [**E-gold Stablecoin**]: An [ERC-20](https://ethereum.org/en/developers/docs/standards/tokens/erc-20/) token for the stable coin, linked to a [`RestrictionManager`](https://github.com/centrifuge/liquidity-pools/blob/main/src/token/RestrictionManager.sol) that manages transfer restrictions. Prices for e-gold tokens are determined by the market.

The deployment of these tranches and the management of investments is controlled by the underlying InvestmentManager, PoolManager, Gateway, Aggregator, and Adapters.
- [**VUL Investment Manager**](https://github.com/centrifuge/liquidity-pools/blob/main/src/InvestmentManager.sol): The core business logic contract that handles pool creation, tranche deployment, managing investments and sending tokens to the [`Escrow`](https://github.com/centrifuge/liquidity-pools/blob/main/src/Escrow.sol), and more.
- [**Pool Manager**](https://github.com/centrifuge/liquidity-pools/blob/main/src/PoolManager.sol): The second business logic contract that handles asset bookkeeping, and transferring tranche tokens as well as assets.


## License
This codebase is licensed under [GNU Lesser General Public License v3.0](https://github.com/centrifuge/liquidity-pools/blob/main/LICENSE).
