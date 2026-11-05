#!/usr/bin/env python3
"""Guarded compile repair for iumrah GitHub Actions checkout at commit 9aa5191.

This migration runs after the existing language repairs and before swiftc parse.
It never alters API services or pricing methods, and aborts before any write if
an expected source anchor is missing. Do not run in an arbitrary repository.
"""
from __future__ import annotations
import argparse
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
changed: dict[Path, str] = {}
messages: list[str] = []

class UnexpectedSource(RuntimeError):
    pass

def load(rel: str) -> str:
    p = ROOT / rel
    if not p.is_file():
        raise UnexpectedSource(f"Missing source: {rel}")
    return changed.get(p, p.read_text(encoding="utf-8"))

def save(rel: str, old_text: str, new_text: str, reason: str) -> None:
    if old_text != new_text:
        changed[ROOT/rel] = new_text
        messages.append(f"{rel}: {reason}")

def replace_unique(rel: str, before: str, after: str, reason: str) -> None:
    t = load(rel)
    occurrences = t.count(before)
    if occurrences == 1:
        save(rel, t, t.replace(before, after, 1), reason)
    elif occurrences == 0 and after in t:
        messages.append(f"{rel}: already fixed: {reason}")
    else:
        raise UnexpectedSource(f"Anchor count {occurrences} instead of 1 for {rel}: {reason}")

def replace_region(rel: str, start: str, end: str, updated: str, reason: str) -> None:
    t = load(rel)
    count = t.count(start)
    if count == 0 and updated in t:
        messages.append(f"{rel}: already fixed: {reason}");return
    if count != 1 or t.count(end) != 1:
        raise UnexpectedSource(f"Missing/ambiguous region for {rel}: {reason}")
    a = t.index(start)
    b = t.index(end,a)
    if b <= a:
        raise UnexpectedSource(f"Invalid region {rel}: {reason}")
    save(rel,t,t[:a]+updated+t[b:],reason)

# Restore a central semantic color, without copying stale design screens.
rel="Sources/Core/IumrahFoundation.swift"
t=load(rel)
if "static let iumrahSignatureBlack" not in t:
    if not t.startswith("import SwiftUI\n"):
        raise UnexpectedSource(f"Unexpected import in {rel}")
    extra='''\n// Semantic graphite token used by root chrome and navigation.\nextension Color {\n    static let iumrahSignatureBlack = Color(red: 17.0 / 255.0, green: 17.0 / 255.0, blue: 17.0 / 255.0)\n}\n'''
    save(rel,t,t.replace('import SwiftUI\n','import SwiftUI\n'+extra,1),"restore signature graphite Color token")

# Keep the new 8-language enum exhaustive where a locale was still 4-language.
rel="Sources/Views/Flights/IumrahFlightDiscoveryView.swift"
old='''    private var locale: Locale {
        switch settings.language {
        case .russian: return Locale(identifier: "ru_RU")
        case .english: return Locale(identifier: "en_US")
        case .uzbek: return Locale(identifier: "uz_Latn_UZ")
        case .uzbekCyrillic: return Locale(identifier: "uz_Cyrl_UZ")
        }
    }'''
new='''    private var locale: Locale {
        switch settings.language {
        case .russian: return Locale(identifier: "ru_RU")
        case .english: return Locale(identifier: "en_US")
        case .uzbek: return Locale(identifier: "uz_Latn_UZ")
        case .uzbekCyrillic: return Locale(identifier: "uz_Cyrl_UZ")
        case .turkish: return Locale(identifier: "tr_TR")
        case .arabic: return Locale(identifier: "ar_SA")
        case .indonesian: return Locale(identifier: "id_ID")
        case .malay: return Locale(identifier: "ms_MY")
        }
    }'''
# The earlier v3 language-compat pass may already have grouped new languages
# into the English arm. Replace either the original or that exact transformed
# arm; never blindly add duplicate Swift cases.
flat=old.replace('case .english: return Locale(identifier: "en_US")',
                 'case .english, .turkish, .indonesian, .malay, .arabic: return Locale(identifier: "en_US")')
current=load(rel)
if current.count(old)==1:
    replace_unique(rel,old,new,"complete flight date locale switch")
elif current.count(flat)==1:
    replace_unique(rel,flat,new,"replace English fallback with exact flight locales")
elif current.count(new)==1:
    messages.append(f"{rel}: flight locale already fixed")
else:
    raise UnexpectedSource(f"Flight locale layout unexpectedly changed in {rel}")

# `services/visa/...` enum values still exist for old links, not Picker tabs.
rel="Sources/Views/Tabs/HotelsHomeView.swift"
replace_unique(rel,'''                case .sundayClub:
                    sundayClubBoard
                }''','''                case .sundayClub:
                    sundayClubBoard
                case .services, .visa, .transfer, .guide, .summary:
                    hotelsBoard // Legacy non-visible deep-link targets stay in the storefront.
                }''',"handle legacy board enum cases")
replace_unique(rel,'''        case .sundayClub: return "Sunday Umrah Club"
        }''','''        case .sundayClub: return "Sunday Umrah Club"
        case .services, .visa, .transfer, .guide, .summary:
            return L10n.text("tab_hotels", settings.language)
        }''',"complete storefront title switch")

# The hotel-choice row retained 6 arguments after its card definition changed.
rel="Sources/Views/Tabs/HotelsHomeView.swift"
marker='''    let onShare: () -> Void

    private let cardHeight: CGFloat = 204'''
rep='''    let onShare: () -> Void
    // Explicit actions for the hotel selector; defaults preserve storefront cards.
    var selectionRole: HotelSelectionRole? = nil
    var isSelectedInConfigurator = false
    var pendingPriceLabel: String? = nil
    var selectHotelLabel: String? = nil
    var selectedHotelLabel: String? = nil
    var onSelectHotel: (() -> Void)? = nil

    private let cardHeight: CGFloat = 204'''
replace_unique(rel,marker,rep,"restore configurator hotel-card API")
# Button is visually compact and works without replacing card-details tapping.
t=load(rel)
start=t.index('struct HotelStorefrontCard: View {')
end=t.index('private struct HotelStorefrontCollage',start)
chunk=t[start:end]
old='''        .accessibilityAddTraits(.isButton)
    }'''
new='''        .overlay(alignment: .bottomTrailing) {
            if let onSelectHotel {
                Button(action: onSelectHotel) {
                    Text(isSelectedInConfigurator ? (selectedHotelLabel ?? "Selected") : (selectHotelLabel ?? "Select"))
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 11)
                        .frame(minHeight: 34)
                        .foregroundStyle(isSelectedInConfigurator ? Color.iumrahInk : Color.white)
                        .background(isSelectedInConfigurator ? Color.iumrahRaisedBackground : Color.iumrahSignatureBlack,
                                    in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(9)
            }
        }
        .accessibilityAddTraits(.isButton)
    }'''
if chunk.count(old)==1:
    updated=t[:start]+chunk.replace(old,new,1)+t[end:]
    save(rel,t,updated,"preserve hotel selection CTA on cards")
elif new in chunk:
    pass
else:
    raise UnexpectedSource('HotelStorefrontCard onSelectHotel overlay insertion location missing')

# Old capture sheet was removed when the secure OTP booking flow was introduced.
# Reconnect BOTH entrypoints to the existing verified BookingPilgrimProfile flow.
rel="Sources/Views/Package/FinalPackageView.swift"
replace_unique(rel,'''        .sheet(isPresented: $isProfileSheetPresented) {
            BookingProfileCaptureSheet {
                Task { await createBooking() }
            }
            .environmentObject(settings)
        }''','''        .sheet(isPresented: $isProfileSheetPresented) {
            NavigationStack {
                IumrahBookingConfirmationView(createBooking: { profile in
                    try await createBooking(profile: profile)
                })
                .environmentObject(settings)
            }
        }''',"use verified booking confirmation instead of deleted sheet")
rel="Sources/Views/Tabs/HotelsHomeView.swift"
replace_unique(rel,'''        .sheet(isPresented: $isProfileSheetPresented) {
            BookingProfileCaptureSheet {
                Task { await createBooking() }
            }
            .environmentObject(settings)
        }''','''        .sheet(isPresented: $isProfileSheetPresented) {
            NavigationStack {
                IumrahBookingConfirmationView(createBooking: { profile in
                    try await createBooking(profile: profile)
                })
                .environmentObject(settings)
            }
        }''',"use verified booking confirmation for hotel-first package")

# FinalPackageView used familyFlow in newer transfer implementation.
rel="Sources/Views/Package/FinalPackageView.swift"
replace_unique(rel,'''struct FinalPackageView: View {
    @EnvironmentObject private var journey: JourneyStore''','''struct FinalPackageView: View {
    var familyFlow = false
    @EnvironmentObject private var journey: JourneyStore''',"restore familyFlow initializer compatibility")

final_create='''    @MainActor
    private func createBooking(profile: BookingPilgrimProfile) async throws -> StoredBookingSession {
        guard !isSubmitting,
              let hotel = journey.selectedHotel,
              let outbound = journey.selectedOutbound,
              let quote = journey.quote else { throw BookingStoreError.authoritativeQuoteRequired }
        let inbound = journey.selectedInbound
        guard outbound.isVerifiedForBooking,
              (!journey.trip.isRoundTripFlight || inbound?.isVerifiedForBooking == true) else {
            errorMessage = invalidFlightSelectionMessage
            IumrahHaptics.error()
            throw BookingStoreError.authoritativeQuoteRequired
        }
        if needsMadinah && journey.selectedMadinahHotel == nil {
            throw BookingStoreError.authoritativeQuoteRequired
        }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            let session = try await bookings.create(
                trip: journey.trip,
                hotel: hotel,
                madinahHotel: journey.selectedMadinahHotel,
                room: journey.selectedRoom,
                roomCategory: journey.selectedRoomCategory,
                madinahRoom: journey.selectedMadinahRoom,
                madinahRoomCategory: journey.selectedMadinahRoomCategory,
                intercityTransport: needsMadinah ? (journey.haramainTrainSelected ? .haramainTrain : .road) : nil,
                transferVehicle: journey.selectedTransferVehicle ?? journey.recommendedTransferVehicle(),
                outbound: outbound,
                inbound: inbound,
                quote: quote,
                language: settings.language,
                pilgrimProfile: profile
            )
            createdSession = session
            if let deviceToken = push.deviceToken {
                await bookings.syncPushSubscriptions(deviceToken: deviceToken, locale: settings.language.rawValue)
            }
            IumrahHaptics.success()
            return session
        } catch {
            errorMessage = L10n.error(error, settings.language)
            IumrahHaptics.error()
            throw error
        }
    }

'''
replace_region('Sources/Views/Package/FinalPackageView.swift',
               '    @MainActor\n    private func createBooking() async {',
               '    private var invalidFlightSelectionMessage: String {',
               final_create,"pass verified pilgrim profile to server booking")

hotel_create='''    @MainActor
    private func createBooking(profile: BookingPilgrimProfile) async throws -> StoredBookingSession {
        guard !isSubmitting,
              let hotel = journey.selectedHotel,
              let outbound = journey.selectedOutbound,
              let inbound = journey.selectedInbound,
              let quote = journey.quote else { throw BookingStoreError.authoritativeQuoteRequired }
        if journey.trip.scope == .makkahAndMadinah && journey.selectedMadinahHotel == nil {
            throw BookingStoreError.authoritativeQuoteRequired
        }
        isSubmitting = true
        bookingError = nil
        defer { isSubmitting = false }
        do {
            let session = try await bookings.create(
                trip: journey.trip,
                hotel: hotel,
                madinahHotel: journey.selectedMadinahHotel,
                room: journey.selectedRoom,
                roomCategory: journey.selectedRoomCategory,
                madinahRoom: journey.selectedMadinahRoom,
                madinahRoomCategory: journey.selectedMadinahRoomCategory,
                intercityTransport: journey.trip.scope == .makkahAndMadinah
                    ? (journey.haramainTrainSelected ? .haramainTrain : .road)
                    : nil,
                transferVehicle: journey.selectedTransferVehicle ?? journey.recommendedTransferVehicle(),
                outbound: outbound,
                inbound: inbound,
                quote: quote,
                language: settings.language,
                pilgrimProfile: profile
            )
            if let deviceToken = push.deviceToken {
                await bookings.syncPushSubscriptions(deviceToken: deviceToken, locale: settings.language.rawValue)
            }
            IumrahHaptics.success()
            createdBookingID = session.id
            return session
        } catch {
            bookingError = L10n.error(error, settings.language)
            IumrahHaptics.error()
            throw error
        }
    }
'''
replace_region('Sources/Views/Tabs/HotelsHomeView.swift',
               '    @MainActor\n    private func createBooking() async {',
               '    private func money(_ value: Decimal) -> String {',
               hotel_create,"pass verified pilgrim profile into hotel-first booking")

# Date/communication source mismatches.
replace_unique('Sources/Views/RootView.swift',
               '''            plannedTrip: UmrahPlanStore.shared.trip
        )''',
               '''            plannedTrip: UmrahPlanStore.shared.trip,
            languageCode: settings.language.rawValue
        )''',
               "pass widget locale to widget synchronization")
replace_unique('Sources/Views/Hotels/PrimaryHotelView.swift',
               '''IumrahGeneratorHeader(stage: .hotel, currentPriceText: visibleTotal, isPriceLoading: isUpdatingPrice)''',
               '''IumrahGeneratorHeader(stage: .hotel, currentPriceText: visibleTotal)''',
               "match generator header parameters")

# Registration APIs do not accept a password in the current server contracts.
# In the email OTP path, keep the verified session instead of a broken password login.
rel="Sources/AppShell/IumrahAccountView.swift"
replace_unique(rel,
               '''                challengeID: registrationSMSChallengeID,
                code: registrationSMSCode,
                password: registrationPassword,
                locale: settings.language.rawValue''',
               '''                challengeID: registrationSMSChallengeID,
                code: registrationSMSCode,
                locale: settings.language.rawValue''',
               "use existing SMS registration API signature")
replace_unique(rel,
               '''                challengeID: registrationEmailChallengeID,
                code: registrationEmailCode,
                password: registrationPassword,
                firstName:''',
               '''                challengeID: registrationEmailChallengeID,
                code: registrationEmailCode,
                firstName:''',
               "use existing email OTP registration API signature")
replace_unique(rel,
               '''            let profile = try await account.login(
                identifier: response.account.iumrahID,
                password: registrationPassword,
                locale: settings.language.rawValue
            )''',
               '''            let profile = await account.acceptVerifiedSession(response, locale: settings.language.rawValue)''',
               "reuse authenticated email OTP response without a password re-login")

# Umrah Flow uses its own language enum, which does NOT have Uzbek Cyrillic.
for rel in ('Sources/Umrah Flow/Components/UmrahFlowTheme.swift',
            'Sources/Umrah Flow/Components/UmrahTawafCopy.swift'):
    t=load(rel)
    if 'case .english, .uzbekCyrillic' in t:
        save(rel,t,t.replace('case .english, .uzbekCyrillic','case .english'),
             "remove invalid case from separate Umrah Guide enum")
    elif 'case .english:' in t:
        pass
    else:
        raise UnexpectedSource(f"Invalid Umrah Guide language marker: {rel}")

# Explicit value identity resolves SwiftUI ForEach initializer inference.
rel="Sources/Core/Components/IumrahSignatureChrome.swift"
replace_unique(rel,'ForEach(tabs) { tab in','ForEach(tabs, id: \\.id) { tab in',"avoid ambiguous ForEach binding initializer")
# The prefetched predecessor contains one `ForEach(tabs)` only.

# Decompose SwiftUI tab label to avoid Xcode 26 type-check timeout.
rel="Sources/AppShell/IumrahStoreTabBar.swift"
t=load(rel)
start=t.find('            ForEach(tabs, id: \\.self) { tab in')
if start == -1:
    if 'private func tabLabel(' not in t:
        raise UnexpectedSource(f"Tab bar label layout changed in {rel}")
else:
    stop=t.find('\n        }\n        .padding(5)',start)
    if stop < 0:
        raise UnexpectedSource('Tab bar ForEach end marker missing')
    new_loop='''            ForEach(tabs, id: \\.self) { tab in
                let active = selection == tab
                Button {
                    guard !active else { return }
                    IumrahHaptics.selection()
                    if reduceMotion { selection = tab }
                    else { withAnimation(.easeInOut(duration: 0.18)) { selection = tab } }
                } label: {
                    tabLabel(tab, active: active)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title(for: settings.language))
                .accessibilityAddTraits(active ? .isSelected : [])
            }'''
    t2=t[:start]+new_loop+t[stop:]
    fn='''
    private func tabLabel(_ tab: AppTab, active: Bool) -> some View {
        VStack(spacing: 5) {
            Image(systemName: tab.systemImage)
                .font(.system(size: 21, weight: active ? .semibold : .regular))
                .frame(height: 25)
            Text(tab.title(for: settings.language))
                .font(.system(size: 10.5, weight: active ? .semibold : .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .foregroundStyle(active ? Color.white : Color.black.opacity(0.75))
        .frame(maxWidth: .infinity)
        .frame(height: 65)
        .background {
            if active {
                RoundedRectangle(cornerRadius: 25, style: .continuous)
                    .fill(Color.iumrahSignatureBlack)
            }
        }
        .contentShape(Rectangle())
    }
'''
    loc=t2.rfind('\n}')
    if loc<0: raise UnexpectedSource('Tab bar missing final }')
    t2=t2[:loc]+fn+t2[loc:]
    save(rel,load(rel),t2,"decompose native tab bar to avoid expensive SwiftUI inference")

# Commit only after every assertion passed.
parser=argparse.ArgumentParser()
parser.add_argument('--apply',action='store_true')
args=parser.parse_args()
print(f"VALIDATED: {len(changed)} Swift source repairs; prepared as an atomic batch")
for message in messages:
    print(' -',message)
if args.apply:
    for path,data in changed.items():
        path.write_text(data,encoding='utf-8')
    print(f"APPLIED: {len(changed)} Swift source changes before XcodeGen")
else:
    print('DRY RUN: pass --apply to write')
