import SwiftUI
import REPickShared
import UIKit

struct WardrobeView: View {
    @Environment(UsagiStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var category: WardrobeCategory?
    @State private var pendingPurchase: WardrobePurchase?
    @State private var shareSnapshot: UsagiState?
    @State private var gachaEntry: GachaEntry?
    @State private var gachaNotice: String?
    @State private var costumePreviews: [CharacterCostume: UIImage] = [:]
    @State private var failedPreviews: Set<CharacterCostume> = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Design.sectionSpacing) {
                    header
                    currentCharacter
                    VStack(alignment: .leading, spacing: 12) {
                        categoryPicker
                        HStack {
                            Text(category?.name ?? String(localized: "코스튬"))
                                .font(AppFont.font(.subheadline, weight: .semibold))
                            Spacer()
                            Text("보유 \(ownedCount)/\(catalogCount)")
                                .font(AppFont.font(.caption)).foregroundStyle(Color.repickSecondaryText)
                            PointBadge(points: store.state.points)
                        }
                        if category == nil {
                            HStack {
                                Text("\(store.state.preferences.character.name)의 코스튬")
                                    .font(AppFont.font(.subheadline)).foregroundStyle(Color.repickSecondaryText)
                                Spacer()
                                Button("벗기") {
                                    Task { await store.update { $0.unequipCostume() } }
                                }
                                .frame(minWidth: 44, minHeight: 44)
                                .disabled(store.state.currentCostume == nil || store.isSaving || store.state.profile == nil)
                                .accessibilityLabel("코스튬 벗기")
                                .accessibilityIdentifier("wardrobe.unequip.costume")
                            }
                        } else if let category, category != .top {
                            HStack {
                                Text(equippedItem?.name ?? String(localized: "착용 안 함"))
                                    .font(AppFont.font(.subheadline)).foregroundStyle(Color.repickSecondaryText)
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
                        LazyVGrid(columns: columns, spacing: 10) {
                            if category == nil {
                                ForEach(costumes) { costume in costumeCard(costume) }
                            } else if category == .top {
                                ForEach(Outfit.allCases) { outfit in outfitCard(outfit) }
                            } else {
                                ForEach(catalogItems) { item in itemCard(item) }
                            }
                        }
                        if category == nil, costumes.contains(where: failedPreviews.contains) {
                            HStack {
                                Text("일부 미리보기를 불러오지 못했어요.")
                                    .font(AppFont.font(.footnote)).foregroundStyle(Color.repickSecondaryText)
                                Spacer()
                                Button("다시 시도") { Task { await loadCostumePreviews() } }
                                    .frame(minHeight: 44)
                                    .accessibilityIdentifier("wardrobe.retryPreviews")
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
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button("이 모습으로 카드 만들기") { shareSnapshot = store.state }
                    .buttonStyle(WardrobeShareButtonStyle())
                    .disabled(store.state.profile == nil || store.isSaving)
                    .accessibilityIdentifier("wardrobe.shareCurrent")
                    .padding(.horizontal, Design.pagePadding)
                    .padding(.vertical, 10)
                    .frame(maxWidth: Design.contentWidth)
            }
            .confirmationDialog("아이템 구매", isPresented: Binding(get: { pendingPurchase != nil }, set: { if !$0 { pendingPurchase = nil } }), titleVisibility: .visible) {
                if let purchase = pendingPurchase {
                    Button("\(purchase.name) · \(purchase.price)P") {
                        Task {
                            let purchased = await store.update { state in
                                switch purchase {
                                case .costume(let costume): try state.buyCostume(costume)
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
                    .disabled(store.isSaving || store.state.points < purchase.price)
                }
                Button("취소", role: .cancel) { pendingPurchase = nil }
            } message: {
                if let purchase = pendingPurchase {
                    Text("보유 \(store.state.points)P · 구매 가격 \(purchase.price)P")
                }
            }
            .sheet(isPresented: Binding(get: { shareSnapshot != nil }, set: { if !$0 { shareSnapshot = nil } })) {
                if let shareSnapshot { ShareCardView(snapshot: shareSnapshot) }
            }
            .fullScreenCover(item: $gachaEntry, onDismiss: {
                if let gachaNotice {
                    store.notice = gachaNotice
                    self.gachaNotice = nil
                }
            }) { entry in
                GachaOpenView(drawID: entry.id, randomIndex: entry.randomIndex, payment: entry.payment,
                              character: entry.character) { receipt in
                    let name = receipt.costume.map { "\($0.character.name) \(receipt.rewardName)" } ?? receipt.rewardName
                    gachaNotice = name + (receipt.wasDuplicate
                        ? String(localized: " · 중복 의상, 50P 반환")
                        : String(localized: " 획득 · 착용 완료"))
                }
            }
            .task(id: store.state.preferences.character) { await loadCostumePreviews() }
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text("꾸미기").font(AppFont.font(.largeTitle, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 16)
                shareButton
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("꾸미기").font(AppFont.font(.largeTitle, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                shareButton
            }
        }
    }

    private var shareButton: some View {
        Button { shareSnapshot = store.state } label: {
            Label("카드 만들기", systemImage: "square.and.arrow.up")
                .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(WardrobeShareButtonStyle())
        .disabled(store.state.profile == nil || store.isSaving)
        .accessibilityIdentifier("wardrobe.share")
    }

    private var currentCharacter: some View {
        VStack(spacing: 8) {
            MapUsagiView(bodyScale: store.state.bodyScale, outfit: store.state.equippedOutfit,
                         heading: 180, cameraHeading: 0,
                         waterLevel: Double(store.state.daily.waterML) / 2_000,
                         accessibilityIdentifier: "wardrobe.currentCharacter",
                         character: store.state.preferences.character, equippedItems: store.state.equippedItems,
                         muscleLevel: store.state.muscleLevel, fieryEyes: store.state.attendanceNeedsAttention,
                         nutritionMood: store.state.nutritionMood, costume: store.state.currentCostume)
                .frame(height: 220)
                .accessibilityLabel("\(store.state.preferences.name)의 현재 모습")
            Text(store.state.preferences.name).font(AppFont.font(.headline))
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("wardrobe.name")
            Text(currentStyleName)
                .font(AppFont.font(.caption)).foregroundStyle(Color.repickSecondaryText)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("wardrobe.currentStyle")
        }
        .frame(maxWidth: .infinity)
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                categoryButton(nil)
                ForEach(WardrobeCategory.allCases) { categoryButton($0) }
            }
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("wardrobe.category")
    }

    private func categoryButton(_ option: WardrobeCategory?) -> some View {
        Button { category = option } label: {
            Text(option?.name ?? String(localized: "코스튬"))
                .font(AppFont.font(.subheadline, weight: .medium))
                .padding(.horizontal, 18)
                .frame(minHeight: 44)
                .foregroundStyle(Color.repickInk)
                .background(category == option ? Color.repickBorder : Color.repickRewardSurface.opacity(0.5),
                            in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(category == option ? .isSelected : [])
        .accessibilityIdentifier("wardrobe.category.\(option?.rawValue ?? "costume")")
    }

    private var catalogItems: [WardrobeItem] { WardrobeItem.allCases.filter { $0.category == category } }
    private var equippedItem: WardrobeItem? {
        store.state.equippedItems.first { $0.category == category }
    }
    private var currentStyleName: String {
        var names = store.state.currentCostume.map { [$0.name] } ?? []
        if store.state.equippedOutfit != .basic { names.append(store.state.equippedOutfit.name) }
        names += store.state.equippedItems.map(\.name)
        return names.isEmpty ? Outfit.basic.name : names.joined(separator: " · ")
    }
    private var costumes: [CharacterCostume] {
        CostumeStyle.allCases.map { CharacterCostume(character: store.state.preferences.character, style: $0) }
    }
    private var catalogCount: Int {
        category == nil ? costumes.count : category == .top ? Outfit.allCases.count : catalogItems.count
    }
    private var ownedCount: Int {
        category == nil ? costumes.filter(store.state.ownedCostumes.contains).count
            : category == .top ? store.state.ownedOutfits.count : catalogItems.filter(store.state.ownedItems.contains).count
    }

    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : category == nil ? Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
            : [GridItem(.adaptive(minimum: 144, maximum: 220), spacing: 12)]
    }

    private func costumeCard(_ costume: CharacterCostume) -> some View {
        let owned = store.state.ownedCostumes.contains(costume)
        let equipped = store.state.currentCostume == costume.style
        return Button {
            if owned { Task { await store.update { try $0.equipCostume(costume) } } }
            else { pendingPurchase = .costume(costume) }
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(Color.repickRewardSurface)
                    if let image = costumePreviews[costume] {
                        Image(uiImage: image).resizable().scaledToFit()
                            .padding(3)
                    } else if failedPreviews.contains(costume) {
                        Image(systemName: "photo.badge.exclamationmark")
                            .foregroundStyle(Color.repickSecondaryText)
                    } else {
                        ProgressView()
                    }
                    if !owned {
                        RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.28))
                        Image(systemName: "lock.fill")
                            .font(AppFont.font(.body, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(height: dynamicTypeSize.isAccessibilitySize ? 180 : 106)
                .shadow(color: Color.repickInk.opacity(0.12), radius: 3, y: 3)
                .accessibilityIdentifier("wardrobe.costume.preview.\(costume.id)")
                .accessibilityHidden(true)
                Text("\(costume.character.name) \(costume.name)")
                    .font(AppFont.font(.caption2, weight: .medium))
                    .foregroundStyle(Color.repickInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(equipped ? "착용 중" : owned ? "보유" : "\(costume.price)P")
                    .font(AppFont.font(.caption2))
                    .foregroundStyle(Color.repickSecondaryText)
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(Color.repickSurface, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(equipped ? Color.repickGold : .clear, lineWidth: 1.5)
            }
            .overlay(alignment: .topTrailing) {
                if equipped {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.repickGold, Color.repickSurface)
                        .padding(6)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(equipped || store.isSaving || store.state.profile == nil)
        .accessibilityLabel("\(costume.character.name) \(costume.name)")
        .accessibilityValue(equipped ? Text("착용 중") : owned ? Text("보유") : Text("잠김"))
        .accessibilityHint(owned ? Text("현재 캐릭터에 착용합니다.") : Text("\(costume.price)포인트 구매 정보를 확인합니다."))
        .accessibilityIdentifier("wardrobe.costume.\(costume.id)")
    }

    @MainActor
    private func loadCostumePreviews() async {
        for costume in costumes where costumePreviews[costume] == nil {
            guard !Task.isCancelled else { return }
            if let image = UsagiSnapshotRenderer.renderCostume(character: costume.character, costume: costume.style,
                                                               size: CGSize(width: 240, height: 280)) {
                costumePreviews[costume] = image
                failedPreviews.remove(costume)
            } else {
                failedPreviews.insert(costume)
            }
            await Task.yield()
        }
    }

    private var drawSection: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("코스튬 뽑기").font(AppFont.font(.headline))
                    Spacer(minLength: 8)
                    if store.state.profile != nil {
                        Text("오늘 포인트 뽑기 \(store.state.daily.maximumDraws - store.state.daily.draws)회 남음")
                            .font(AppFont.font(.subheadline)).foregroundStyle(Color.repickSecondaryText)
                    }
                }
                Text("무료 뽑기 \(store.state.freeDraws)회")
                    .font(AppFont.font(.subheadline, weight: .semibold))
                    .foregroundStyle(Color.repickInk)
                    .accessibilityIdentifier("wardrobe.freeDraws")
                Text(store.state.freeDraws > 0
                     ? "무료 기회 1회를 먼저 사용합니다."
                     : "무료 기회가 없어 100P를 사용합니다.")
                    .font(AppFont.font(.subheadline))
                    .foregroundStyle(Color.repickSecondaryText)
                    .accessibilityIdentifier("wardrobe.drawPayment")
                if let reason = drawUnavailableReason {
                    Text(reason).font(AppFont.font(.subheadline)).foregroundStyle(Color.repickSecondaryText)
                        .accessibilityIdentifier("wardrobe.drawReason")
                }
                Button(store.state.freeDraws > 0 ? "무료로 토쿠볼 열기" : "100P로 토쿠볼 열기", action: openGacha)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(drawUnavailableReason != nil || store.isSaving)
                    .accessibilityIdentifier("wardrobe.draw")
                DisclosureGroup("확률과 중복 보상") {
                    Text("현재 캐릭터의 인어섬·파자마·갸루는 각각 1/3 확률입니다. 중복 의상을 뽑으면 50P를 돌려받습니다.")
                        .font(AppFont.font(.footnote)).foregroundStyle(Color.repickSecondaryText)
                        .padding(.top, 4)
                }
                .font(AppFont.font(.subheadline))
                .tint(.repickGreen)
            }
        }
    }

    private var drawUnavailableReason: String? {
        if store.state.profile == nil { return String(localized: "프로필을 먼저 등록하세요.") }
        if store.state.freeDraws > 0 { return nil }
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
                         character: store.state.preferences.character, equippedItems: store.state.equippedItems,
                         muscleLevel: store.state.muscleLevel, fieryEyes: store.state.attendanceNeedsAttention,
                         costume: store.state.currentCostume)
                .frame(height: 120)
                .clipped()
                .accessibilityHidden(true)
            Text(outfit.name).font(AppFont.font(.subheadline, weight: .semibold))
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
                         character: store.state.preferences.character, equippedItems: previewItems,
                         muscleLevel: store.state.muscleLevel, fieryEyes: store.state.attendanceNeedsAttention,
                         costume: store.state.currentCostume)
                .frame(height: 120)
                .clipped()
                .accessibilityHidden(true)
            Text(item.name).font(AppFont.font(.subheadline, weight: .semibold))
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

    private func openGacha() {
        guard drawUnavailableReason == nil, !store.isSaving else { return }
        gachaEntry = GachaEntry(payment: store.state.freeDraws > 0 ? .free : .points,
                                character: store.state.preferences.character)
    }
}

private struct GachaEntry: Identifiable {
    let id = UUID()
    let randomIndex = Int.random(in: CostumeStyle.allCases.indices)
    let payment: GachaPayment
    let character: CharacterKind
}

private enum WardrobePurchase {
    case costume(CharacterCostume)
    case top(Outfit)
    case item(WardrobeItem)

    var name: String {
        switch self {
        case .costume(let costume): "\(costume.character.name) \(costume.name)"
        case .top(let outfit): outfit.name
        case .item(let item): item.name
        }
    }

    var price: Int {
        switch self {
        case .costume(let costume): costume.price
        case .top(let outfit): outfit.price
        case .item(let item): item.price
        }
    }
}

private struct WardrobeShareButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.font(.body, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(Color.repickInk)
            .background(LinearGradient(colors: [.repickSurface, .repickCream, .repickYellow.opacity(0.6)],
                                       startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(Color.repickBorder, lineWidth: 1) }
            .shadow(color: Color.repickInk.opacity(0.14), radius: 2, y: 3)
            .opacity(!isEnabled ? 0.5 : configuration.isPressed ? 0.8 : 1)
    }
}

private struct OutfitButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let owned: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.font(.subheadline, weight: .semibold))
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
