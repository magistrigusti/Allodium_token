import { CompilerConfig } from '@ton/blueprint';

export const compile: CompilerConfig = {
    lang: 'tact',
    target: 'contracts/AllodiumJettonMaster.tact',
    options: {
        debug: true,
    },
};
