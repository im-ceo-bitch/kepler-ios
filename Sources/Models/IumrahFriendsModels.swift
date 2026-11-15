import Foundation

struct IumrahFriendGift: Decodable, Identifiable, Hashable {
    let id: String
    let code: String
    let position: Int
    let status: String
    let redeemedBookingID: String?
    let rewardStatus: String?
    let rewardUsd: Double
    let discountUsd: Double
    let createdAt: String
    let redeemedAt: String?

    var isAvailable: Bool { status.lowercased() == "available" }
    var isRewardPending: Bool { rewardStatus?.lowercased() == "pending" }
    var isRewardEarned: Bool { rewardStatus?.lowercased() == "earned" }
}

struct IumrahFriendsDashboard: Decodable, Hashable {
    let ok: Bool
    let availableCreditUsd: Double
    let pendingRewardsUsd: Double
    let earnedRewardsUsd: Double
    let gifts: [IumrahFriendGift]
    let invitation: IumrahReferralInvitation?
    let referrals: [IumrahReferralFriend]?
    let transactions: [IumrahRewardTransaction]?
    let completedTrips: Int?
    let paidReferrals: Int?
    let tier: String?
}

struct IumrahFriendsAppliedGift: Decodable, Hashable, Identifiable {
    let code: String
    let discountUsd: Double
    let rewardStatus: String

    var id: String { code }
}

struct IumrahFriendsBookingSummary: Decodable, Hashable {
    let ok: Bool
    let bookingID: String
    let identityConfirmed: Bool
    let totalUsd: Double
    let maxDiscountUsd: Double
    let giftDiscountUsd: Double
    let creditAppliedUsd: Double
    let totalDiscountUsd: Double
    let remainingAllowanceUsd: Double
    let payableUsd: Double
    let availableCreditUsd: Double
    let appliedGifts: [IumrahFriendsAppliedGift]
}

struct IumrahFriendGiftRedeemRequest: Encodable {
    let code: String
}

struct IumrahFriendCreditApplyRequest: Encodable {
    let amountUsd: Int
}

struct IumrahReferralInvitation: Decodable, Hashable { let code: String; let url: String }
struct IumrahReferralFriend: Decodable, Hashable, Identifiable {
    let id: String; let name: String; let status: String; let rewardUsd: Double; let registeredAt: String; let bookingID: String?
}
struct IumrahRewardTransaction: Decodable, Hashable, Identifiable {
    let id: String; let amountUsd: Double; let type: String; let createdAt: String
}
