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
    let burnWallet: SandboxContract<TreasuryContract>;

    beforeAll(async () => {
        walletCode = await compile('AllodiumJettonWallet');
    });

    beforeEach(async () => {
        blockchain = await Blockchain.create();

        deployer = await blockchain.treasury('deployer');
        masterWallet = await blockchain.treasury('master');
        inflationWallet = await blockchain.treasury('inflation');
        burnWallet = await blockchain.treasury('burn');

        wallet = blockchain.openContract(
            AllodiumJettonWallet.createFromConfig(
                {
                    masterAddress: masterWallet.address,
                    ownerAddress: deployer.address,
                    burnAddress: burnWallet.address,
                    inflationAddress: inflationWallet.address,
                },
                walletCode
            )
        );

        const deployResult = await wallet.sendDeploy(deployer.getSender(), toNano('0.2'));
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

        await deployer.getSender().send({
            to: wallet.address,
            value: toNano('0.05'),
            body: internalTransfer,
        });

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

        await masterWallet.getSender().send({
            to: wallet.address,
            value: toNano('0.05'),
            body: tokenTransferInternalBody,
        });

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

        await deployer.getSender().send({
            to: wallet.address,
            value: toNano('0.05'),
            body: burnNotificationBody,
        });

        const finalData = await wallet.getWalletData();
        expect(finalData.balance).toBe(0n);
    });

    it('should burn 0.01% and send BurnNotification', async () => {
        const transferAmount = toNano('0.01');
        const expectedBurn = transferAmount / 10000n;
        const destination = await blockchain.treasury('recipient');

        const transferBody = beginCell()
            .storeUint(0xf8a7ea5, 32)
            .storeUint(123n, 64)
            .storeCoins(transferAmount)
            .storeAddress(destination.address)
            .storeAddress(null)
            .storeCoins(0)
            .storeRef(beginCell().endCell())
            .endCell();

        const result = await wallet.sendTransfer(deployer.getSender(), {
            amount: toNano("0.01"),
            destination: destination.address,
            forwardTonAmount: toNano("0.002"),
            forwardPayload: beginCell().endCell(),
        });

        expect(result.transactions).toHaveTransaction({
            from: wallet.address,
            to: burnWallet.address,
            success: true,
            body: (cell) => {
                if (!cell) return false;
                const slice = cell.beginParse();
                const op = slice.loadUint(32);
                slice.loadUint(64);
                const amount = slice.loadCoins();
                return op === 0x595f07bc && amount === expectedBurn;
            }
        });
        

        const data = await wallet.getWalletData();
        expect(data.balance).toBe(0n);
    });
});
