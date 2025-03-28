import "@stdlib/ownable";
import "@stdlib/deploy";
import "./messages";

const MONTHLY_INFLAION: Int = 416_666_666;
const MAX_MINEABLE: Int = 500_000_000n * 10000n;

struct JettonData {
    totalSupply: Int;
    mintable: Bool;
    owner: Address;
    inflation: Address;
    content: Cell;
    walletCode: Cell;
}

trait JettonAllodium with Ownable {
  totalSupply: Int;
  mintable: Bool;
  owner: Address;
  inflation: Address;
  content: Cell;
  maxSupply: Int;

  receive(msg: ChangeContent) {
    self.requireOwner();
    self.content = msg.content;
  }

  receive(msg: BurnNotification) {
    self.requireWallet(msg.sender);
    self.totalSupply -= msg.amount;

    send(SendParameters{
      to: msg.response_destination,
      value: 0,
      bounce: false,
      mode: SendRemainingValue + SendIgnoreErrors,
      body: Excesses{query_id: msg.query_id}.toCell()
    });
  }

  fun requireWallet(owner: Address) {
    let ctx = context();
    let expected = self.getJettonWalletInit(owner);
    require(contractAddress(expected) == ctx.sender, "Invalid wallet sender");
  }

  virtual fun getJettonWalletInit(address: Address): StateInit {
    return initOf AllodimJettonWallet(myAddress(), address, self.inflation);
  }

  get fun get_jetton_data(): JettonData {
    let code = self.getJettonWalletInit(myAddress()).code;

    return JettonData {
      totalSupply: self.totalSupply,
      mintable: self.mintable,
      owner: self.owner,
      inflation: self.inflation,
      content: self.content,
      walletCode: code,
    };
  }

  get fun et_wallet_address(owner: Address): Address {
    return contractAddress(self.getJettonWalletInit(owner));
  }

}


contract AllodiumJettonMaster with Deployable, Ownable,  {
  total_mined: Int;
  walletCode: Cell;
  inflation: Address;
  last_inflation: Int;

  init(owner: Address, walletCode: Cell, iflation: Address) {
    self.owner = owner;
    self.walletCode = walletCode;
    self.inflation = inflation;
    self.total_mined = 0;
    self.last_inflation = now();
  }
  
  get fun get_jetton_data(): JettonData {
    return JettonData {
      totalSupply: self.total_mined,
      mintable: true,
      owner: self.owner,
      content: Cell.empty(),
      walletCode: self.walletCode
    };
  }

}

