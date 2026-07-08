import { useState } from 'react'
import {
  useAccount,
  useConnect,
  useDisconnect,
  useReadContract,
  useWriteContract,
  useWaitForTransactionReceipt,
} from 'wagmi'
import { formatUnits, parseEther } from 'viem'
import {
  DEMO_TOKEN_ADDRESS,
  DEMO_VAULT_ADDRESS,
  demoTokenAbi,
  demoVaultAbi,
} from './contracts'

// DEMO has the usual 18 decimals. sDEMO shares have 21: OZ's ERC4626
// adds the vault's _decimalsOffset() (3) to the asset's decimals as
// part of the inflation-attack defense. Format each with the right one.
const ASSET_DECIMALS = 18
const SHARE_DECIMALS = 21
// 1 whole sDEMO share, in share-wei (10^21).
const ONE_SHARE = 10n ** BigInt(SHARE_DECIMALS)

function fmt(value?: bigint, decimals = ASSET_DECIMALS, digits = 4) {
  if (value === undefined) return '…'
  const n = Number(formatUnits(value, decimals))
  return n.toLocaleString(undefined, { maximumFractionDigits: digits })
}

export default function App() {
  const { address, isConnected } = useAccount()
  const { connect, connectors, isPending: connecting } = useConnect()
  const { disconnect } = useDisconnect()

  const [depositAmount, setDepositAmount] = useState('')
  const [withdrawAmount, setWithdrawAmount] = useState('')

  // ───────────── Reads (view functions — free, no gas) ─────────────
  // Polling every 2s makes the position value + share price visibly
  // tick up during the demo: totalAssets() includes pending yield.
  const { data: balance } = useReadContract({
    address: DEMO_TOKEN_ADDRESS,
    abi: demoTokenAbi,
    functionName: 'balanceOf',
    args: [address!],
    query: { enabled: !!address, refetchInterval: 2000 },
  })

  const { data: allowance } = useReadContract({
    address: DEMO_TOKEN_ADDRESS,
    abi: demoTokenAbi,
    functionName: 'allowance',
    args: [address!, DEMO_VAULT_ADDRESS],
    query: { enabled: !!address, refetchInterval: 2000 },
  })

  // Your vault shares (sDEMO) — the vault itself is an ERC-20.
  const { data: shares } = useReadContract({
    address: DEMO_VAULT_ADDRESS,
    abi: demoVaultAbi,
    functionName: 'balanceOf',
    args: [address!],
    query: { enabled: !!address, refetchInterval: 2000 },
  })

  // What those shares are redeemable for RIGHT NOW, yield included.
  const { data: positionValue } = useReadContract({
    address: DEMO_VAULT_ADDRESS,
    abi: demoVaultAbi,
    functionName: 'convertToAssets',
    args: [shares ?? 0n],
    query: { enabled: shares !== undefined, refetchInterval: 2000 },
  })

  // Share price = value of exactly 1 whole sDEMO share, in DEMO.
  const { data: sharePrice } = useReadContract({
    address: DEMO_VAULT_ADDRESS,
    abi: demoVaultAbi,
    functionName: 'convertToAssets',
    args: [ONE_SHARE],
    query: { refetchInterval: 2000 },
  })

  const { data: totalAssets } = useReadContract({
    address: DEMO_VAULT_ADDRESS,
    abi: demoVaultAbi,
    functionName: 'totalAssets',
    query: { refetchInterval: 2000 },
  })

  // ───────────── Writes (transactions — signed by the wallet) ─────────────
  const { writeContract, data: txHash, isPending, error } = useWriteContract()
  const { isLoading: confirming } = useWaitForTransactionReceipt({ hash: txHash })
  const busy = isPending || confirming

  const depositWei = depositAmount ? parseEther(depositAmount) : 0n
  const needsApproval = allowance !== undefined && depositWei > allowance
  const yieldEarned =
    positionValue !== undefined && shares !== undefined ? positionValue : undefined

  if (!isConnected) {
    return (
      <main className="page">
        <h1>🏦 DEMO Vault (ERC-4626)</h1>
        <p className="sub">
          Deposit DEMO, receive sDEMO shares. Yield streams into the vault
          every second, so the share price only goes up — no claiming needed.
          <br />
          Running on a local Anvil chain — connect your wallet to start.
        </p>
        {connectors.map((connector) => (
          <button
            key={connector.uid}
            className="primary"
            disabled={connecting}
            onClick={() => connect({ connector })}
          >
            {connecting ? 'Connecting…' : `Connect ${connector.name}`}
          </button>
        ))}
      </main>
    )
  }

  return (
    <main className="page">
      <header className="bar">
        <h1>🏦 DEMO Vault</h1>
        <div className="who">
          <code>
            {address?.slice(0, 6)}…{address?.slice(-4)}
          </code>
          <button onClick={() => disconnect()}>Disconnect</button>
        </div>
      </header>

      <section className="stats">
        <div className="stat">
          <span>Wallet balance</span>
          <strong>{fmt(balance)} DEMO</strong>
        </div>
        <div className="stat">
          <span>Your shares</span>
          <strong>{fmt(shares, SHARE_DECIMALS)} sDEMO</strong>
        </div>
        <div className="stat highlight">
          <span>Position value (live)</span>
          <strong>{fmt(yieldEarned)} DEMO</strong>
        </div>
        <div className="stat highlight">
          <span>Share price</span>
          <strong>{fmt(sharePrice, ASSET_DECIMALS, 6)} DEMO</strong>
        </div>
        <div className="stat">
          <span>Vault TVL</span>
          <strong>{fmt(totalAssets)} DEMO</strong>
        </div>
      </section>

      <section className="card">
        <h2>1 · Get test tokens</h2>
        <p>The faucet mints you 100 DEMO (once per minute).</p>
        <button
          className="primary"
          disabled={busy}
          onClick={() =>
            writeContract({
              address: DEMO_TOKEN_ADDRESS,
              abi: demoTokenAbi,
              functionName: 'faucet',
            })
          }
        >
          Claim 100 DEMO
        </button>
      </section>

      <section className="card">
        <h2>2 · Deposit</h2>
        <p>
          Deposit DEMO and the vault mints you sDEMO shares at the current
          share price. First it needs your <em>approval</em> to pull tokens —
          the standard two-step ERC-20 flow.
        </p>
        <div className="row">
          <input
            type="number"
            placeholder="Amount (DEMO)"
            value={depositAmount}
            onChange={(e) => setDepositAmount(e.target.value)}
          />
          {needsApproval ? (
            <button
              className="primary"
              disabled={busy || !depositAmount}
              onClick={() =>
                writeContract({
                  address: DEMO_TOKEN_ADDRESS,
                  abi: demoTokenAbi,
                  functionName: 'approve',
                  args: [DEMO_VAULT_ADDRESS, depositWei],
                })
              }
            >
              Approve
            </button>
          ) : (
            <button
              className="primary"
              disabled={busy || !depositAmount}
              onClick={() =>
                writeContract({
                  address: DEMO_VAULT_ADDRESS,
                  abi: demoVaultAbi,
                  functionName: 'deposit',
                  args: [depositWei, address!],
                })
              }
            >
              Deposit
            </button>
          )}
        </div>
      </section>

      <section className="card">
        <h2>3 · Withdraw</h2>
        <p>
          No claim button — yield auto-compounds into the share price. Pull an
          exact DEMO amount, or redeem all your shares at once.
        </p>
        <div className="row">
          <input
            type="number"
            placeholder="Amount (DEMO)"
            value={withdrawAmount}
            onChange={(e) => setWithdrawAmount(e.target.value)}
          />
          <button
            disabled={busy || !withdrawAmount}
            onClick={() =>
              writeContract({
                address: DEMO_VAULT_ADDRESS,
                abi: demoVaultAbi,
                functionName: 'withdraw',
                args: [parseEther(withdrawAmount), address!, address!],
              })
            }
          >
            Withdraw
          </button>
        </div>
        <div className="row">
          <button
            className="primary"
            disabled={busy || !shares}
            onClick={() =>
              writeContract({
                address: DEMO_VAULT_ADDRESS,
                abi: demoVaultAbi,
                functionName: 'redeem',
                args: [shares!, address!, address!],
              })
            }
          >
            Redeem all shares
          </button>
        </div>
      </section>

      {busy && <p className="status">⏳ Transaction pending…</p>}
      {error && <p className="status error">{error.message.split('\n')[0]}</p>}
    </main>
  )
}
