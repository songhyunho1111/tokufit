import SwiftUI
import REPickShared

struct WardrobeView: View {
    @Environment(UsagiStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var category: WardrobeCategory = .top
    @State private var pendingPurchase: WardrobePurchase?
    @State private var shareSnapshot: UsagiState?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Design.sectionSpacing) {
                    currentCharacter
                    VStack(alignment: .leading, spacing: 12) {
                        Text("포인트샵").font(.headline)
                        if dynamicTypeSize.isAccessibilitySize {
                            categoryPicker.pickerStyle(.menu)
                        } else {
                            categoryPicker.pickerStyle(.segmented)
                        }
                        HStack {
                            Text(category.name).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("보유 \(ownedCount)/\(catalogCount)")
                                .font(.subheadline).foregroundStyle(Color.repickSecondaryText)
                        }
                        if category != .top {
                            HStack {
                                Text(equippedItem?.name ?? String(localized: "착용 안 함"))
                                    .font(.subheadline).foregroundStyle(Color.repickSecondaryText)
                                Spacer()
                                Button {
                                    let selectedCategory = category
                                    Task { await store.update { $0.unequipItem(in: selectedCategory) } }
                                } label: {
                                    Text("벗기").frame(minWidth: 44, minHeight: 44)
                                }
                                .disabled(equippedItem == nil || store.isSaving || store.state.profile == nil)
                                .accessibilityLabel("\(category.name) 벗기")
                                .accessibilityIdentifier("wardrobe.unequip.\(category.rawValue)")
                            }
                        }
                        LazyVGrid(columns: columns, spacing: 12) {
                            if category == .top {
                                ForEach(Outfit.allCases) { outfit in outfitCard(outfit) }
                            } else {
                                ForEach(catalogItems) { item in itemCard(item) }
                            }
                        }
                    }
                    drawSection
                }
                .padding(Design.pagePadding)
                .frame(maxWidth: Design.contentWidth)
                .frame(maxWidth: .infinity)
            }
            .background(Color.repickCream)
            .navigationTitle("꾸미기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                PointsToolbar(points: store.state.points)
                ToolbarItem(placement: .topBarLeading) {
                    Button { shareSnapshot = store.state } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("카드 만들기")
                    .accessibilityIdentifier("wardrobe.share")
                    .disabled(store.state.profile == nil || store.isSaving)
                }
            }
            .confirmationDialog("아이템 구매", isPresented: Binding(get: { pendingPurchase != nil }, set: { if !$0 { pendingPurchase = nil } }), titleVisibility: .visible) {
                if let purchase = pendingPurchase {
                    Button("\(purchase.name) · \(purchase.price)P") {
                        Task {
                            let purchased = await store.update { state in
                                switch purchase {
                                case .top(let outfit): try state.buyOutfit(outfit)
                                case .item(let item): try state.buyItem(item)
                                }
                            }
                            if !purchased, store.errorMessage == nil {
                                store.errorMessage = String(localized: "저장 중입니다. 잠시 후 다시 시도해 주세요.")
                            }
                            pendingPurchase = nil
                        }
                    }
                    .disabled(store.isSaving)
                }
                Button("취소", role: .cancel) { pendingPurchase = nil }
            }
            .sheet(isPresented: Binding(get: { shareSnapshot != nil }, set: { if !$0 { shareSnapshot = nil } })) {
                if let shareSnapshot { ShareCardView(snapshot: shareSnapshot) }
            }
        }
    }

    private var currentCharacter: some View {
        VStack(spacing: 8) {
            MapUsagiView(bodyScale: store.state.bodyScale, outfit: store.state.equippedOutfit,
                         heading: 180, cameraHeading: 0,
                         waterLevel: Double(store.state.daily.waterML) / 2_000,
                         accessibilityIdentifier: "wardrobe.currentCharacter",
                         character: store.state.preferences.character, equippedItems: store.state.equippedItems)
                .frame(height: 190)
                .accessibilityLabel("\(store.state.preferences.name)의 현재 모습")
            Text(store.state.preferences.name).font(.headline)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("wardrobe.name")
            Text(([store.state.equippedOutfit.name] + store.state.equippedItems.map(\.name)).joined(separator: " · "))
                .font(.caption).foregroundStyle(Color.repickSecondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var categoryPicker: some View {
        Picker("종류", selection: $category) {
            ForEach(WardrobeCategory.allCases) { category in
                Text(category.name).tag(category)
                    .accessibilityIdentifier("wardrobe.category.\(category.rawValue)")
            }
        }
        .accessibilityIdentifier("wardrobe.category")
    }

    private var catalogItems: [WardrobeItem] { WardrobeItem.allCases.filter { $0.category == category } }
    private var equippedItem: WardrobeItem? { store.state.equippedItems.first { $0.category == category } }
    private var catalogCount: Int { category == .top ? Outfit.allCases.count : catalogItems.count }
    private var ownedCount: Int {
        category == .top ? store.state.ownedOutfits.count : catalogItems.filter(store.state.ownedItems.contains).count
    }

    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.adaptive(minimum: 144, maximum: 220), spacing: 12)]
    }

    private var drawSection: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("상의 뽑기").font(.headline)
                    Spacer(minLength: 8)
                    if store.state.profile != nil {
                        Text("오늘 \(store.state.daily.maximumDraws - store.state.daily.draws)회 남음")
                            .font(.subheadline).foregroundStyle(Color.repickSecondaryText)
                    }
                }
                if let reason = drawUnavailableReason {
                    Text(reason).font(.subheadline).foregroundStyle(Color.repickSecondaryText)
                        .accessibilityIdentifier("wardrobe.drawReason")
                }
                Button("100P로 뽑기", action: drawOutfit)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(drawUnavailableReason != nil || store.isSaving)
                    .accessibilityIdentifier("wardrobe.draw")
                DisclosureGroup("확률과 중복 보상") {
                    Text("학생복·정장·운동복은 각각 1/3 확률입니다. 중복 의상을 뽑으면 50P를 돌려받습니다.")
                        .font(.footnote).foregroundStyle(Color.repickSecondaryText)
                        .padding(.top, 4)
                }
                .font(.subheadline)
                .tint(.repickGreen)
            }
        }
    }

    private var drawUnavailableReason: String? {
        if store.state.profile == nil { return String(localized: "프로필을 먼저 등록하세요.") }
        if !store.state.daily.isGoalComplete { return String(localized: "오늘 걸음 목표를 달성하면 이용할 수 있습니다.") }
        if store.state.daily.draws >= store.state.daily.maximumDraws { return String(localized: "오늘 뽑기를 모두 사용했습니다.") }
        if store.state.points < 100 {
            return store.state.daily.rewardClaimed
                ? String(localized: "뽑기에는 100P가 필요합니다.")
                : String(localized: "홈에서 오늘 목표 보상을 받아 주세요.")
        }
        return nil
    }

    private func outfitCard(_ outfit: Outfit) -> some View {
        let owned = store.state.ownedOutfits.contains(outfit)
        let equipped = store.state.equippedOutfit == outfit
        return VStack(spacing: 12) {
            MapUsagiView(bodyScale: store.state.bodyScale, outfit: outfit,
                         heading: 180, cameraHeading: 0, isAnimating: false,
                         accessibilityIdentifier: "wardrobe.preview.\(outfit.rawValue)",
                         character: store.state.preferences.character, equippedItems: store.state.equippedItems)
                .frame(height: 120)
                .clipped()
                .accessibilityHidden(true)
            Text(outfit.name).font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(equipped ? "착용 중" : owned ? "착용" : "\(outfit.price)P") {
                if owned { Task { await store.update { try $0.equip(outfit) } } }
                else { pendingPurchase = .top(outfit) }
            }
            .buttonStyle(OutfitButtonStyle(owned: owned))
            .accessibilityLabel(equipped ? "\(outfit.name) 착용 중" : owned ? "\(outfit.name) 착용" : "\(outfit.name) \(outfit.price)포인트 구매")
            .accessibilityHint(store.state.profile == nil ? Text("프로필을 먼저 등록하세요.")
                : !owned && store.state.points < outfit.price
                    ? Text("\(outfit.price - store.state.points)포인트가 더 필요합니다.") : Text(""))
            .accessibilityIdentifier("wardrobe.outfit.\(outfit.rawValue)")
            .disabled(equipped || store.isSaving || (!owned && store.state.points < outfit.price) || store.state.profile == nil)
        }
        .padding(Design.cardPadding)
        .frame(maxWidth: .infinity)
        .background(Color.repickSurface, in: RoundedRectangle(cornerRadius: Design.controlRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Design.controlRadius)
                .strokeBorder(equipped ? Color.repickGreen : .clear, lineWidth: 1.5)
        }
        .overlay(alignment: .topTrailing) {
            if equipped {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.repickGreen)
                    .padding(12)
                    .accessibilityHidden(true)
            }
        }
    }

    private func itemCard(_ item: WardrobeItem) -> some View {
        let owned = store.state.ownedItems.contains(item)
        let equipped = store.state.equippedItems.contains(item)
        let previewItems = store.state.equippedItems.filter { $0.category != item.category } + [item]
        return VStack(spacing: 12) {
            MapUsagiView(bodyScale: store.state.bodyScale, outfit: store.state.equippedOutfit,
                         heading: 180, cameraHeading: 0, isAnimating: false,
                         accessibilityIdentifier: "wardrobe.preview.\(item.rawValue)",
                         character: store.state.preferences.character, equippedItems: previewItems)
                .frame(height: 120)
                .clipped()
                .accessibilityHidden(true)
            Text(item.name).font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(equipped ? "착용 중" : owned ? "착용" : "\(item.price)P") {
                if owned { Task { await store.update { try $0.equipItem(item) } } }
                else { pendingPurchase = .item(item) }
            }
            .buttonStyle(OutfitButtonStyle(owned: owned))
            .accessibilityLabel(equipped ? "\(item.name) 착용 중" : owned ? "\(item.name) 착용" : "\(item.name) \(item.price)포인트 구매")
            .accessibilityHint(store.state.profile == nil ? Text("프로필을 먼저 등록하세요.")
                : !owned && store.state.points < item.price
                    ? Text("\(item.price - store.state.points)포인트가 더 필요합니다.") : Text(""))
            .accessibilityIdentifier("wardrobe.item.\(item.rawValue)")
            .disabled(equipped || store.isSaving || (!owned && store.state.points < item.price) || store.state.profile == nil)
        }
        .padding(Design.cardPadding)
        .frame(maxWidth: .infinity)
        .background(Color.repickSurface, in: RoundedRectangle(cornerRadius: Design.controlRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Design.controlRadius)
                .strokeBorder(equipped ? Color.repickGreen : .clear, lineWidth: 1.5)
        }
        .overlay(alignment: .topTrailing) {
            if equipped {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.repickGreen)
                    .padding(12)
                    .accessibilityHidden(true)
            }
        }
    }

    private func drawOutfit() {
        Task {
            var result: Outfit?
            var duplicate = false
            if await store.update({ state in
                let index = Int.random(in: Outfit.drawPool.indices)
                duplicate = state.ownedOutfits.contains(Outfit.drawPool[index])
                result = try state.drawOutfit(randomIndex: index)
            }), let result {
                store.notice = result.name + (duplicate ? String(localized: " · 중복 의상, 50P 반환") : String(localized: " 획득 · 착용 완료"))
            }
        }
    }
}

private enum WardrobePurchase {
    case top(Outfit)
    case item(WardrobeItem)

    var name: String {
        switch self {
        case .top(let outfit): outfit.name
        case .item(let item): item.name
        }
    }

    var price: Int {
        switch self {
        case .top(let outfit): outfit.price
        case .item(let item): item.price
        }
    }
}

private struct OutfitButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let owned: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isEnabled ? (owned ? Color.repickInk : Color.repickRewardInk) : Color.repickSecondaryText)
            .frame(maxWidth: .infinity, minHeight: Design.controlHeight)
            .background(
                owned ? Color.repickBorder.opacity(isEnabled ? 0.55 : 0.30)
                    : (isEnabled ? Color.repickYellow : Color.repickRewardSurface),
                in: RoundedRectangle(cornerRadius: Design.controlRadius)
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}
