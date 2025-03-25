import { Blockchain, SandboxContract, TreasuryContract } from '@ton/sandbox';
import { toNano, beginCell, Cell } from '@ton/core';
import { compile } from '@ton/blueprint';
import { AllodiumJettonWallet } from '../wrappers/AllodiumJettonWallet';
import '@ton/test-utils';

describe('AllodiumJettonWallet', () => {
    let blockchain: Blockchain;
    let walletCode: Cell;
    let wallet: SandboxContract<AllodiumJettonWallet>;
    let deployer: SandboxContract<TreasuryContract>;
    let masterWallet: SandboxContract<TreasuryContract>;
    let inflationWallet: SandboxContract<TreasuryContract>;

    beforeAll(async () => {
        walletCode = await compile('AllodiumJettonWallet');
    });

    beforeEach(async () => {
        blockchain = await Blockchain.create();

        deployer = await blockchain.treasury('deployer');
        masterWallet = await blockchain.treasury('master');
        inflationWallet = await blockchain.treasury('inflation');

        wallet = blockchain.openContract(
            AllodiumJettonWallet.createFromConfig(
                {
                    masterAddress: masterWallet.address,
                    ownerAddress: deployer.address,
                    inflationAddress: inflationWallet.address,
                },
                walletCode
            )
        );

        const deployResult = await wallet.sendDeploy(deployer.getSender(), toNano('0.05'));

        expect(deployResult.transactions).toHaveTransaction({
            from: deployer.address,
            to: wallet.address,
            deploy: true,
            success: true,
        });
    });

    it('should initialize wallet correctly', async () => {
        const data = await wallet.getWalletData();

        expect(data.balance).toBe(0n);
        expect(data.owner.equals(deployer.address)).toBeTruthy();
        expect(data.master.equals(masterWallet.address)).toBeTruthy();
    });

    it('should receive internal transfers correctly', async () => {
        const transferAmount = toNano('15');

        const internalTransfer = beginCell()
            .storeUint(0x178d4519, 32)
            .storeUint(1n, 64)
            .storeCoins(transferAmount)
            .storeAddress(masterWallet.address)
            .storeAddress(masterWallet.address)
            .storeCoins(0)
            .storeRef(beginCell().endCell())
            .endCell();

        await wallet.send(
            masterWallet.getSender(),
            { value: toNano('0.05') },
            internalTransfer
        );

        const dataAfter = await wallet.getWalletData();
        expect(dataAfter.balance).toBe(transferAmount);
    });

    it('should handle token burn correctly', async () => {
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

        await wallet.send(
            masterWallet.getSender(),
            { value: toNano('0.05') },
            tokenTransferInternalBody
        );

        await wallet.sendBurn(deployer.getSender(), burnAmount);

        const dataAfterBurn = await wallet.getWalletData();
        expect(dataAfterBurn.balance).toBe(initialAmount - burnAmount);
    });

    it('should correctly handle burn notification bounce', async () => {
        const burnNotificationBody = beginCell()
            .storeUint(0x7bdd97de, 32)
            .storeUint(3n, 64)
            .storeCoins(toNano('5'))
            .storeAddress(wallet.address)
            .storeAddress(deployer.address)
            .endCell();

        await wallet.send(
            deployer.getSender(),
            { value: toNano('0.05') },
            burnNotificationBody
        );

        const finalData = await wallet.getWalletData();
        expect(finalData.balance).toBe(0n);
    });
});
