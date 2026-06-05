module orafi::main {

    use sui::balance;
    use sui::coin::{Self, Coin};
    use sui::clock::Clock;
    use sui::event;
    use deepbook::pool::{Self, Pool};
    use deepbook::deep::DEEP;
    use usdc::usdc::USDC;

    // Hardcoded administrative address for fee collection
    const ADMIN_ADDRESS: address = @0x997043ec15507d6f1d52c5b5396fcc9f8b0db67495dedc7d6b5927f24271f7f1;

    // Fee percentage (1.00% = 100 basis points out of 10000)
    const FEE_BASIS_POINTS: u64 = 100; 
    const BASIS_POINTS_DIVISOR: u64 = 10000;

    // Error codes
    const E_INSUFFICIENT_BALANCE: u64 = 1;
    const E_BALANCE_MISMATCH: u64 = 3;

    // --- Events ---

    public struct WalletCreated has copy, drop {
        wallet_id: ID,
        merchant: address,
        amount: u64,
        transaction_id: u64,
    }

    public struct PaymentProcessed has copy, drop {
        wallet_id: ID,
        merchant: address,
        input_amount: u64,
        usdc_distributed: u64,
        fee_collected: u64,
    }

    // --- Storage Structures ---

    public struct Wallet<phantom T> has key, store {
        id: UID,
        merchant: address,
        amount: u64,
        transaction_id: u64, // Added transaction identifier
    }

    /// Generate a payment wallet for a merchant and emit creation event
    public fun generatePaymentWallet<T>(
        merchantWalletAddress: address, 
        amount: u64, 
        transaction_id: u64, 
        ctx: &mut TxContext
    ) {
        let id = object::new(ctx);
        let wallet_id = object::uid_to_inner(&id);

        let wallet = Wallet<T> {
            id,
            merchant: merchantWalletAddress,
            amount,
            transaction_id,
        };

        // Emit creation metadata for indexing off-chain
        event::emit(WalletCreated {
            wallet_id,
            merchant: merchantWalletAddress,
            amount,
            transaction_id,
        });

        transfer::share_object(wallet);
    }

    /// Path 1: T is NOT USDC — swap first via DeepBook, then distribute
    public fun pay_swap<T>(
        coin: Coin<T>,
        wallet: Wallet<T>,
        pool: &mut Pool<T, USDC>,
        deep_fee: Coin<DEEP>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let Wallet { id, merchant, amount, transaction_id: _ } = wallet;
        assert!(coin.value() == amount, E_BALANCE_MISMATCH);

        // Swap T -> USDC
        let (_, usdc_out, deep_remainder) = pool::swap_exact_quantity(
            pool,
            coin,
            coin::zero<USDC>(ctx),
            deep_fee,
            0,
            clock,
            ctx,
        );

        if (deep_remainder.value() > 0) {
            transfer::public_transfer(deep_remainder, ctx.sender());
        } else {
            deep_remainder.destroy_zero();
        };

        _distribute_usdc(usdc_out, merchant, amount, id, ctx);
    }

    /// Path 2: T is already USDC — skip swap entirely
    public fun pay_usdc(
        coin: Coin<USDC>,
        wallet: Wallet<USDC>,
        ctx: &mut TxContext
    ) {
        let Wallet { id, merchant, amount, transaction_id: _ } = wallet;
        assert!(coin.value() == amount, E_BALANCE_MISMATCH);

        _distribute_usdc(coin, merchant, amount, id, ctx);
    }

    /// Shared internal logic — split fee, send to admin + merchant, and emit event
    fun _distribute_usdc(
        usdc: Coin<USDC>,
        merchant: address,
        input_amount: u64,
        wallet_id: UID,
        ctx: &mut TxContext
    ) {
        let usdc_amount = usdc.value();
        let fee_amount = (usdc_amount * FEE_BASIS_POINTS) / BASIS_POINTS_DIVISOR;
        let merchant_amount = usdc_amount - fee_amount;

        let mut usdc_balance = coin::into_balance(usdc);
        let fee_balance = balance::split(&mut usdc_balance, fee_amount);

        // Emit settlement event before destroying wallet ID
        event::emit(PaymentProcessed {
            wallet_id: object::uid_to_inner(&wallet_id),
            merchant,
            input_amount,
            usdc_distributed: merchant_amount,
            fee_collected: fee_amount,
        });

        transfer::public_transfer(coin::from_balance(fee_balance, ctx), ADMIN_ADDRESS);
        transfer::public_transfer(coin::from_balance(usdc_balance, ctx), merchant);

        object::delete(wallet_id);
    }

    /// Public withdrawal facility for specific merchant distribution rules
    public fun withdraw_to_merchant(
        mut coin_obj: Coin<USDC>,
        amount: u64,
        destination: address,
        ctx: &mut TxContext
    ) {
        assert!(coin_obj.value() >= amount, E_INSUFFICIENT_BALANCE);

        let fee_amount = (amount * FEE_BASIS_POINTS) / BASIS_POINTS_DIVISOR;
        let mut withdraw_coin = coin_obj.split(amount, ctx);
        let fee_coin = withdraw_coin.split(fee_amount, ctx);

        transfer::public_transfer(fee_coin, ADMIN_ADDRESS);
        transfer::public_transfer(withdraw_coin, destination);
        
        if (coin_obj.value() > 0) {
            transfer::public_transfer(coin_obj, ctx.sender());
        } else {
            coin_obj.destroy_zero();
        };
    }

    /// Combines multiple incoming USDC coin objects into a base primary coin object
    public fun merge_all_usdc(
        primary: &mut Coin<USDC>,
        mut others: vector<Coin<USDC>>,
    ) {
        while (!others.is_empty()) {
            let c = others.pop_back();
            primary.join(c);
        };
        others.destroy_empty();
    }
}