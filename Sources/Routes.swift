import Foundation

/// Typed navigation values so cards, credits and offers never collide in one stack.
struct CardRoute: Hashable { let id: UUID }
struct CreditRoute: Hashable { let id: UUID }
struct OfferRoute: Hashable { let id: String }
