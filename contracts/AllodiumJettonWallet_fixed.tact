import "@stdlib/deploy";
@interface("org.ton.jetton.wallet")
contract AllodiumJettonWallet {
    const minTonsForStorage: Int = ton("0.01");
    const gasConsumption: Int = ton("0.01");

    balance: Int;
    owner: Address;
    master: Address;

    init(master: Address, owner: Address) {
        self.balance = 0;
        self.owner = owner;
        self.master = master;
    }

    receive(msg: TokenTransfer) {
        let ctx: Context = context();
        require(ctx.sender == self.owner, "Invalid sender");

        let burnAmount: Int = msg.amount / 10000;         // 0.01%
        let transferAmount: Int = msg.amount - burnAmount;

        self.balance -= msg.amount;
        require(self.balance >= 0, "Invalid balance");

        let fwdFeeDest: Int = ctx.readForwardFee();
        let fwdFeeBurn: Int = ctx.readForwardFee();
        let finalFee: Int = 2 * self.gasConsumption + self.minTonsForStorage + fwdFeeDest + fwdFeeBurn;
        require(ctx.value > min(finalFee, ton("0.015")), "Invalid value");

        let initDest: StateInit = initOf AllodiumJettonWallet(self.master, msg.destination);
        let destWallet: Address = contractAddress(initDest);

        if (burnAmount > 0) {
            send(SendParameters{
                to: self.master,
                value: 0,
                bounce: true,
                mode: 0,
                body: TokenBurnNotification{
                    queryId: msg.queryId,
                    amount: burnAmount,
                    owner: self.owner,
                    response_destination: self.owner
                }.toCell()
            });
        }

        send(SendParameters{
            to: destWallet,
            value: 0,
            bounce: false,
            mode: SendRemainingValue,
            body: TokenTransferInternal{
                queryId: msg.queryId,
                amount: transferAmount,
                from: self.owner,
                response_destination: msg.response_destination,
                forward_ton_amount: msg.forward_ton_amount,
                forward_payload: msg.forward_payload
            }.toCell(),
            code: initDest.code,
            data: initDest.data
        });
    }

    receive(msg: TokenTransferInternal) {
        let ctx: Context = context();
        if (ctx.sender != self.master) {
            let initSender: StateInit = initOf AllodiumJettonWallet(self.master, msg.from);
            require(contractAddress(initSender) == ctx.sender, "Invalid sender");
        }

        self.balance += msg.amount;
        require(self.balance >= 0, "Invalid balance");

        if (msg.forward_ton_amount > 0) {
            send(SendParameters{
                to: self.owner,
                value: msg.forward_ton_amount,
                mode: SendPayGasSeparately + SendIgnoreErrors,
                bounce: false,
                body: TokenNotification{
                    queryId: msg.queryId,
                    amount: msg.amount,
                    from: msg.from,
                    forward_payload: msg.forward_payload
                }.toCell()
            });
        }

        if (maybe(msg.response_destination)) {
            let msgValue: Int = ctx.value;
            let tonBefore: Int = myBalance() - msgValue;
            let storageFee: Int = self.minTonsForStorage - min(tonBefore, self.minTonsForStorage);
            msgValue = msgValue - (storageFee + self.gasConsumption);
            msgValue = msgValue - msg.forward_ton_amount - ctx.readForwardFee();

            send(SendParameters{
                to: msg.response_destination!!,
                value: msgValue,
                bounce: false,
                body: TokenExcesses{ queryId: msg.queryId }.toCell(),
                mode: SendIgnoreErrors
            });
        }
    }

    receive(msg: TokenBurn) {
        let ctx: Context = context();
        require(ctx.sender == self.owner, "Invalid sender");

        self.balance -= msg.amount;
        require(self.balance >= 0, "Invalid balance");

        let fwdFee: Int = ctx.readForwardFee();
        require(ctx.value > (fwdFee + 2 * self.gasConsumption + self.minTonsForStorage), "Invalid value - Burn");

        send(SendParameters{
            to: self.master,
            value: 0,
            bounce: true,
            mode: SendRemainingValue,
            body: TokenBurnNotification{
                queryId: msg.queryId,
                amount: msg.amount,
                owner: self.owner,
                response_destination: self.owner
            }.toCell()
        });
    }

    bounced(msg: bounced<TokenTransferInternal>) {
        self.balance += msg.amount;
    }

    bounced(msg: bounced<TokenBurnNotification>) {
        self.balance += msg.amount;
    }

    get fun get_wallet_data(): JettonWalletData {
        return JettonWalletData{
            balance: self.balance,
            owner: self.owner,
            master: self.master,
            walletCode: (initOf AllodiumJettonWallet(self.master, self.owner)).code
        };
    }
}
