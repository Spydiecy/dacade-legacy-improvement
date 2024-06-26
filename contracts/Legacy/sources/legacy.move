/// Assets Legacy module is responsible for managing the Legacy
/// 
/// There are five main operations in this module:
/// 
/// 1. Users can create an legacy
/// 2. Users can deposit any token to legacy.
/// 3. Users can set heirs any time.
/// 4. Admin can distribute the legacy
/// 5. Users can withdraw the token from legacy if the legacy distributed
module legacy::assets_legacy {
    use sui::object::{Self, UID};
    use sui::table::{Self, Table};
    use sui::bag::{Self, Bag};
    use sui::transfer;
    use sui::tx_context::{TxContext, sender};
    use sui::coin::{Self, Coin, CoinMetadata};
    use sui::balance::{Self, Balance};
    use sui::sui::{SUI};
    use sui::clock::{Clock, timestamp_ms};

    use std::vector;
    use std::string::{Self, String};

    // =================== Errors ===================

    const ERROR_INVALID_ARRAY_LENGTH: u64 = 0;
    const ERROR_INVALID_PERCENTAGE_SUM: u64 = 1;
    const ERROR_YOU_ARE_NOT_HEIR: u64 =2;
    const ERROR_YOU_ARE_NOT_OWNER: u64 = 3;
    const ERROR_INVALID_TIME :u64 = 4;
    const ERROR_INVALID_REMAINING: u64 = 5; // New error for invalid remaining time

    // =================== Structs ===================

    /// We will keep the percentages and balances of Heirs here.
    /// 
    /// # Arguments
    /// 
    /// * `heirs_percentage` - admin will decide heirs percantage here. 
    /// * `heirs_amount` -  We keep the heirs Balance here like Table<address, <String, Balance<T>>>
    /// * `old_heirs` - We keep the heirs address in a vector for using in while loop.
    /// * `remaining` - The date the legacy will be made available for heirs
    struct Legacy has key {
        id: UID,
        owner: address,
        legacy: Bag,
        heirs_percentage: Table<address, u64>, 
        heirs_amount: Table<address, Bag>,    
        old_heirs: vector<address>,
        remaining: u64
    } 

    // =================== Functions ===================

    /// Users can create any legacy
    /// 
    /// # Arguments
    /// 
    /// * `remaining` - The date the legacy will be made available for heirs. 
    /// * `clock` -  The shareobject that we use for current time
    public fun new_legacy(remaining: u64, clock: &Clock, ctx: &mut TxContext) {
        // Validate the remaining time
        assert!(remaining >= 0 && remaining <= 1000, ERROR_INVALID_REMAINING);

        let remaining_ :u64 = ((remaining) * (86400 * 30)) + timestamp_ms(clock);
        // share object
        transfer::share_object(
            Legacy {
                id:object::new(ctx),
                owner: sender(ctx),
                legacy: bag::new(ctx),
                heirs_percentage:table::new(ctx),
                heirs_amount:table::new(ctx),
                old_heirs:vector::empty(),
                remaining: remaining_
            },
        );
    }

    /// Legacy owner's can deposit any token
    /// 
    /// # Arguments
    /// 
    /// * `legacy` - The share object that we keep funds, heirs names and percantages
    /// * `coin` -  The amount of token
    /// * `coin_metadata` - To get coin_name of token that We will keep tokens in hashmap as a <string, balance>.
    public fun deposit_legacy<T>(legacy: &mut Legacy, coin:Coin<T>, coin_metadata: &CoinMetadata<T>, ctx: &mut TxContext) {
        // check the legacy sender 
        assert!(sender(ctx) == legacy.owner, ERROR_YOU_ARE_NOT_OWNER);
        // get user bag 
        let bag_ = &mut legacy.legacy;
        // convert coin to the balance
        let balance = coin::into_balance(coin);
        // define the name of coin
        let name = coin::get_name(coin_metadata);
        // we should create a key value pair in our bag for first time.
        let coin_names = string::utf8(b"coins");
        // check if coin_names vector key value is not in bag create one time.
        if(!bag::contains(bag_, coin_names)) {
            bag::add<String, vector<String>>(bag_, coin_names, vector::empty());
        };

        // Optimize the coin existence check and balance update
        if let Some(coin_value) = bag::contains_and_borrow_mut(bag_, name) {
            balance::join(coin_value, balance);
        } else {
            bag::add(bag_, name, balance);
            let coins = bag::borrow_mut<String, vector<String>>(bag_, coin_names);
            vector::push_back(coins, name);
        }
    }

    /// Legacy owner's can set new heirs
    /// 
    /// # Arguments
    /// 
    /// * `legacy` - The share object that we keep funds, heirs names and percantages
    /// * `heir_address` -  The heir's addresses
    /// * `heir_percentage` - The heir's percentages
    public fun new_heirs(legacy: &mut Legacy, heir_address:vector<address>, heir_percentage:vector<u64>, ctx: &mut TxContext) {
        // check the shareobject owner
        assert!(legacy.owner == sender(ctx), ERROR_YOU_ARE_NOT_OWNER);
        // check input length > 0 and array lengths are equal
        assert!((vector::length(&heir_address) > 0 && 
        vector::length(&heir_address) == vector::length(&heir_percentage)), 
        ERROR_INVALID_ARRAY_LENGTH);
        // check percentange sum must be equal to 100 "
        let percentage_sum:u64 = 0;
        // remove the old heirs
        while(!vector::is_empty(&legacy.old_heirs)) {
            // Remove the old heirs from table. 
            let heir_address = vector::pop_back(&mut legacy.old_heirs);
            table::remove(&mut legacy.heirs_percentage, heir_address);
        };
         // add shareholders to table. 
        while(!vector::is_empty(&heir_address)) {
            let heir_address = vector::pop_back(&mut heir_address); 
            let heir_percentage = vector::pop_back(&mut heir_percentage);
            // add new heirs to old heirs vector. 
            vector::push_back(&mut legacy.old_heirs, heir_address);   
            // add table to new heirs and theirs percentange
            table::add(&mut legacy.heirs_percentage, heir_address , heir_percentage);
             // sum percentage
            percentage_sum = percentage_sum + heir_percentage;
        };
            // check percentage is equal to 100.
            assert!(percentage_sum == 10000, ERROR_INVALID_PERCENTAGE_SUM);
    }

    /// Admin can distribute the legacy
    /// 
    /// # Arguments
    /// 
    /// * `legacy` - The user legacy share object 
    /// * `clock` -  The shareobject that we use for current time
    public fun distribute<T>(
        legacy: &mut Legacy,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // check the remaining is more than 1 month
        assert!(timestamp_ms(clock) >= legacy.remaining, ERROR_INVALID_TIME);
        // Check the sender is heir and authorized to distribute
        assert!(vector::contains(&legacy.old_heirs, &sender(ctx)) && is_authorized_to_distribute(ctx), ERROR_YOU_ARE_NOT_HEIR);
        // get user bag from kiosk
        let bag_ = &mut legacy.legacy;
        // get the coin names
        let coin_names = string::utf8(b"coins);

        let coins = bag::borrow_mut<String, vector<String>>(bag_, coin_names);
        let heirs = legacy.old_heirs;

        // Check if the coins vector is non-empty before removing an element
        if !vector::is_empty(coins) {
            let coin_name = vector::remove(coins, 0);
            let heirs_length = vector::length(&legacy.old_heirs); 

            let j: u64 = 0;
            // set the total balance
            let total_balance = bag::borrow<String, Balance<T>>(bag_, coin_name);
            // define the total balance as u64
            let total_amount = balance::value(total_balance);

            while(j < heirs_length) {
                // take address from oldshareholder vector
                let heir_address = vector::borrow(&heirs, j);
                if (!table::contains(&legacy.heirs_amount, *heir_address)) {
                    let bag = bag::new(ctx);
                    table::add(&mut legacy.heirs_amount,*heir_address,bag);
                 };  
                // take heir percentage from table
                let heir_percentage = table::borrow(&legacy.heirs_percentage, *heir_address);
                // set the total balance
                let total_balance = bag::borrow_mut<String, Balance<T>>(bag_, coin_name);
                // calculate heir withdraw tokens
                let heir_legacy =  (total_amount * *heir_percentage ) / 10000;
                // calculate the distribute coin value to shareholder           
                let withdraw_coin = balance::split<T>( total_balance, heir_legacy);
                // get heir's bag from share object
                let heir_bag = table::borrow_mut<address, Bag>( &mut legacy.heirs_amount, *heir_address);
                // add heir's amount to table
                if(bag::contains(heir_bag, coin_name) == true) { 
                    let coin_value = bag::borrow_mut( heir_bag, coin_name);
                    balance::join(coin_value, withdraw_coin);
                }   else { 
                        bag::add(heir_bag, coin_name, withdraw_coin);
                     };
                j = j + 1;
            };       
        }
    }

    /// Heirs can withdraw any tokens from legacy
    /// 
    /// # Arguments
    /// 
    /// * `legacy` - The user legacy share object 
    /// * `coin_name` -  The distributed token's name 
    public fun withdraw<T>(legacy: &mut Legacy, coin_name: String, ctx: &mut TxContext) : Coin<T> {
        let sender = sender(ctx);
        // Check if the sender is an heir and authorized to withdraw
        assert!(table::contains(&legacy.heirs_amount, sender) && is_authorized_to_withdraw(ctx), ERROR_YOU_ARE_NOT_HEIR);
        // let take heir's bag from table 
        let bag_ = table::borrow_mut<address, Bag>(&mut legacy.heirs_amount, sender);
        // calculate withdraw balance 
        let balance_value = bag::remove<String, Balance<T>>( bag_, coin_name);
        // return the withdraw balance
        let coin_value = coin::from_balance(balance_value, ctx);
        coin_value
    }

    // =================== Public-View Functions===================

    // return the coin name from bag 
    public fun get_coin_name(legacy: &Legacy, index: u64) : String {
        let bag_ = &legacy.legacy;
        let coin_names = string::utf8(b"coins");
        let coin_vector = bag::borrow<String, vector<String>>(bag_, coin_names);
        let name = vector::borrow(coin_vector, index);
        *name
    }

    // return the total amount of tokens 
    public fun get_legacy_coin_amount<T>(legacy: &Legacy, coin: String) : u64 {
        let coin = bag::borrow<String, Balance<T>>(&legacy.legacy, coin);
        let amount = balance::value(coin);
        amount 
    }

    // return the heir's legacy token amount 
    public fun get_heir_coin_amount<T>(legacy: &Legacy, coin: String, heir: address) : u64 {
        let bag_ = &legacy.legacy;
        let heir_bag = table::borrow<address, Bag>(&legacy.heirs_amount, heir);
        let coin = bag::borrow<String, Balance<T>>(heir_bag, coin);
        balance::value(coin)
    }

    // =================== Helper Functions ===================

    // Check if the caller is authorized to distribute the legacy
    fun is_authorized_to_distribute(ctx: &TxContext): bool {
        // Add your authorization logic here
        true // Replace with the actual authorization check
    }

    // Check if the caller is authorized to withdraw from the legacy
    fun is_authorized_to_withdraw(ctx: &TxContext): bool {
        // Add your authorization logic here
        true // Replace with the actual authorization check
    }

    // =================== TEST ONLY ===================

    #[test_only]
    // We can't reach the sui coinmetadata so we will test the sui token in local test.
    public fun deposit_legacy_sui(legacy: &mut Legacy, coin:Coin<SUI>) {
        // get user bag from kiosk
        let bag_ = &mut legacy.legacy;
        // lets define balance
        let balance = coin::into_balance(coin);
        // set the sui as a string
        let name = string::utf8(b"sui");
        // we should create a key value pair in our bag for first time.
        let coin_names = string::utf8(b"coins");
        // check if coin_names vector key value is not in bag create one time.
        if(!bag::contains(bag_, coin_names)) {
            bag::add<String, vector<String>>(bag_, coin_names, vector::empty());
        };
        // lets check is there any sui token in bag
        if(bag::contains(bag_, name)) { 
            let coin_value = bag::borrow_mut(bag_, name);
             // if there is a sui token in our bag we will sum it.
             balance::join(coin_value, balance);
        }
        else { 
            // add fund into the bag 
            bag::add(bag_, name, balance);
            let coins = bag::borrow_mut<String, vector<String>>(bag_, coin_names);
            // Add coins name into the vector
            vector::push_back(coins, name);
        }
    }

    #[test_only]
    public fun test_get_heir_balance<T>(legacy: &Legacy, heir: address, coin: String) : u64 {
        let bag_ = table::borrow<address, Bag>(&legacy.heirs_amount, heir);
        let coin = bag::borrow<String, Balance<T>>(bag_, coin);
        let amount = balance::value(coin);
        amount
    }

    #[test_only]
    public fun test_get_remaining(legacy: &Legacy) : u64 {
        legacy.remaining
    }
}
