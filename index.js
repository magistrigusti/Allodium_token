const TonWeb = require('tonweb');

// Правильное подключение HttpProvider в новой версии tonweb
const tonweb = new TonWeb(new TonWeb.HttpProvider('https://testnet.toncenter.com/api/v2/jsonRPC'));

// Функция для получения баланса аккаунта
async function getAccountBalance(addressStr) {
    try {
        const address = new TonWeb.utils.Address(addressStr);
        const account = await tonweb.provider.getBalance(address);
        console.log('Account Balance:', TonWeb.utils.fromNano(account), 'TON');
    } catch (error) {
        console.error('Error:', error);
    }
}

// Замени этот адрес на твой реальный адрес в TON Testnet
getAccountBalance('0QCRFHD0ndG_wVIN00H_lFVCl5Ce_perCRZU27F2idoAzoKz');
