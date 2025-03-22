import "@stdlib/deploy";
import "@stdlib/ownable";

// JettonData struct for get_jetton_data return
struct JettonData {
    totalSupply: Int;
    mintable: Bool;
    owner: Address;
    content: Cell;
    walletCode: Cell;
}

// Trait implementing Jetton master (TEP-89 and TEP-74 functionalities)
@interface("org.ton.jetton.master")
trait Jetton with Ownable {
    // Persistent state variables (to be provided by implementing contract)
    totalSupply: Int;
    mintable: Bool;
    owner: Address;
    content: Cell;
    max_supply: Int;

    // Allow owner to update token metadata content (standard TEP-64 behavior)
    receive(msg: TokenUpdateContent) {
        self.requireOwner();
        self.content = msg.content;
    }

    // Handle burn notifications from wallets: decrease total supply
    receive(msg: TokenBurnNotification) {
        self.requireWallet(msg.owner);
        self.totalSupply = self.totalSupply - msg.amount;
        if (msg.response_destination != null) {
            // Return excess gas (if any) to the specified address
            send(SendParameters{
                to: msg.response_destination!!,
                value: 0,
                bounce: false,
                mode: SendRemainingValue + SendIgnoreErrors,
                body: TokenExcesses{ queryId: msg.queryId }.toCell()
            });
        }
    }

    // Utility: ensure the sender is the valid wallet for the given owner
    fun requireWallet(owner: Address) {
        let ctx: Context = context();
        let expected: StateInit = self.getJettonWalletInit(owner);
        require(contractAddress(expected) == ctx.sender, "Invalid wallet sender");
    }

    // Get the StateInit (code and data) for a wallet for a given owner address
    virtual fun getJettonWalletInit(address: Address): StateInit {
        return initOf AllodiumJettonWallet(myAddress(), address);
    }

    // Read-only get method: return JettonData (total supply, owner, etc.)
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

    // Read-only get method: compute wallet address for a given owner address
    get fun get_wallet_address(owner: Address): Address {
        let winit: StateInit = self.getJettonWalletInit(owner);
        return contractAddress(winit);
    }
}

// Jetton Minter Contract for Allodium (ALOD)
contract AllodiumJettonMinter with Jetton {
    // State variables (inherited from Jetton trait and extended)
    totalSupply: Int as coins;
    mintable: Bool;
    owner: Address;
    content: Cell;
    max_supply: Int as coins;
    rewardAddress: Address;    // address where 25% of mining rewards go
    inflationAddress: Address; // address where inflationary tokens are sent
    lastInflationTime: Int as uint32;

    // Constant for decimal precision: 4 decimal places (1 token = 10^4 base units)
    const DECIMALS_FACTOR: Int = 10000;

    init(owner: Address, content: Cell, rewardAddress: Address, inflationAddress: Address) {
        self.totalSupply = 0;
        self.mintable = true;
        self.owner = owner;
        self.content = content;
        // Set maximum mineable supply = 600,000,000 * 10^4 (to account for 4 decimals)
        self.max_supply = 600_000_000 * DECIMALS_FACTOR;
        self.rewardAddress = rewardAddress;
        self.inflationAddress = inflationAddress;
        self.lastInflationTime = 0;
    }

    // Message to mint (mine) new tokens. Only owner (mining controller) can call.
    message Mine {
        amount: Int as coins;
        to: Address;
    }

    receive(msg: Mine) {
        self.requireOwner();                              // Only owner can trigger mining rewards
        require(self.mintable, "Minting is closed");      // Mining must be open
        // Ensure not exceeding max mineable supply
        require(self.totalSupply + msg.amount <= self.max_supply, "Max supply exceeded");
        // Split reward: 75% to recipient, 25% to reward pool
        let poolPart: Int = msg.amount / 4;          // 25% (floored if not divisible)
        let userPart: Int = msg.amount - poolPart;   // remaining 75%
        // Update total supply with the full amount
        self.totalSupply = self.totalSupply + msg.amount;
        // Gas requirements: ensure enough TON attached for two internal transfers
        let ctx: Context = context();
        require(ctx.value >= ton("0.02"), "Not enough TON for mining mint");
        // Prepare StateInit for reward pool wallet and user wallet
        let initPool: StateInit = self.getJettonWalletInit(self.rewardAddress);
        let poolWallet: Address = contractAddress(initPool);
        let initUser: StateInit = self.getJettonWalletInit(msg.to);
        let userWallet: Address = contractAddress(initUser);
        // Send tokens to reward pool (25% of reward)
        send(SendParameters{
            to: poolWallet,
            value: ton("0.01"),       // forward a small amount to cover storage
            bounce: false,
            mode: 0,
            body: TokenTransferInternal{
                queryId: 0,
                amount: poolPart,
                from: myAddress(),                // tokens minted from root
                response_destination: self.owner, // return any excess gas to owner
                forward_ton_amount: 0,
                forward_payload: emptySlice()
            }.toCell(),
            code: initPool.code,
            data: initPool.data
        });
        // Send tokens to user (75% of reward), forwarding all remaining value
        send(SendParameters{
            to: userWallet,
            value: 0,
            bounce: false,
            mode: SendRemainingValue,
            body: TokenTransferInternal{
                queryId: 0,
                amount: userPart,
                from: myAddress(),
                response_destination: self.owner,  // excess gas back to owner
                forward_ton_amount: 0,
                forward_payload: emptySlice()
            }.toCell(),
            code: initUser.code,
            data: initUser.data
        });
    }

    // Command to close mining (disable further minting). Only owner can call. 
    // Once called, inflation schedule begins.
    receive("CloseMinting") {
        self.requireOwner();
        require(self.mintable, "Minting already closed");
        self.mintable = false;
        // Set last inflation time to now, so next inflation occurs 180 days from this point
        self.lastInflationTime = now();
    }

    // Trigger the inflation mechanism after mining phase. Can be called by anyone when due.
    receive("DistributeInflation") {
        // Inflation only allowed after mining is finished
        require(!self.mintable, "Mining not yet ended");
        // 180 days period in seconds (approximately)
        const INFLATION_PERIOD: Int = 15552000;
        // Check that at least 180 days have passed since last inflation distribution
        require(now() >= self.lastInflationTime + INFLATION_PERIOD, "Too early for inflation");
        // Calculate 0.5% of current totalSupply (in base units)
        let increment: Int = self.totalSupply / 200;  // 0.5% = 1/200 (integer division)
        require(increment > 0, "No inflation increment");  // If 0 (very low supply), skip
        // Update last inflation timestamp to current time
        self.lastInflationTime = now();
        // Mint the inflationary tokens to the designated inflation address
        // Use caller as response destination to refund any excess gas
        let ctx: Context = context();
        self.mintJetton(self.inflationAddress, increment, ctx.sender);
    }

    // Internal function to mint jettons to a specified address (deploys or transfers to wallet)
    fun mintJetton(to: Address, amount: Int, response_destination: Address) {
        if (self.mintable) {
            // Enforce cap only during mining phase
            require(self.totalSupply + amount <= self.max_supply, "Max supply exceeded");
        }
        self.totalSupply = self.totalSupply + amount;
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

    // Override Jetton trait's wallet init function to use AllodiumJettonWallet contract
    override fun getJettonWalletInit(address: Address): StateInit {
        return initOf AllodiumJettonWallet(myAddress(), address);
    }

    // Override trait mint (not exposed externally) to use our mintJetton logic
    override fun mint(to: Address, amount: Int, response_destination: Address) {
        self.mintJetton(to, amount, response_destination);
    }
}

// Standard Jetton message and data definitions used by the contracts

// Internal transfer message (sent from Jetton Minter to Jetton Wallet or between wallets)
message(0x178d4519) TokenTransferInternal {
    queryId: Int as uint64;
    amount: Int as coins;
    from: Address;
    response_destination: Address;
    forward_ton_amount: Int as coins;
    forward_payload: Slice as remaining;
}

// Notification from Jetton Wallet to Jetton Minter when tokens are burned
message(0x7bdd97de) TokenBurnNotification {
    queryId: Int as uint64;
    amount: Int as coins;
    owner: Address;
    response_destination: Address?;
}

// Excess gas credit message (sent to return unused gas)
message(0xd53276db) TokenExcesses {
    queryId: Int as uint64;
}

// Message to update jetton content (metadata), only callable by owner
message TokenUpdateContent {
    content: Cell;
}
