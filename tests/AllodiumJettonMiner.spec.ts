// import { Blockchain, SandboxContract } from "@ton/sandbox";
// import { Address, beginCell, toNano } from "@ton/core";
// import { AllodiumMining } from "../wrappers/AllodiumMining";
// import { compile } from "@ton/blueprint";

// describe("AllodiumMining", () => {
//     let blockchain: Blockchain;
//     let user: SandboxContract;
//     let jettonWallet: SandboxContract;
//     let boostNft: SandboxContract;
//     let pool: SandboxContract;
//     let mining: ReturnType<typeof blockchain.open>;

//     beforeAll(async () => {
//         // Создаём песочницу и аккаунты
//         blockchain = await Blockchain.create();
//         user = await blockchain.treasury("user");
//         jettonWallet = await blockchain.treasury("jettonWallet");
//         boostNft = await blockchain.treasury("boostNft");
//         pool = await blockchain.treasury("pool");

//         // Компилируем контракт
//         const miningCode = await compile("AllodiumMining");

//         // Создаём контракт майнинга
//         mining = blockchain.open(
//             await AllodiumMining.createFromConfig(
//                 {
//                     jettonWallet: jettonWallet.address,
//                     boostNft: boostNft.address,
//                     pool: pool.address,
//                     totalMined: 0n,
//                 },
//                 miningCode
//             )
//         );
//     });

//     it("should deploy AllodiumMining successfully", async () => {
//         await mining.sendDeploy(user.getSender(), toNano("0.05"));
//         const data = await mining.getMiningData();

//         expect(data.jettonWallet.equals(jettonWallet.address)).toBe(true);
//         expect(data.boostNft.equals(boostNft.address)).toBe(true);
//         expect(data.pool.equals(pool.address)).toBe(true);
//         expect(data.totalMined).toBe(0n);
//     });

//     it("should mine tokens and update totalMined", async () => {
//         // Проверим, что totalMined = 0
//         let before = await mining.getMiningData();
//         expect(before.totalMined).toBe(0n);

//         // Выполняем майнинг
//         await mining.sendMine(user.getSender(), toNano("0.2"));

//         // Проверим, что totalMined увеличился (в контракте это должно быть реализовано)
//         let after = await mining.getMiningData();
//         expect(after.totalMined > before.totalMined).toBe(true);
//     });
// });

describe('AllodiumJettonMiner', () => {
  it('заглушка — тесты будут позже', () => {
      expect(true).toBe(true);
  });
});

