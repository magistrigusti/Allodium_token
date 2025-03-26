export * from '../build/Allodium/tact_Allodium';

import {
  Address, toNano, Cell, beginCell, Contract, ContractProvider, Sender, SendMode, contractAddress
} from '@ton/core';

export type AllodiumJettonWalletConfig = {
  masterAddress: Address;
  ownerAddress: Address;
  burnAddress: Address;
  inflationAddress: Address;
};

export function allodiumJettonWalletConfigToCell(config: AllodiumJettonWalletConfig): Cell {
  return beginCell()
    .storeAddress(config.masterAddress)
    .storeAddress(config.ownerAddress)
    .storeAddress(config.burnAddress)
    .storeAddress(config.inflationAddress)
    .endCell();
}

export class AllodiumJettonWallet implements Contract {
  constructor(
    public readonly address: Address,
    public readonly init?: {code: Cell; data: Cell}
  ) {}

  static createFromConfig(config: AllodiumJettonWalletConfig, code: Cell, workchain = 0) {
    const data = allodiumJettonWalletConfigToCell(config);
    const init = { code, data };

    return new AllodiumJettonWallet(contractAddress(workchain, init), init);
  }

  async sendDeploy(provider: ContractProvider, via: Sender, value: bigint) {
    await provider.internal(via, {
      value,
      sendMode: SendMode.PAY_GAS_SEPARATELY,
      body: beginCell().storeUint(0, 32).storeUint(0, 64).endCell()
    });
  }

  async sendBurn(provider: ContractProvider, via: Sender, amount: bigint, queryId: bigint = 0n) {
    await provider.internal(via, {
      value: amount,
      sendMode: SendMode.PAY_GAS_SEPARATELY,
      body: beginCell()
        .storeUint(0x595f07bc, 32)
        .storeUint(queryId, 64)
        .storeCoins(amount)
        .storeAddress(via.address)
        .storeMaybeRef(null)
        .endCell()
    });
  }

  async getWalletData(provider: ContractProvider) {
    const result = await provider.get('get_wallet_dat', []);

    return {
      balance: result.stack.readBigNumber(),
      owner: result.stack.readAddress(),
      master: result.stack.readAddress(),
      walletCode: result.stack.readCell(),
    }
  }

  async sendTransfer(
    provider: ContractProvider,
    via: Sender,
    params: {
      queryId?: bigint,
      amount: bigint,
      destination: Address,
      responseDestination?: Address | null,
      forwardTonAmount: bigint,
      forwardPayload: Cell
    }
  ) {
    const body = beginCell()
      .storeUint(0xf8a7ea5, 32)
      .storeUint(params.queryId ?? 0n, 64)
      .storeCoins(params.amount)
      .storeAddress(params.destination)
      .storeAddress(params.responseDestination ?? null)
      .storeBit(0)
      .storeCoins(params.forwardTonAmount)
      .storeBit(1)
      .storeRef(params.forwardPayload)
    .endCell();

    await provider.internal(via, {
      value: params.forwardTonAmount + toNano("0.01"),
      sendMode: SendMode.PAY_GAS_SEPARATELY,
      body,
    });
  }

}
