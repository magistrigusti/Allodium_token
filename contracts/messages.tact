

message(0xd8cfdaf1) Inflation {
    query_id: Int as uint64;
    amount: Int as coins;
    from: Address;
    to: Address;
}

message(0x595f07bc) JettonBurn {
    queryId: Int as uint64;
    amount: Int as coins;
    responseDestination: Address?;
    customPayload: Cell? = null;
}

message(0xf8a7ea5) JettonTransfer {
    queryId: Int as uint64;
    amount: Int as coins;
    destination: Address;
    responseDestination: Address?;
    customPayload: Cell? = null;
    forwardTonAmount: Int as coins;
    forwardPayload: Slice as remaining;
}

message(0x178d4519) TransferInternal {
    query_id: Int as uint64;
    amount: Int as coins;
    from: Address;
    responseDestination: Address?;
    customPayload: Cell? = null;
    forwardTonAmount: Int as coins;
    forwardPayload: Slice as remaining;
}

message(0x7362d09c) JettonTransferNotification {
    queryId: Int as uint64;
    amount: Int as coins;
    sender: Address;
    forwardPayload: Slice as remaining;
}

message(0xd53276db) Excesses {
    query_id: Int as uint64;
}

//mine contract
message(0x262f9a08) Mine {
    query_id: Int as uint64;
    amount: Int as coins;   
    to: Address;            
}

message(0xd2a7f71e) CloseMinting {
    query_id: Int as uint64;
}

//master contract

message(0x7bdd97de) BurnNotification {
    queryId: Int as uint64;
    amount: Int as coins;
    sender: Address;
    forwardPayload: Slice as remaining;
}

message ChangeContent {
    query_id: Int as uint64;
    jettonContent: Cell;
    walletCode: Cell;
}

message(0x2c76b973) ProvideWalletAddress {
    query_id: Int as uint64;
    owner_address: Address;
    include_address: Bool;
}
message(0xd1735400) TakeWalletAddress {
    query_id: Int as uint64;
    wallet_address: Address;
    owner_address: Address?;
}