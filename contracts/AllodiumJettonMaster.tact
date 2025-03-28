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

contract AllodiumJettonMaster with Deployable, Ownable {
  total_mined: Int;
  wallet_code: Cell;
  inflation_wallet: Address;

  init(t)
}

