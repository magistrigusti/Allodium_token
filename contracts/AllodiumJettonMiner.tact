import "@stdlib/ownable";
import "@stdlib/deploy";
import "./messages";
import "./constants";
import "./AllodiumJettonWallet"; // на случай initOf

struct JettonData {
    totalSupply: Int;
    mintable: Bool;
    owner: Address;
    inflation: Address;
    content: Cell;
    walletCode: Cell;
}

contract AllodiumJettonMinter with Jetton {
    nftRegistry: Address;
    totalSupply: Int;         
    mintable: Bool;                    
    owner: Address;                    
    content: Cell;                    
    max_supply: Int;          
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

        let poolPart = msg.amount / 4;
        let userPart = msg.amount - poolPart;

        self.totalSupply += msg.amount;

        let poolWallet = contractAddress(self.getJettonWalletInit(self.rewardAddress));
        let userWallet = contractAddress(self.getJettonWalletInit(msg.to));

        send(SendParameters{
            to: poolWallet,
            value: ton("0.01"),
            bounce: false,
            mode: 0,
            body: TransferInternal{
                query_id: 0,
                amount: poolPart,
                from: myAddress(),
                response_destination: self.owner,
                forward_ton_amount: 0,
                forward_payload: emptySlice(),
            }.toCell(),
            code: self.getJettonWalletInit(self.rewardAddress).code,
            data: self.getJettonWalletInit(self.rewardAddress).data
        });

        send(SendParameters{
            to: userWallet,
            value: 0,
            bounce: false,
            mode: SendRemainingValue,
            body: TransferInternal{
                query_id: 0,
                amount: userPart,
                from: myAddress(),
                response_destination: self.owner,
                forward_ton_amount: 0,
                forward_payload: emptySlice(),
            }.toCell(),
            code: self.getJettonWalletInit(msg.to).code,
            data: self.getJettonWalletInit(msg.to).data
        });
    }

    receive(msg: CloseMinting) {
        self.requireOwner();
        require(self.mintable, "Already closed");
        self.mintable = false;
        self.lastInflationTime = now();
    }


    // fun getNftBonus(owner: Address): Int {
    //     return call(self.nftRegistry, "getBonusFor", owner);
    // }

    fun mintJetton(to: Address, amount: Int, response_destination: Address) {
        if (self.mintable) {
            require(self.totalSupply + amount <= self.max_supply, "Mint limit exceeded");
        }

        self.totalSupply += amount;

        let winit = self.getJettonWalletInit(to);

        send(SendParameters{
            to: contractAddress(winit),
            value: 0,
            bounce: false,
            mode: SendRemainingValue,
            body: TransferInternal{
                query_id: 0,
                amount: amount,
                from: myAddress(),
                response_destination: response_destination,
                forward_ton_amount: 0,
                forward_payload: emptySlice(),
            }.toCell(),
            code: winit.code,
            data: winit.data
        });
    }

    override fun getJettonWalletInit(address: Address): StateInit {
        return initOf AllodiumJettonWallet(myAddress(), address, self.inflationAddress);
    }

    fun mint(to: Address, amount: Int, response_destination: Address) {
        self.mintJetton(to, amount, response_destination);
    }
}
