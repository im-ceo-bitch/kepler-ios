#!/usr/bin/env python3
"""Source-level Home 2.0 + Profile 2.0 regression checks; not an iOS build."""
from pathlib import Path
import sys
root = Path(__file__).resolve().parents[1]
r = root / 'Sources'
h = (r/'Views/Home/HomeDashboardView.swift').read_text()
a = (r/'AppShell/IumrahAccountView.swift').read_text()
p = (r/'Views/Home/HomePersonalizationSections.swift').read_text()
checks = {}
home = h.split('private var marketingHome: some View {',1)[1].split('private var homeIncludedServicesSection:',1)[0]
expected = ['IumrahHomeJourneySearchHero(', 'publishedFlightSection','WhyIumrahCarousel(', 'IumrahMissionCard()', 'HomeRecentActivitySection(', 'HomeAvailablePackagesSection(', 'homeIncludedServicesSection','homeBenefitsSection','IumrahSloganCard()']
checks['Home follows agreed order'] = all(home.find(a) < home.find(b) for a,b in zip(expected,expected[1:]))
checks['Home has no video or duplicated promos'] = all(t not in home for t in ['HomeVideoCarousel()', 'homeIntegrationsSection','productsCarousel()', 'HomeEmotionalJourneyPrompt()', 'HomeDestinationsSection()', 'HomeRewardsOffersSection(', 'HomeRecommendedHotelsSection()', 'SmartConfiguratorHomeCard'])
checks['Search and selected flights persist'] = all(x in h for x in ['IumrahGraphiteSearchSurface','IumrahPublishedFlightCarousel(', 'publishedSelection.choose(', 'publishedSelection.commit(', 'showPublishedHotels = true'])
checks['Manual return retains direction'] = 'onSelect: { flight in _ = publishedSelection.choose(flight, direction: publishedDirection' in h
checks['Smart accessible without promo'] = 'startNewSmart()' in h and 'iumrah Smart' in h
checks['Included services open existing details'] = all(x in h for x in ['IumrahServicesView(initialService: kind)', 'IumrahServiceKind.visa, .flights, .hotels, .transfer, .guide, .ziyarat'])
checks['Balance, Rewards, Friends compact'] = all(x in h for x in ['IumrahBalanceVisualPage(language:', 'IumrahRewardsVisualPage(language:', 'IumrahFriendsVisualPage(language:'])
checks['Published offers only, no fallback'] = 'HomeAvailablePackagesSection(showsFallback: false' in h and 'if !points.isEmpty || showsFallback' in p
checks['Home no background endless polling'] = 'while !Task.isCancelled {' not in h.split('var body: some View',1)[1].split('private var marketingHome:',1)[0]
main_account = a.split('var body: some View {',1)[1].split('private var seamlessGuestProfile:',1)[0]
checks['Account is grouped'] = all(x in a for x in ['compactAccountContent(profile)', 'compactAccountGroup(', 'compactAccountRow(', 'compactGuestActions'])
checks['Booking access for both auth states'] = a.count('NavigationLink { IumrahFindBookingView() }') >= 2
checks['Preserves booking, saved, favorite and traveler pages'] = all(x in a for x in ['SavedJourneysView()', 'NuiteeHotelsCatalogView(refreshSignal: 0, favoritesOnly: true)', 'IumrahTravelCompanionsView()', 'chrome.navigate(to: .booking)'])
checks['Identity and Wallet available'] = 'showIdentityFullscreen = true' in a and 'PKPassLibrary.isPassLibraryAvailable()' in a and 'await addIdentityToWallet()' in a
checks['User can sign out/delete'] = 'signOutButton' in main_account and 'deleteAccountButton' in main_account
checks['Recent history controls retained'] = all(x in a for x in ['homeHistory.setEnabled($0)', 'homeHistory.clear(owner: HomePersonalizationStore.owner(account))', 'showClearRecentConfirmation'])
checks['Slogan on Profile'] = 'IumrahSloganCard()' in main_account
for k,v in checks.items(): print(('PASS' if v else 'FAIL')+': '+k)
assert all(checks.values())
print(f'HOME + PROFILE static regression: {len(checks)}/{len(checks)}')
