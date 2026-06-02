pub mod checker;
pub mod state;

pub use checker::{check_program, OwnershipError};
pub use state::OwnershipState;
