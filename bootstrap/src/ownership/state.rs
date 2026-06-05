use std::fmt;

/// Ownership state of a variable at any point in the program
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum OwnershipState {
    /// The variable owns a Copy type (can be used multiple times)
    Copy,
    /// The variable owns a non-Copy value and can be used or moved
    Owned,
    /// The value has been moved to another variable
    Moved,
    /// There is an active immutable borrow (`^x`)
    Borrowed { count: usize },
    /// There is an active mutable borrow (`^mut x`)
    MutBorrowed,
}

impl OwnershipState {
    pub fn is_usable(&self) -> bool {
        matches!(self, OwnershipState::Copy | OwnershipState::Owned | OwnershipState::Borrowed { .. })
    }

    pub fn is_moved(&self) -> bool {
        matches!(self, OwnershipState::Moved)
    }

    pub fn is_copy(&self) -> bool {
        matches!(self, OwnershipState::Copy)
    }

    pub fn is_mut_borrowed(&self) -> bool {
        matches!(self, OwnershipState::MutBorrowed)
    }

    pub fn has_active_borrows(&self) -> bool {
        matches!(self, OwnershipState::Borrowed { .. } | OwnershipState::MutBorrowed)
    }
}

impl fmt::Display for OwnershipState {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            OwnershipState::Copy => write!(f, "copy"),
            OwnershipState::Owned => write!(f, "owned"),
            OwnershipState::Moved => write!(f, "moved"),
            OwnershipState::Borrowed { count } => write!(f, "borrowed ({} active)", count),
            OwnershipState::MutBorrowed => write!(f, "mutably borrowed"),
        }
    }
}
