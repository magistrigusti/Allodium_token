import "@stdlib/deploy";
@interface("org.ton.jetton.wallet")
contract AllodiumJettonWallet {
    // Constants for minimum storage rent and gas consumption fees
    const minTonsForStorage: Int = ton("0.01");
    const gasConsumption: Int = ton("0.01");

    // State variables
    balance: Int;
    owner: Address;
    master: Address;

    init(master: Address, owner: Address) {
        self.balance = 0;
        self.owner = owner;
        self.master = master;
    }

    // Handle direct transfer from the owner of this wallet
    receive(msg: TokenTransfer) {
        let ctx: Context = context();
        require(ctx.sender == self.owner, "Invalid sender");

        // Calculate burn commission of 0.01% and the amount to transfer out
        let burnAmount: Int = msg.amount / 10000;         // 0.01% of transfer
        let transferAmount: Int = msg.amount - burnAmount;

        // Deduct the full amount (including the portion to burn) from this wallet's balance
        self.balance = self.balance - msg.amount;
        require(self.balance >= 0, "Invalid balance");

        // Gas and fees check: ensure enough TON was attached to cover forwarding messages
        let fwdFeeDest: Int = ctx.readForwardFee();
        let fwdFeeBurn: Int = ctx.readForwardFee();
        let finalFee: Int = 2 * self.gasConsumption + self.minTonsForStorage + fwdFeeDest + fwdFeeBurn;
        require(ctx.value > min(finalFee, ton("0.015")), "Invalid value");

        // Prepare the recipient's wallet (it may be deployed if not existing)
        let initDest: StateInit = initOf AllodiumJettonWallet(self.master, msg.destination);
        let destWallet: Address = contractAddress(initDest);

        // 1. Send burn notification for the burned amount to the jetton master
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

        // 2. Send the remaining tokens to the destination wallet (forward remaining TON)
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

    // Handle incoming internal jetton transfer from another wallet or the minter
    receive(msg: TokenTransferInternal) {
        let ctx: Context = context();
        // Verify sender: must be the jetton master or another AllodiumJettonWallet
        if (ctx.sender != self.master) {
            let initSender: StateInit = initOf AllodiumJettonWallet(self.master, msg.from);
            require(contractAddress(initSender) == ctx.sender, "Invalid sender");
        }
        // Increase balance by incoming amount
        self.balance = self.balance + msg.amount;
        require(self.balance >= 0, "Invalid balance");

        // If there's a forward payload and TON to forward to the wallet owner
        if (msg.forward_ton_amount > 0) {
            // Send a notification to this wallet's owner with the forwarded TON and payload
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
        // Return any remaining TON (excess gas) back to the original sender if requested
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

}


    // Handle a burn request from the owner (user-initiated token burn)
    receive(msg: TokenBurn) {
        let ctx: Context = context();
        require(ctx.sender == self.owner, "Invalid sender");
        self.balance = self.balance - msg.amount;
        require(self.balance >= 0, "Invalid balance");
        let fwdFee: Int = ctx.readForwardFee();
        require(ctx.value > fwdFee + 2 * self.gasConsumption + self.minTonsForStorage, "Invalid value - Burn");
        // Send a burn notification to the jetton master to update total supply
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

    // Bounce handler: if any internal message fails and returns TON, credit it back to this wallet
    bounced(msg: bounced<TokenTransferInternal>) {
        self.balance = self.balance + src.amount;
    }

    bounced(msg: bounced<TokenBurnNotification>) {
        self.balance += msg.amount;
    }

    // Read-only get method: returns the data of this wallet (balance and addresses)
    get fun get_wallet_data(): JettonWalletData {
        return JettonWalletData{
            balance: self.balance,
            owner: self.owner,
            master: self.master,
            walletCode: (initOf AllodiumJettonWallet(self.master, self.owner)).code
        };
    }
}

// Supporting data structures and message definitions for the Jetton wallet

struct JettonWalletData {
    balance: Int;
    owner: Address;
    master: Address;
    walletCode: Cell;
}

// External transfer message (from user to their wallet)
message(0xf8a7ea5) TokenTransfer {
    queryId: Int as uint64;
    amount: Int as coins;
    destination: Address;
    response_destination: Address;
    custom_payload: Cell?;
    forward_ton_amount: Int as coins;
    forward_payload: Slice as remaining;
}

// Internal transfer message (from one wallet or minter to another wallet)
message(0x178d4519) TokenTransferInternal {
    queryId: Int as uint64;
    amount: Int as coins;
    from: Address;
    response_destination: Address;
    forward_ton_amount: Int as coins;
    forward_payload: Slice as remaining;
}

// Notification to wallet owner about incoming transfer (with forwarded payload)
message(0x7362d09c) TokenNotification {
    queryId: Int as uint64;
    amount: Int as coins;
    from: Address;
    forward_payload: Slice as remaining;
}

// Burn message (from user to their wallet to burn tokens)
message(0x595f07bc) TokenBurn {
    queryId: Int as uint64;
    amount: Int as coins;
    owner: Address;
    response_destination: Address;
}

// Burn notification (from wallet to master after burning tokens)
message(0x7bdd97de) TokenBurnNotification {
    queryId: Int as uint64;
    amount: Int as coins;
    owner: Address;
    response_destination: Address?;
}

// Excess gas credit message (return unused TON to sender)
message(0xd53276db) TokenExcesses {
    queryId: Int as uint64;
}
