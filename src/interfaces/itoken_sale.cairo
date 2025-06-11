use starknet::{ContractAddress, ClassHash};

#[starknet::interface]
pub trait ITokenSale<TContractState> {
    fn check_available_token(self: @TContractState, token_address: ContractAddress) -> u256;

    fn deposit_token(ref self: TContractState, token_address: ContractAddress, amount: u256, token_price: u256);

    fn buy_token(ref self: TContractState, token_address: ContractAddress, amount: u256);

    fn upgrade(ref self: TContractState, new_class_hash: ClassHash);
}