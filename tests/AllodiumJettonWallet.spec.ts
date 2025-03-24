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
    });

});