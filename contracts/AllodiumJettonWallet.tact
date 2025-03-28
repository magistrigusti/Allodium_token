// Обновлённая версия контракта AllodiumJettonWallet с учётом предложенных исправлений и комментариев

import "@stdlib/ownable";
import "@stdlib/deploy";
import "./messages";
import "./constants";
import "./AllodiumJettonMaster";

const MIN_TONS_FOR_STORAGE: Int = ton("0.1");
const GAS_CONSUMPTION: Int = ton("0.01");

struct WalletData {
    balance: Int;
    owner: Address;
    master: Address;
    burn: Address;
    inflation: Address;
    jeton_content: Cell;
    wallet_code: Cell;
}

contract AllodiumJettonWallet with Ownable, Deployable, JettonAllodium {
    balance: Int;
    owner: Address;
    master: Address;
    burn: Address;
    inflation: Address;
    jeton_content: Cell;

    init(master: Address, args: Slice) {
        self.owner = args.loadAddress();         // загружаем адрес владельца из аргументов
        self.burn = args.loadAddress();          // загружаем адрес для сжигания
        self.inflation = args.loadAddress();     // загружаем адрес инфляции

        self.master = master;
        self.balance = 0;
        self.content = Cell.empty();             // инициализируем контент пустой ячейкой (можно позже заменить на конкретный)
    }

    receive(msg: Transfer) {
        let ctx: Context = context();            // используем тип Context
        require(ctx.sender == self.owner, "Invalid sender");

        let burnAmount = msg.amount / 10000;     // 0.01% от суммы
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

        send(SendParameters {
            to: self.burn,
            value: GAS_CONSUMPTION,
            bounce: false,
            mode: 0,
            body: BurnNotification {
                query_id: msg.query_id,
                amount: burnAmount,
                sender: self.owner,
                response_destination: self.owner
            }.toCell()
        });

        // отправка оставшегося количества (после сжигания)
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
        let ctx: Context = context();

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

    receive(msg: TokenBurn) {
        let ctx: Context = context();
        require(ctx.sender == self.owner, "Only owner can burn");
        require(msg.amount > 0, "Amount must be > 0");
        require(self.balance >= msg.amount, "Not enough balance");
        self.balance -= msg.amount;

        send(SendParameters {
            to: self.burn,
            value: GAS_CONSUMPTION,
            bounce: false,
            mode: 0,
            body: TokenBurn {
                query_id: msg.query_id,
                amount: msg.amount,
                sender: self.owner,
                response_destination: self.owner,
                custom_payload: msg.custom_payload
            }.toCell()
        });
    }

    receive(msg: Inflation) {
        require(msg.to == myAddress(), "Invalid recipient address");
        require(msg.amount > 0, "Amount must be positive");
        self.balance += msg.amount;
    }

    bounced(msg: bounced<TransferInternal>) {
        self.balance = self.balance + msg.amount;
    }

    bounced(src: bounced<BurnNotification>) {
        self.balance = self.balance + msg.amount;
    }

    get fun get_wallet_data(): WalletData {
        let winit = initOf AllodiumJettonWallet(
            self.master,
            beginCell().storeRef(beginCell()
                .storeAddress(self.owner)
                .storeAddress(self.burn)
                .storeAddress(self.inflation)
                .endCell()
            ).endCell().asSlice()
        );

        return WalletData{
            balance: self.balance,
            owner: self.owner,
            master: self.master,
            burn: self.burn,
            inflation: self.inflation,
            jeton_content: self.content,
            wallet_code: winit.code
        };
    }
}
