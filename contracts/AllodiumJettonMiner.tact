import "@stdlib/ownable";
import "@stdlib/deploy";
import "./messages";
import "./constants";

struct JettonData {
    totalSupply: Int;
    mintable: Bool;
    owner: Address;
    content: Cell;
    walletCode: Cell;
}

@interface("org.ton.jetton.master")
trait Jetton with Ownable {
    totalSupply: Int;
    mintable: Bool;
    owner: Address;
    content: Cell;
    max_supply: Int;

    receive(msg: TokenUpdateContent) {
        self.requireOwner(); 
        self.content = msg.content;
    }
 
    receive(msg: TokenBurnNotification) {
        self.requireWallet(msg.owner); 
        self.totalSupply -= msg.amount;

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

    fun requireWallet(owner: Address) {
        let ctx: Context = context();
        let expected: StateInit = self.getJettonWalletInit(owner);
        require(contractAddress(expected) == ctx.sender, "Invalid wallet sender");
    }

    virtual fun getJettonWalletInit(address: Address): StateInit {
        return initOf AllodiumJettonWallet(myAddress(), address);
    }

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

    get fun get_wallet_address(owner: Address): Address {
        let winit: StateInit = self.getJettonWalletInit(owner);
        return contractAddress(winit);
    }
}

contract AllodiumJettonMinter with Jetton {
    nftRegistry: Address;
    totalSupply: Int as coins;         
    mintable: Bool;                    
    owner: Address;                    
    content: Cell;                    
    max_supply: Int as coins;          
    rewardAddress: Address;           
    inflationAddress: Address;         
    lastInflationTime: Int as uint32;  
    
    init(owner: Address, content: Cell, rewardAddress: Address, inflationAddress: Address, nftRegistry: Address) {
        self.totalSupply = 0;
        self.mintable = true;
        self.owner = owner;
        self.content = content;
        self.max_supply = 600_000_000 * DECIMALS_FACTOR;
        self.rewardAddress = rewardAddress;
        self.inflationAddress = inflationAddress;
        self.lastInflationTime = 0;
        self.nftRegistry = nftRegistry;
    }


    
    receive(msg: Mine) {
        self.requireOwner();
        require(self.mintable, "Minting is closed");
        require(self.totalSupply + msg.amount <= self.max_supply, "Max supply exceeded");

        
        let poolPart: Int = msg.amount / 4;
        let userPart: Int = msg.amount - poolPart;

        self.totalSupply += msg.amount;

        
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

    receive("CloseMinting") {
        self.requireOwner();
        require(self.mintable, "Already closed");
        self.mintable = false;
        self.lastInflationTime = now(); 
    }

    receive("DistributeInflation") {
        require(!self.mintable, "Minting not closed");
        require(now() >= self.lastInflationTime + INFLATION_PERIOD, "Too early");

        let increment: Int = self.totalSupply / 200; // 0.5%
        require(increment > 0, "Nothing to mint");

        self.lastInflationTime = now();

        
        self.mintJetton(self.inflationAddress, increment, context().sender);
    }

    receive(msg: Inflation) {
        require(self.lastInflationTime > 0, "Minting has not started");
        require(now() >= self.lastInflationTime + INFLATION_PERIOD, "Too early");


        let increment: Int = self.totalSupply / 200;
        require(increment > 0, "Nothing to mint");

        self.lastInflationTime = now();
        self.mintJetton(msg.from, msg.amount, msg.to);
    }

    fun getNftBonus(owner: Address): Int {
    // Вызываем внешний контракт (например, NFT Registry), который возвращает лучший бонус
        let bonus: Int = call(self.nftRegistry, "getBonusFor", owner);
        return bonus;
    }   
    
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
    
    override fun getJettonWalletInit(address: Address): StateInit {
        return initOf AllodiumJettonWallet(myAddress(), address);
    }

    override fun mint(to: Address, amount: Int, response_destination: Address) {
        self.mintJetton(to, amount, response_destination);
    }
}
