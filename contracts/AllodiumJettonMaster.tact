import "@stdlib/ownable";
import "@stdlib/deploy";
import "./messages";

const MONTHLY_INFLAION: Int = 416_666_666;
const MAX_MINEABLE: Int = 500_000_000n * 10000n;

struct InternalMint {
  query_id: Int;
  receiver: Address;
  amount: Int;
  value: Int;
  burn: Address;
}

struct TriggerInflation {
  query_id: Int;
  value: Int;
}

struct JettonData {
    totalSupply: Int;
    mintable: Bool;
    owner: Address;
    content: Cell;
    walletCode: Cell;
}


contract AllodiumJettonMaster with Deployable, Ownable {
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

  receive(msg: Mine) {
    require(msg.amount > 0, "zero-amount");
    let new_total = self.total_mined + msg.amount;
    require(new_total <= MAX_MINEABLE, "max-mint-limit");
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

