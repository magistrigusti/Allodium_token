import { toNano, Cell } from '@ton/core';
import { NetworkProvider } from '@ton/blueprint';
import { AllodiumJettonMiner } from '../wrappers/AllodiumJettonMiner';

export async function run(provider: NetworkProvider) {
    const sender = provider.sender(); // тот, кто деплоит
    const owner = sender.address;


    const content = new Cell(); // сюда можно вставить jetton metadata (URI, JSON и т.д.)
    const rewardAddress = owner;
    const inflationAddress = owner;
    const nftRegistry = owner;


    const minter = provider.open(
        AllodiumJettonMiner.createFromConfig(
            {
                owner,
                content,
                rewardAddress,
                inflationAddress,
                nftRegistry
            },
            await provider.compile('AllodiumJettonMinter')
        )
    );


    await minter.sendDeploy(sender, toNano('0.05'));

    console.log('✅ AllodiumJettonMinter deployed at:', minter.address.toString());
}
