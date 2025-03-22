// Импортируем трейты для работы с Jetton и правами владельца
import "@stdlib/ownable";

// Структура с данными токена, возвращаемая через get_jetton_data
struct JettonData {
    totalSupply: Int;
    mintable: Bool;
    owner: Address;
    content: Cell;
    walletCode: Cell;
}

// Интерфейс токена по стандарту Jetton (TEP-89)
@interface("org.ton.jetton.master")
trait Jetton with Ownable {
    totalSupply: Int;
    mintable: Bool;
    owner: Address;
    content: Cell;
    max_supply: Int;

    // Позволяет владельцу обновить контент токена (метаданные)
    receive(msg: TokenUpdateContent) {
        self.requireOwner(); // Проверяем, что это владелец
        self.content = msg.content;
    }

    // Обработка уведомления о сжигании токенов от кошельков
    receive(msg: TokenBurnNotification) {
        self.requireWallet(msg.owner); // Проверяем, что сжигает владелец кошелька
        self.totalSupply -= msg.amount;

        // Возврат лишнего газа (если указан response_destination)
        if (msg.response_destination != null) {
            send(SendParameters{
                to: msg.response_destination!!,
                value: 0,
                bounce: false,
                mode: SendRemainingValue + SendIgnoreErrors,
                body: TokenExcesses{ queryId: msg.queryId }.toCell()
            });
        }
    }

    // Проверка: правильный ли JettonWallet прислал сообщение
    fun requireWallet(owner: Address) {
        let ctx: Context = context();
        let expected: StateInit = self.getJettonWalletInit(owner);
        require(contractAddress(expected) == ctx.sender, "Invalid wallet sender");
    }

    // Получение StateInit кошелька для адреса владельца
    virtual fun getJettonWalletInit(address: Address): StateInit {
        return initOf AllodiumJettonWallet(myAddress(), address);
    }

    // Метод просмотра: возвращает общую информацию о токене
    get fun get_jetton_data(): JettonData {
        let code: Cell = self.getJettonWalletInit(myAddress()).code;
        return JettonData{
            totalSupply: self.totalSupply,
            mintable: self.mintable,
            owner: self.owner,
            content: self.content,
            walletCode: code
        };
    }

    // Метод просмотра: возвращает адрес JettonWallet по адресу владельца
    get fun get_wallet_address(owner: Address): Address {
        let winit: StateInit = self.getJettonWalletInit(owner);
        return contractAddress(winit);
    }
}

// ✅ Основной контракт Allodium Jetton
contract AllodiumJettonMinter with Jetton {
    totalSupply: Int as coins;         // Текущее общее количество токенов
    mintable: Bool;                    // Можно ли ещё майнить (true/false)
    owner: Address;                    // Владелец контракта
    content: Cell;                     // Метаданные токена
    max_supply: Int as coins;          // Лимит токенов (600 млн ALOD)
    rewardAddress: Address;            // Кошелёк, куда идут 25% майнинга
    inflationAddress: Address;         // Кошелёк для инфляции
    lastInflationTime: Int as uint32;  // Последнее начисление инфляции

    const DECIMALS_FACTOR: Int = 10000; // 4 знака после запятой
    const INFLATION_PERIOD: Int = 15552000; // 180 дней в секундах (6 мес)

    // Инициализация контракта
    init(owner: Address, content: Cell, rewardAddress: Address, inflationAddress: Address) {
        self.totalSupply = 0;
        self.mintable = true;
        self.owner = owner;
        self.content = content;
        self.max_supply = 600_000_000 * DECIMALS_FACTOR;
        self.rewardAddress = rewardAddress;
        self.inflationAddress = inflationAddress;
        self.lastInflationTime = 0;
    }

    // Структура входящего сообщения для майнинга
    message Mine {
        amount: Int as coins;   // Сколько токенов заминтить
        to: Address;            // Кому отправить награду
    }

    // Обработка сообщения Mine (награда за майнинг)
    receive(msg: Mine) {
        self.requireOwner();
        require(self.mintable, "Minting is closed");
        require(self.totalSupply + msg.amount <= self.max_supply, "Max supply exceeded");

        // Разделяем награду: 75% пользователю, 25% в пул
        let poolPart: Int = msg.amount / 4;
        let userPart: Int = msg.amount - poolPart;

        self.totalSupply += msg.amount;

        // Отправляем 25% в пул
        let initPool: StateInit = self.getJettonWalletInit(self.rewardAddress);
        let poolWallet: Address = contractAddress(initPool);

        send(SendParameters{
            to: poolWallet,
            value: ton("0.01"),
            bounce: false,
            mode: 0,
            body: TokenTransferInternal{
                queryId: 0,
                amount: poolPart,
                from: myAddress(),
                response_destination: self.owner,
                forward_ton_amount: 0,
                forward_payload: emptySlice()
            }.toCell(),
            code: initPool.code,
            data: initPool.data
        });

        // Отправляем 75% пользователю
        let initUser: StateInit = self.getJettonWalletInit(msg.to);
        let userWallet: Address = contractAddress(initUser);

        send(SendParameters{
            to: userWallet,
            value: 0,
            bounce: false,
            mode: SendRemainingValue,
            body: TokenTransferInternal{
                queryId: 0,
                amount: userPart,
                from: myAddress(),
                response_destination: self.owner,
                forward_ton_amount: 0,
                forward_payload: emptySlice()
            }.toCell(),
            code: initUser.code,
            data: initUser.data
        });
    }

    // Закрываем фазу майнинга (запускаем инфляцию)
    receive("CloseMinting") {
        self.requireOwner();
        require(self.mintable, "Already closed");
        self.mintable = false;
        self.lastInflationTime = now(); // Запоминаем время
    }

    // Инфляционное начисление 0.5% (разрешено после закрытия майнинга)
    receive("DistributeInflation") {
        require(!self.mintable, "Minting not closed");
        require(now() >= self.lastInflationTime + INFLATION_PERIOD, "Too early");

        let increment: Int = self.totalSupply / 200; // 0.5%
        require(increment > 0, "Nothing to mint");

        self.lastInflationTime = now();

        // Минтим инфляционные токены на inflationAddress
        self.mintJetton(self.inflationAddress, increment, context().sender);
    }

    // Минтим токены (внутренняя функция)
    fun mintJetton(to: Address, amount: Int, response_destination: Address) {
        if (self.mintable) {
            require(self.totalSupply + amount <= self.max_supply, "Mint limit exceeded");
        }

        self.totalSupply += amount;

        let winit: StateInit = self.getJettonWalletInit(to);

        send(SendParameters{
            to: contractAddress(winit),
            value: 0,
            bounce: false,
            mode: SendRemainingValue,
            body: TokenTransferInternal{
                queryId: 0,
                amount: amount,
                from: myAddress(),
                response_destination: response_destination,
                forward_ton_amount: 0,
                forward_payload: emptySlice()
            }.toCell(),
            code: winit.code,
            data: winit.data
        });
    }

    // Переопределяем генерацию JettonWallet
    override fun getJettonWalletInit(address: Address): StateInit {
        return initOf AllodiumJettonWallet(myAddress(), address);
    }

    // Обёртка над mintJetton (если захочешь использовать вручную)
    override fun mint(to: Address, amount: Int, response_destination: Address) {
        self.mintJetton(to, amount, response_destination);
    }
}
