@echo off
echo 🔧 Компиляция смарт-контрактов...
npx tact compile contracts/AllodiumJettonMinter.tact
npx tact compile contracts/AllodiumJettonWallet.tact
echo ✅ Готово!
pause
