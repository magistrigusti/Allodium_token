import { Blockchain, SandboxContract, TreasuryContract } from '@ton/sandbox';
import { toNano } from '@ton/core';
import { AllodiumJettonWallet } from '../wrappers/AllodiumJettonWallet';
import { AllodiumJettonMiner } from '../wrappers/AllodiumJettonMiner';
import '@ton/test-utils';

describe('AllodiumJettonWallet', () => {
    let blockchain: Blockchain;
    let deployer: SandboxContract<TreasuryContract>;
    let masterWallet: SandboxContract<TreasuryContract>;
    let userWallet: SandboxContract<AllodiumJettonWallet>;
    let inflation: SandboxContract<AllodiumJettonMiner>;

    beforeEach(async () => {
        blockchain = await Blockchain.create();

        deployer = await blockchain.treasury('deployer');
        masterWallet = await blockchain.treasury('master');
        inflation = await blockchain.treasury('inflation');

        userWallet = blockchain.openContract(
            await AllodiumJettonWallet.fromInit(
                masterWallet.address,
                deployer.address,
                inflation.address
            )
        );

        const deployResult = await userWallet.send(
            deployer.getSender(),
            { value: toNano('0.05')},
            {
                $$type: 'Deploy',
                queryId: 0n,
            }
        );

        expect(deployResult.transaction).toHaveTransaction({
            from: deployer.address,
            to: userWallet.address,
            deploy: true,
            success: true
        });
    });


    it('should correctly initialize wallet data', async () => {
        const data = await userWallet.getWalletData();

        expect(data.balance.toNumber()).toBe(0);
        expect(data.owner.equals(deployer.address)).toBeTruthy();
        expect(data.master.equals(masterWallet.address)).toBeTruthy();
    });

    it('should correctly process internal token transfer', async () => {
        const transferAmount = toNano('10');

        await userWallet.sendInternalMessage({
            from: masterWallet.address,
            value: toNano('0.05'),
            body: {
                $$type: 'TokenTransferInternal',
                query_id: 1n,
                amount: transferAmount,
                from: masterWallet.address,
                response_destination: masterWallet.address,
                forward_ton_amount: 0n,
                forward_payload: Buffer.alloc(0)
            }
        });

        const dataAfterTransfer = await userWallet.getWalletData();
        expect(dataAfterTransfer.balance.toString()).toBe(transferAmount.toString());
    });

    it('should burn tokens correctly', async () => {
        const initialAmount = toNano('20');
        const burnAmount = toNano('5');

        await userWallet.sendInternalMessage({
            from: masterWallet.address,
            value: toNano('0.05'),
            body: {
                $$type: "TokenTransferinternal",
                query_id: 2n,
                amount: initialAmount,
                from: masterWallet.address,
                response_estination: masterWallet.address,
                forward_ton_amount: 0n,
                forward_payoad: Buffer.alloc(0)
            }
        });

        await userWallet.send(
            deployer.getSender(),
            { value: toNano('0.05')},
            {
                $$type: 'Burn',
                query_id: 3n,
                amount: burnAmount,
                response_destination: deployer.address,
                custom_payload: null,
            }
        );

        const dataAfterBurn = await userWallet.getWalletData();
        expect(dataAfterBurn.balance.toString()).toBe(toNano('15').toString());
    });

});