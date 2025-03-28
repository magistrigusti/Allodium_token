import "@stdlib/ownable";
import "@stdlib/deploy";
import "./messages";
import "./constants";
import "./AllodiumJettonWallet";

const MIN_TONS_FOR_STORAGE: Int = ton("0.01");
const GAS_CONSUMPTION: Int = ton("0.005");

struct WalletData {
    balance: Int;
    owner: Address;
    master: Address;
    burn: Address;
    inflation: Address;
    jeton_content: Cell;
    wallet_code: Cell;
}

contract AllodiumJettonWallet with Ownable, Deployable {
    balance: Int;
    owner: Address;
    master: Address;
    burn: Address;
    inflation: Address;
    jetton_content: Cell;

    
    init(master: Address,  args: Slice) {
        self.owner = owner;
        self.burn = burn;
        self.inflation = inflation;

        self.master = master;
        self.balance = 0;
        self.content = content;
    }

    receive(msg: Transfer) {
        let ctx: Context = context();
        require(ctx.sender == self.owner, "Invalid sender");

        let burnAmount = msg.amount / 10000;               // 0.01%
        let transferAmount = msg.amount - burnAmount;

        self.balance = self.balance - msg.amount;
        require(self.balance >= 0, "Invalid balance");

        let fwdFeeDest = ctx.readForwardFee();
        let fwdFeeReturn = ctx.readForwardFee();
        let finalFee = 2 * GAS_CONSUMPTION + MIN_TONS_FOR_STORAGE + fwdFeeDest + fwdFeeReturn;
        require(ctx.value > min(finalFee, ton("0.015")), "Invalid value");

        let args = beginCell().storeRef(beginCell()
            .storeAddress(msg.destination)
            .storeAddress(self.burn)
            .storeAddress(self.inflation)
            .endCell()
        ).endCell();

        let initDest = initOf AllodiumJettonWallet(self.master, args.asSlice());
        let destWallet = contractAddress(initDest);

        if (burnAmount > 0) {
            send(SendParameters{
                to: self.burn,
                value: ton("0.01"),
                bounce: false,
                mode:0,
                body: BurnNotification{
                    query_id: msg.query_id,
                    amount: burnAmount,
                    sender: self.owner,
                    response_destination: self.owner
                }.toCell()
            });
        }

        // Отправка оставшегося количества (после сжигания)
        send(SendParameters{
            to: destWallet,
            value: 0,
            bounce: false,
            mode: SendRemainingValue,
            body: TransferInternal{
                query_id: msg.query_id,
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

    receive(msg: TransferInternal) {
        let ctx = context();

        if (ctx.sender != self.master) {
            let args = beginCell().storeRef(beginCell()
                .storeAddress(msg.from)
                .storeAddress(self.burn)
                .storeAddress(self.inflation)
                .endCell()
            ).endCell();

            let initSender = initOf AllodiumJettonWallet(self.master, args.asSlice());


            require(contractAddress(initSender) == ctx.sender, "Invalid sender");
        }

        self.balance = self.balance + msg.amount;
        require(self.balance >= 0, "Invalid balance");

        if (msg.forward_ton_amount > 0) {
            send(SendParameters{
                to: self.owner,
                value: msg.forward_ton_amount,
                mode: SendPayGasSeparately + SendIgnoreErrors,
                bounce: false,
                body: TransferNotification{
                    query_id: msg.query_id,
                    amount: msg.amount,
                    sender: msg.from,
                    forward_payload: msg.forward_payload
                }.toCell()
            });
        }

        if (msg.response_destination != null) {
            let msgValue = ctx.value;
            let tonBefore = myBalance() - msgValue;
            let storageFee = MIN_TONS_FOR_STORAGE - min(tonBefore, MIN_TONS_FOR_STORAGE);
            msgValue = msgValue - (storageFee + GAS_CONSUMPTION);
            msgValue = msgValue - msg.forward_ton_amount - ctx.readForwardFee();

            send(SendParameters{
                to: msg.response_destination!!,
                value: msgValue,
                bounce: false,
                body: Excesses{ query_id: msg.query_id }.toCell(),
                mode: SendIgnoreErrors
            });
        }
    }

    receive(msg: ChangeContent) {
        self.requireOwner();
        self.content = msg.jetton_content;
    }

    bounced(msg: bounced<TransferInternal>) {
        self.balance = self.balance + msg.amount;
    }

    bounced(src: bounced<BurnNotification>) {
        self.balance = self.balance + msg.amount;
    }

    get fun get_wallet_data(): WalletData {
        return WalletData{
        balance: self.balance,
        owner: self.owner,
        master: self.master,
        walletCode: (initOf AllodiumJettonWallet(
            self.master,
            beginCell().storeRef(beginCell()
                .storeAddress(self.owner)
                .storeAddress(self.burn)
                .storeAddress(self.inflation)
                .endCell()
            ).endCell().asSlice()
        )).code
        };
    }

}
