module orafi::main {

use sui::balance;
use sui::coin::{Self, Coin};

const ADMIN_PUBLIC_KEY: address =
    @0x997043ec15507d6f1d52c5b5396fcc9f8b0db67495dedc7d6b5927f24271f7f1;

// Fee percentage (0.5% = 50 basis points out of 10000)
const FEE_BASIS_POINTS: u64 = 100;
const BASIS_POINTS_DIVISOR: u64 = 10000;

// Error codes
const E_INSUFFICIENT_BALANCE: u64 = 1;
const E_BALANCE_MISMATCH: u64 = 3;

public struct Wallet<phantom T> has key, store {
    id: UID,
    merchant: address,
    amount: u64,
}

// Generate a payment wallet for a merchant
public fun generatePaymentWallet<T: copy + drop>(merchantWalletAddress: address, amount: u64, ctx: &mut TxContext) {
    let wallet: Wallet<T> = Wallet {
        id: object::new(ctx),
        merchant: merchantWalletAddress,
        amount,
    };
 

    transfer::share_object(wallet);
}

// Receive payment, extract fees, and send remainder to merchant
public fun pay<T: copy + drop>(coin: Coin<T>, wallet: Wallet<T>, ctx: &mut TxContext) {
    let Wallet { id, merchant, amount } = wallet;
    assert!(coin.value() == amount, E_BALANCE_MISMATCH);
    let fee_amount = (amount * FEE_BASIS_POINTS) / BASIS_POINTS_DIVISOR;

    let mut coin_balance = coin::into_balance(coin);

    // Split the balance
    let fee_balance = balance::split(&mut coin_balance, fee_amount);

    // Send fee to admin
    let fee_coin = coin::from_balance(fee_balance, ctx);
    transfer::public_transfer(fee_coin, ADMIN_PUBLIC_KEY);

    // Send remainder to merchant
    let merchant_coin = coin::from_balance(coin_balance, ctx);
    transfer::public_transfer(merchant_coin, merchant);
 
    // Clean up empty wallet balance and delete
    object::delete(id);
}


    #[allow(lint(self_transfer))]
    public fun withdraw_to_merchant(
        mut coin_obj: coin::Coin<USDC>,
        amount: u64,
        destination: address,
        ctx: &mut TxContext
    ) {

    assert!(coin_obj.value() >= amount, E_INSUFFICIENT_BALANCE); // E_INSUFFICIENT_BALANCE
    let withdraw_coin = coin_obj.split(amount, ctx);
    transfer::public_transfer(withdraw_coin, destination);
    transfer::public_transfer(coin_obj, ctx.sender())
}

    public fun merge_all_usdc(
        primary: &mut coin::Coin<USDC>,
        mut others: vector<coin::Coin<USDC>>,
    ) {
        let len = vector::length(&others);
        let mut i = 0;
        while (i < len) {
            let c = vector::pop_back(&mut others);
            coin::join(primary, c);
            i = i + 1;
        };
        others.destroy_empty();
    }
}
