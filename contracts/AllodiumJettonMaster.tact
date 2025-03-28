import "@stdlib/ownable";
import "@stdlib/deploy";
import "./messages";

const MONTHLY_INFLAION: Int = 416_666_666;

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
  wallet_code: Cell;
  inflation_wallet: Address;

  init(t) {

  }
  
  get fun get_jetton_data(): JettonData {
    return JettonData {
      totalSupply: self.total_mined,
      mintable: true,
      owner: self.owner,
      content: Cell;
      admin_address: self.owner,
      walletCode: self.wallet_code
    };
  }

}

