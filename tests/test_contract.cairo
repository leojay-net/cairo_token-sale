use starknet::{ContractAddress, contract_address_const, ClassHash};

use snforge_std::{declare, ContractClassTrait, DeclareResultTrait, start_cheat_caller_address, stop_cheat_caller_address, spy_events, EventSpyAssertionsTrait, get_class_hash};

use token_sale::interfaces::itoken_sale::{ITokenSaleDispatcher, ITokenSaleDispatcherTrait};
use token_sale::interfaces::ierc20::{IERC20Dispatcher, IERC20DispatcherTrait};


fn deploy_contract(name: ByteArray, args: Array::<felt252>) -> ContractAddress {
    let contract = declare(name).unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@args).unwrap();
    contract_address
}

fn deploy_token_contract(name: ByteArray, symbol: ByteArray) -> ContractAddress {
    let mut erc20_args = array![];
    name.serialize(ref erc20_args);
    symbol.serialize(ref erc20_args);
    return deploy_contract("MockERC20", erc20_args);
}

fn deploy_token_sale(owner: ContractAddress, payment_token: ContractAddress) -> ContractAddress {
    let token_sale_args = array![owner.into(), payment_token.into()];
    deploy_contract("TokenSaleContract", token_sale_args)
}

// UNIT TESTS

#[test]
fn test_constructor() {

    let token_contract_address = deploy_token_contract("Payment Token", "PT");

    let owner: ContractAddress = contract_address_const::<'owner'>();
    let token_sale_contract_address = deploy_token_sale(owner, token_contract_address);
    let token_sale_contract_address_felt: felt252 = token_sale_contract_address.into();

    let dispatcher = ITokenSaleDispatcher { contract_address: token_sale_contract_address };
    assert(dispatcher.get_owner() == owner, 'Not Owner');

}

#[test]
fn test_check_available_token() {
    let owner = contract_address_const::<'owner'>();
    let payment_token = deploy_token_contract("Payment Token", "PT");
    let test_token = deploy_token_contract("TestToken", "TT");
    
    let token_sale_address = deploy_token_sale(owner, payment_token);
    let dispatcher = ITokenSaleDispatcher { contract_address: token_sale_address };
    
    let balance = dispatcher.check_available_token(test_token);
    assert!(balance == 0, "Initial balance should be 0");
}

#[test]
fn test_deposit_token_only_owner() {
    let owner = contract_address_const::<'owner'>();
    let payment_token = deploy_token_contract("PaymentToken", "PT");
    let test_token = deploy_token_contract("TestToken", "TT");
    
    let token_sale_address = deploy_token_sale(owner, payment_token);
    let dispatcher = ITokenSaleDispatcher { contract_address: token_sale_address };


    let balance_before = dispatcher.check_available_token(payment_token);
    assert!(balance_before == 0, "Invalid Balance Before");

    let payment_dispatcher = IERC20Dispatcher { contract_address: payment_token };
    start_cheat_caller_address(payment_token, owner);
    payment_dispatcher.mint(owner, 1000);

    payment_dispatcher.approve(token_sale_address, 1000);
    stop_cheat_caller_address(payment_token);
    
    start_cheat_caller_address(token_sale_address, owner);

    dispatcher.deposit_token(test_token, 100, 50);
    let balance_after = dispatcher.check_available_token(payment_token);

    assert!(balance_after > balance_before, "Invalid Balance After");
    assert!(balance_after == 100, "Invalid Mint Operation");
    stop_cheat_caller_address(token_sale_address);
    
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_deposit_token_non_owner_fails() {
    let owner = contract_address_const::<'owner'>();
    let non_owner = contract_address_const::<'non_owner'>();
    let payment_token = deploy_token_contract("PaymentToken", "PT");
    let test_token = deploy_token_contract("TestToken", "TT");
    
    let token_sale_address = deploy_token_sale(owner, payment_token);
    let dispatcher = ITokenSaleDispatcher { contract_address: token_sale_address };
    
    start_cheat_caller_address(token_sale_address, non_owner);
    dispatcher.deposit_token(test_token, 100, 50);
    stop_cheat_caller_address(token_sale_address);
}

#[test]
#[should_panic(expected: ('insufficient balance',))]
fn test_deposit_token_insufficient_balance() {
    let owner = contract_address_const::<'owner'>();
    let payment_token = deploy_token_contract("PaymentToken", "PT");
    let test_token = deploy_token_contract("TestToken", "TT");
    
    let token_sale_address = deploy_token_sale(owner, payment_token);
    let dispatcher = ITokenSaleDispatcher { contract_address: token_sale_address };

    start_cheat_caller_address(token_sale_address, owner);
    dispatcher.deposit_token(test_token, 100, 50);
}

#[test]
fn test_upgrade_only_owner() {
    let owner = contract_address_const::<'owner'>();
    let payment_token = deploy_token_contract("PaymentToken", "PT");
    
    let token_sale_address = deploy_token_sale(owner, payment_token);
    let dispatcher = ITokenSaleDispatcher { contract_address: token_sale_address };

    let original_class_hash = get_class_hash(token_sale_address);
    
    let new_contract = declare("MockERC20").unwrap().contract_class();
    let new_class_hash = new_contract.class_hash;

    assert!(*new_class_hash != original_class_hash, "Not Different");

    start_cheat_caller_address(token_sale_address, owner);
    dispatcher.upgrade(*new_class_hash);
    stop_cheat_caller_address(token_sale_address);

    assert!(get_class_hash(token_sale_address) == *new_class_hash, "Upgrade Failed");
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_upgrade_non_owner_fails() {
    let owner = contract_address_const::<'owner'>();
    let non_owner = contract_address_const::<'non_owner'>();
    let payment_token = deploy_token_contract("PaymentToken", "PT");
    
    let token_sale_address = deploy_token_sale(owner, payment_token);
    let dispatcher = ITokenSaleDispatcher { contract_address: token_sale_address };

    let original_class_hash = get_class_hash(token_sale_address);
    
    let new_contract = declare("MockERC20").unwrap().contract_class();
    let new_class_hash = new_contract.class_hash;

    assert!(*new_class_hash != original_class_hash, "Not Different");

    start_cheat_caller_address(token_sale_address, non_owner);
    dispatcher.upgrade(*new_class_hash);
    stop_cheat_caller_address(token_sale_address);

    assert!(get_class_hash(token_sale_address) == *new_class_hash, "Upgrade Failed");
}

// INTEGRATION TESTS

#[test]
fn test_full_token_sale_flow() {
    let owner = contract_address_const::<'owner'>();
    let buyer = contract_address_const::<'buyer'>();
    let payment_token = deploy_token_contract("PaymentToken", "PT");
    let sale_token = deploy_token_contract("SaleToken", "ST");
    
    let token_sale_address = deploy_token_sale(owner, payment_token);
    let dispatcher = ITokenSaleDispatcher { contract_address: token_sale_address };
    
    let payment_dispatcher = IERC20Dispatcher { contract_address: payment_token };
    let sale_dispatcher = IERC20Dispatcher { contract_address: sale_token };
    
    start_cheat_caller_address(payment_token, owner);
    payment_dispatcher.mint(owner, 1000);
   payment_dispatcher.approve(token_sale_address, 500);
    stop_cheat_caller_address(payment_token);
    
    start_cheat_caller_address(sale_token, owner);
    sale_dispatcher.mint(token_sale_address, 500);
    stop_cheat_caller_address(sale_token);
    
    start_cheat_caller_address(token_sale_address, owner);
    dispatcher.deposit_token(sale_token, 500, 100); 
    stop_cheat_caller_address(token_sale_address);
    
    let available = dispatcher.check_available_token(sale_token);
    assert!(available == 500, "Should have 500 tokens available");
    
    start_cheat_caller_address(payment_token, buyer);
    payment_dispatcher.mint(buyer, 200);
    payment_dispatcher.approve(token_sale_address, 100);
    stop_cheat_caller_address(payment_token);
    
    start_cheat_caller_address(token_sale_address, buyer);
    dispatcher.buy_token(sale_token, 500);
    stop_cheat_caller_address(token_sale_address);
    
    let buyer_balance = sale_dispatcher.balance_of(buyer);
    assert!(buyer_balance == 500, "Buyer should have 500 tokens");
    
    let buyer_payment_balance = payment_dispatcher.balance_of(buyer);
    assert!(buyer_payment_balance == 100, "Buyer should have 100 payment tokens left");
}

#[test]
#[should_panic]
fn test_buy_token_wrong_amount_fails() {
    let owner = contract_address_const::<'owner'>();
    let buyer = contract_address_const::<'buyer'>();
    let payment_token = deploy_token_contract("PaymentToken", "PT");
    let sale_token = deploy_token_contract("SaleToken", "ST");
    
    let token_sale_address = deploy_token_sale(owner, payment_token);
    let dispatcher = ITokenSaleDispatcher { contract_address: token_sale_address };

    let payment_dispatcher = IERC20Dispatcher { contract_address: payment_token };
    start_cheat_caller_address(payment_token, owner);
    payment_dispatcher.mint(owner, 1000);
    payment_dispatcher.approve(token_sale_address, 1000);
    stop_cheat_caller_address(payment_token);
    
    let sale_dispatcher = IERC20Dispatcher { contract_address: sale_token };
    start_cheat_caller_address(sale_token, owner);
    sale_dispatcher.mint(token_sale_address, 100);
    stop_cheat_caller_address(sale_token);
    
    start_cheat_caller_address(token_sale_address, owner);
    dispatcher.deposit_token(sale_token, 100, 50);
    stop_cheat_caller_address(token_sale_address);
    
    start_cheat_caller_address(token_sale_address, buyer);
    dispatcher.buy_token(sale_token, 50);
}

#[test]
#[should_panic(expected: ('insufficient funds',))]
fn test_buy_token_insufficient_funds() {
    let owner = contract_address_const::<'owner'>();
    let buyer = contract_address_const::<'buyer'>();
    let payment_token = deploy_token_contract("PaymentToken", "PT");
    let sale_token = deploy_token_contract("SaleToken", "ST");
    
    let token_sale_address = deploy_token_sale(owner, payment_token);
    let dispatcher = ITokenSaleDispatcher { contract_address: token_sale_address };
    
    let payment_dispatcher = IERC20Dispatcher { contract_address: payment_token };
    let sale_dispatcher = IERC20Dispatcher { contract_address: sale_token };
    
    start_cheat_caller_address(payment_token, owner);
    payment_dispatcher.mint(owner, 1000);
    payment_dispatcher.approve(token_sale_address, 500);
    stop_cheat_caller_address(payment_token);
    
    start_cheat_caller_address(sale_token, owner);
    sale_dispatcher.mint(token_sale_address, 500);
    stop_cheat_caller_address(sale_token);
    
    start_cheat_caller_address(token_sale_address, owner);
    dispatcher.deposit_token(sale_token, 500, 1000);
    stop_cheat_caller_address(token_sale_address);
    
    start_cheat_caller_address(token_sale_address, buyer);
    dispatcher.buy_token(sale_token, 500);
}

#[test]
fn test_multiple_token_deposits() {
    let owner = contract_address_const::<'owner'>();
    let payment_token = deploy_token_contract("PaymentToken", "PT");
    let token1 = deploy_token_contract("Token1", "T1");
    let token2 = deploy_token_contract("Token2", "T2");
    
    let token_sale_address = deploy_token_sale(owner, payment_token);
    let dispatcher = ITokenSaleDispatcher { contract_address: token_sale_address };
    
    let payment_dispatcher = IERC20Dispatcher { contract_address: payment_token };
    
    start_cheat_caller_address(payment_token, owner);
    payment_dispatcher.mint(owner, 2000);
    payment_dispatcher.approve(token_sale_address, 2000);
    stop_cheat_caller_address(payment_token);
    
    start_cheat_caller_address(token_sale_address, owner);
    dispatcher.deposit_token(token1, 100, 50);
    dispatcher.deposit_token(token2, 200, 75);
    stop_cheat_caller_address(token_sale_address);
    
    let balance1 = dispatcher.check_available_token(token1);
    let balance2 = dispatcher.check_available_token(token2);
    
}

