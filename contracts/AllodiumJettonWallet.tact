import "@stdlib/ownable";
import "@stdlib/deploy";
import "./messages";
import "./constants";

const minTonsForStorage: Int = ton("0.01");
const gasConsumption: Int = ton("0.005");

struct WalletData {
    balance: Int;
    owner: Address;
    master: Address;
    walletCode: Cell;
}

contract AllodiumJettonWallet with Ownable, Deployable {
    balance: Int;
    owner: Address;
    master: Address;
    inflation: Address;
    

    init(master: Address, owner: Address, inflation: Address) {
        self.balance = 0;
        self.owner = owner;
        self.master = master;
        self.inflation = inflation;

    }

    receive(msg: TokenTransfer) {
        let ctx: Context = context();
        require(ctx.sender == self.owner, "Invalid sender");

        let burnAmount: Int = msg.amount / 10000;         // 0.01% of transfer
        let transferAmount: Int = msg.amount - burnAmount;

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

    receive(msg: TokenTransferInternal) { 
        let ctx: Context = context();

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

    receive(msg: ChangeContent) {
        self.requireOwner(); 
        self.content = msg.jettonContent;
    }

    bounced(msg: bounced<TokenTransferInternal>) {
        self.balance = self.balance + msg.amount;
    }

    bounced(msg: bounced<BurnNotification>) {
        self.balance += msg.amount;
    }

    get fun get_wallet_data(): WalletData {
        return WalletData{
            balance: self.balance,
            owner: self.owner,
            master: self.master,
            walletCode: (initOf AllodiumJettonWallet(self.master, self.owner)).code
        };
    }

}

