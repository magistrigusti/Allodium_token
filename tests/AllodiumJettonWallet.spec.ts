import { Blockchain, SandboxContract, TreasuryContract } from '@ton/sandbox';
import { toNano, beginCell, Cell } from '@ton/core';
import { compile } from '@ton/blueprint';
import { AllodiumJettonWallet } from '../wrappers/AllodiumJettonWallet';
import '@ton/test-utils';

describe('AllodiumJettonWallet', () => {
    let blockchain: Blockchain;
    let deployer: SandboxContract<TreasuryContract>;
    let masterWallet: SandboxContract<TreasuryContract>;
    let userWallet: SandboxContract<AllodiumJettonWallet>;
    let walletCode: Cell;

    beforeAll(async () => {
        walletCode = await compile('AllodiumJettonWallet');
    });

    beforeEach(async () => {
        blockchain = await Blockchain.create();

        deployer = await blockchain.treasury('deployer');
        masterWallet = await blockchain.treasury('master');

        userWallet = blockchain.openContract(
            AllodiumJettonWallet.createFromConfig(
                {
                    masterAddress: masterWallet.address,
                    ownerAddress: deployer.address,
                    inflationAddress: deployer.address,
                },
                walletCode
            )
        );

        const deployResult = await userWallet.sendDeploy(deployer.getSender(), toNano('0.05'));

        expect(deployResult.transactions).toHaveTransaction({
            from: deployer.address,
            to: userWallet.address,
            deploy: true,
            success: true
        });
    });

    it('should correctly initialize wallet data', async () => {
        const data = await userWallet.getWalletData();

        expect(data.balance).toBe(0n);
        expect(data.owner.equals(deployer.address)).toBeTruthy();
        expect(data.master.equals(masterWallet.address)).toBeTruthy();
    });

    it('should correctly process internal token transfer', async () => {
        const transferAmount = toNano('10');

        const tokenTransferInternalBody = beginCell()
            .storeUint(0x178d4519, 32)
            .storeUint(1n, 64)
            .storeCoins(transferAmount)
            .storeAddress(masterWallet.address)
            .storeAddress(masterWallet.address)
            .storeCoins(0)
            .storeRef(beginCell().endCell())
            .endCell();

        await masterWallet.send({
            to: userWallet.address,
            value: toNano('0.05'),
            body: tokenTransferInternalBody,
        });

        const dataAfterTransfer = await userWallet.getWalletData();
        expect(dataAfterTransfer.balance).toBe(transferAmount);
    });

    it('should burn tokens correctly', async () => {
        const initialAmount = toNano('20');
        const burnAmount = toNano('5');

        const tokenTransferInternalBody = beginCell()
            .storeUint(0x178d4519, 32)
            .storeUint(2n, 64)
            .storeCoins(initialAmount)
            .storeAddress(masterWallet.address)
            .storeAddress(masterWallet.address)
            .storeCoins(0)
            .storeRef(beginCell().endCell())
            .endCell();

        await masterWallet.send({
            to: userWallet.address,
            value: toNano('0.05'),
            body: tokenTransferInternalBody,
        });

        await userWallet.sendBurn(deployer.getSender(), burnAmount);

        const dataAfterBurn = await userWallet.getWalletData();
        expect(dataAfterBurn.balance).toBe(initialAmount - burnAmount);
    });
});
