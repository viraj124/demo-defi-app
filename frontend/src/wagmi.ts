import { http, createConfig } from 'wagmi'
import { foundry } from 'wagmi/chains'
import { injected } from 'wagmi/connectors'

// wagmi config: which chains we support, how to connect wallets,
// and which RPC endpoint to talk to.
//
// `foundry` = the local Anvil chain (chainId 31337, http://127.0.0.1:8545).
// `injected()` = any browser-extension wallet (MetaMask, Rabby, ...).
export const config = createConfig({
  chains: [foundry],
  connectors: [injected()],
  transports: {
    [foundry.id]: http('http://127.0.0.1:8545'),
  },
})
