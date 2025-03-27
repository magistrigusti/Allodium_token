import {
  Address,
  beginCell,
  Cell,
  Contract,
  contractAddress,
  ContractProvider,
  Sender,
  SendMode,
} from "@ton/core";
import { compile } from "@ton/blueprint";

// Тип конфигурации контракта майнинга
export type AllodiumMiningConfig = {
  jettonWallet: Address;
  boostNft: Address;
  pool: Address;
  totalMined: bigint;
};

// Сериализация конфига в Cell
export function allodiumMiningConfigToCell(config: AllodiumMiningConfig): Cell {
  return beginCell()
      .storeAddress(config.jettonWallet)
      .storeAddress(config.boostNft)
      .storeAddress(config.pool)
      .storeCoins(config.totalMined)
      .endCell();
}

// Основной класс обёртки
export class AllodiumMining implements Contract {
  constructor(readonly address: Address, readonly init?: { code: Cell; data: Cell }) {}

  static async compileCode(): Promise<Cell> {
      return await compile("AllodiumMining");
  }

  static async createFromConfig(config: AllodiumMiningConfig, code: Cell): Promise<AllodiumMining> {
      const data = allodiumMiningConfigToCell(config);
      const init = { code, data };
      const address = contractAddress(0, init);
      return new AllodiumMining(address, init);
  }

  async sendDeploy(provider: ContractProvider, via: Sender, value: bigint) {
      await provider.internal(via, {
          value,
          sendMode: SendMode.PAY_GAS_SEPARATELY,
          body: new Cell(),
      });
  }

  // Получение текущих данных о состоянии майнинга
  async getMiningData(provider: ContractProvider) {
      const { stack } = await provider.get("get_mining_data", []);
      return {
          jettonWallet: stack.readAddress(),
          boostNft: stack.readAddress(),
          pool: stack.readAddress(),
          totalMined: stack.readBigNumber(),
      };
  }

  // Вызов процесса майнинга
  async sendMine(provider: ContractProvider, via: Sender, value: bigint) {
      await provider.internal(via, {
          value,
          sendMode: SendMode.PAY_GAS_SEPARATELY,
          body: beginCell()
              .storeUint(0xf4a573b3, 32) // Опкод mine()
              .endCell(),
      });
  }
}
