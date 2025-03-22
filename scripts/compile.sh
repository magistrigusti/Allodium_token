#!/bin/bash

echo "🔧 Компиляция смарт-контрактов..."
tact compile contracts/AllodiumJettonMinter.tact
tact compile contracts/AllodiumJettonWallet.tact
echo "✅ Готово!"
