#[test_only]
module orafi::ora_test;

use orafi::main::{Wallet, generatePaymentWallet, pay};
use sui::coin::{Self, Coin};
use sui::test_scenario as ts;
use usdc::usdc::USDC;

const MERCHANT_ADDRESS: address = @0xA;
const BOB: address = @0xB;

#[test]
fun test_wallet_creation_and_payment_verification() {
    let mut scenario = ts::begin(MERCHANT_ADDRESS);

    //Create Payment Wallet
    {
        let ctx = ts::ctx(&mut scenario);
        generatePaymentWallet(MERCHANT_ADDRESS, ctx);
    };

    //Initialise payment
    ts::next_tx(&mut scenario, BOB);
    {
        let wallet = ts::take_shared<Wallet>(&scenario);
        let ctx = ts::ctx(&mut scenario);
        let test_usdc_coin: coin::Coin<USDC> = coin::mint_for_testing<USDC>(200, ctx);

        pay(test_usdc_coin, wallet, ctx);
    };

    //Verify Merchant payment
    ts::next_tx(&mut scenario, MERCHANT_ADDRESS);
    {
        let coin_balance = ts::take_from_sender<Coin<USDC>>(&scenario);

        let amount = coin::value(&coin_balance);

        assert!(amount == 198, 0);

        ts::return_to_sender<Coin<USDC>>(&scenario, coin_balance);
    };

    ts::end(scenario);
}
