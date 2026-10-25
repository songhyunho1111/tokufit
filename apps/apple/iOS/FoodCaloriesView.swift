import PhotosUI
import REPickShared
import SwiftUI

struct FoodCaloriesView: View {
    let isSelected: Bool
    var onClose: () -> Void = {}
    @Environment(UsagiStore.self) private var store
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("apiBaseURL") private var configuredURL = ""
    @State private var model = FoodCaloriesModel()
    @State private var camera = FoodCameraController()
    @State private var selectedPhoto: PhotosPickerItem?
    @FocusState private var focusedField: String?

    private var baseURL: String {
        configuredURL.isEmpty ? Bundle.main.object(forInfoDictionaryKey: "REPickAPIBaseURL") as? String ?? "" : configuredURL
    }

    private var cameraShouldRun: Bool {
        isSelected && scenePhase == .active && model.stage == .capture && !model.isImporting
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollViewReader { scroll in
                    ScrollView {
                        VStack(spacing: 18) {
                            header
                            if model.stage != .saved { mealSelector }
                            if model.isImporting {
                                HStack {
                                    ProgressView("사진 준비 중")
                                    Spacer()
                                    Button("취소") { model.cancelPending() }
                                }
                                .padding(.vertical, 36)
                            } else {
                                content(previewHeight: min(427, max(240, geometry.size.height - 300)))
                            }
                            if let message = model.errorMessage {
                                Text(message)
                                    .font(AppFont.font(.subheadline)).foregroundStyle(Color.repickDanger)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .accessibilityIdentifier("food.status")
                            }
                        }
                        .padding(.horizontal, Design.pagePadding)
                        .padding(.vertical, 12)
                        .frame(width: min(geometry.size.width, Design.contentWidth))
                        .frame(maxWidth: .infinity)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        if [.capture, .preview].contains(model.stage), !model.isImporting {
                            captureControls
                                .padding(.horizontal, Design.pagePadding)
                                .padding(.vertical, 12)
                                .frame(maxWidth: Design.contentWidth)
                                .frame(maxWidth: .infinity)
                                .background(Color.repickCream)
                        }
                    }
                    .background(Color.repickCream)
                    .foregroundStyle(Color.repickInk)
                    .toolbar(.hidden, for: .navigationBar)
                    .toolbar(.hidden, for: .tabBar)
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("완료") { focusedField = nil }
                                .accessibilityIdentifier("food.keyboardDone")
                        }
                    }
                    .onChange(of: selectedPhoto) { _, item in
                        guard let item else { return }
                        camera.stop()
                        model.importPhoto(item)
                        selectedPhoto = nil
                    }
                    .onAppear { model.setActive(isSelected) }
                    .onChange(of: isSelected) { _, selected in
                        model.setActive(selected)
                        if !selected { camera.stop(); focusedField = nil }
                    }
                    .task(id: cameraShouldRun) {
                        if cameraShouldRun { await camera.start() }
                        else { camera.stop() }
                    }
                    .onDisappear { camera.stop() }
                    .onChange(of: focusedField) { _, field in
                        guard let field else { return }
                        withAnimation(.easeOut(duration: 0.2)) { scroll.scrollTo(field, anchor: .top) }
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                focusedField = nil
                camera.stop()
                model.cancelPending()
                if model.stage == .saved { model.reset() }
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 19, weight: .medium))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("식단 기록 닫기")
            .accessibilityIdentifier("food.close")
            .disabled(model.isSaving)
            Spacer(minLength: 0)
            Text(model.stage == .review ? String(localized: "영양정보 확인") : String(localized: "식단 기록"))
                .font(AppFont.font(.title2, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if model.stage == .capture {
                Button { camera.toggleFlash() } label: {
                    Image(systemName: camera.isFlashEnabled ? "bolt.fill" : "bolt")
                        .font(.system(size: 19, weight: .medium))
                        .frame(width: 44, height: 44)
                        .background(Color.repickRewardSurface, in: Circle())
                }
                .disabled(!camera.isFlashAvailable || camera.isCapturing)
                .accessibilityLabel("카메라 플래시")
                .accessibilityValue(camera.isFlashAvailable ? (camera.isFlashEnabled ? "켜짐" : "꺼짐") : "사용할 수 없음")
                .accessibilityIdentifier("food.flash")
            } else if [.preview, .confirmation, .review].contains(model.stage) {
                Button { focusedField = nil; model.back() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 19, weight: .medium))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("이전")
                .accessibilityIdentifier("food.back")
                .disabled(model.isSaving)
            } else { Color.clear.frame(width: 44, height: 44).accessibilityHidden(true) }
        }
        .buttonStyle(.plain)
    }

    private var mealSelector: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 6))
            : AnyLayout(HStackLayout(spacing: 14))
        return layout {
            ForEach(MealKind.allCases) { kind in
                Button { model.selectMealKind(kind) } label: {
                    Text(kind.name)
                        .font(AppFont.font(.subheadline))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(model.selectedMealKind == kind ? Color.repickYellow : Color.repickSurface, in: Capsule())
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(model.selectedMealKind == kind ? .isSelected : [])
                .accessibilityIdentifier("food.mealKind.\(kind.rawValue)")
            }
        }
        .disabled(model.isImporting || model.isAnalyzing || model.isSaving || camera.isCapturing)
    }

    @ViewBuilder
    private func content(previewHeight: CGFloat) -> some View {
        switch model.stage {
        case .capture, .preview: captureContent(previewHeight: previewHeight)
        case .confirmation: confirmationContent
        case .review: reviewContent
        case .saved: savedContent
        }
    }

    private func captureContent(previewHeight: CGFloat) -> some View {
        VStack(spacing: 18) {
            cameraFrame(height: previewHeight)
            HStack(spacing: 12) {
                Image("FoodMascot").resizable().scaledToFit().frame(width: 53, height: 56)
                    .accessibilityHidden(true)
                Text("음식이 네모 안에 다 들어오게 찍어줘.\n내가 뭔지 맞춰볼게!")
                    .font(AppFont.font(.footnote))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .foregroundStyle(Color(red: 0.23, green: 0.19, blue: 0.13))
            .background(.white, in: RoundedRectangle(cornerRadius: 18))

            if model.stage == .preview {
                Text("제출하면 선택한 사진을 분석 서버와 AI 서비스로 전송해 음식과 영양정보를 추정해요. 분석 서버는 사진을 보관하지 않아요.")
                    .font(AppFont.font(.caption)).foregroundStyle(Color.repickSecondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if model.isAnalyzing {
                HStack {
                    ProgressView("음식 분석 중…")
                    Spacer()
                    Button("취소") { model.cancelPending() }
                        .accessibilityIdentifier("food.cancelAnalysis")
                }
                .font(AppFont.font(.subheadline))
            }
        }
    }

    private func cameraFrame(height: CGFloat) -> some View {
        Color.repickSurface.overlay {
            if let data = model.photo?.jpegData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit()
                    .accessibilityLabel("선택한 음식 사진")
                    .accessibilityIdentifier("food.preview")
            } else if camera.status == .ready {
                FoodCameraPreview(controller: camera)
                    .accessibilityLabel("실시간 음식 카메라")
                    .accessibilityIdentifier("food.cameraPreview")
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "camera")
                        .font(.system(size: 38, weight: .light))
                    if camera.status == .starting {
                        ProgressView("카메라 준비 중")
                    } else {
                        Text(camera.errorMessage ?? String(localized: "음식을 촬영하거나 사진 보관함에서 골라 주세요."))
                            .font(AppFont.font(.subheadline))
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("food.cameraStatus")
                        if camera.status == .denied {
                            Button("카메라 권한 설정 열기") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }
                    }
                }
                .padding(38)
            }
        }
        .overlay {
            FoodFramingGuides()
                .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .padding(22)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        .frame(height: dynamicTypeSize.isAccessibilitySize ? 300 : height)
        .clipShape(RoundedRectangle(cornerRadius: 30))
    }

    private var captureControls: some View {
        HStack(spacing: 24) {
            PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(Color.repickSurface)
                    if let data = model.photo?.jpegData, let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        Image(systemName: "photo.on.rectangle").font(.system(size: 24, weight: .regular))
                    }
                }
                .frame(width: 54, height: 54).clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Color.repickGold, lineWidth: 1.5) }
            }
            .accessibilityLabel("사진 보관함에서 선택")
            .accessibilityIdentifier("food.library")
            .disabled(model.isAnalyzing || camera.isCapturing)
            Spacer(minLength: 0)
            Button(action: takePhoto) {
                ZStack {
                    Circle().fill(Color.repickInk)
                    Circle().fill(Color.repickCream).padding(5)
                    Circle().fill(Color.repickInk).padding(11)
                    if camera.isCapturing { ProgressView().tint(Color.repickCream) }
                }
                .frame(width: 80, height: 80)
            }
            .accessibilityLabel(model.stage == .preview ? "다시 촬영하기" : "음식 촬영하기")
            .accessibilityIdentifier("food.camera")
            .disabled(model.isAnalyzing || camera.isCapturing || camera.status == .starting)
            Spacer(minLength: 0)
            Button("제출") { camera.stop(); model.analyze(baseURL: baseURL) }
                .font(AppFont.font(.subheadline))
                .frame(minWidth: 58, minHeight: 50)
                .foregroundStyle(Color.repickActionInk)
                .background(Color.repickYellow, in: Capsule())
                .overlay { Capsule().strokeBorder(Color.repickGold.opacity(0.45), lineWidth: 1) }
                .opacity(model.stage == .preview && !model.isAnalyzing ? 1 : 0.45)
                .accessibilityIdentifier("food.analyze")
                .disabled(model.stage != .preview || model.isAnalyzing || camera.isCapturing)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    private var confirmationContent: some View {
        VStack(spacing: 24) {
            if let food = model.displayedFood {
                VStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Circle().fill(Color.repickGold).frame(width: 7, height: 7)
                        Text(model.isDraftEdited ? "직접 확인 · \(food.name)" : "AI 인식 · \(food.name)")
                            .font(AppFont.font(.footnote, weight: .bold))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.repickSurface, in: Capsule())
                    .accessibilityIdentifier("food.recognition")
                    Image("FoodBowl").resizable().scaledToFit().frame(width: 208, height: 160)
                        .accessibilityHidden(true)
                }
                .padding(.vertical, 12)
            }
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .center, spacing: 16) {
                    Image("FoodMascot").resizable().scaledToFit().frame(width: 55, height: 58)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        if let food = model.displayedFood {
                            Text("이 음식, \(food.name) 맞아?")
                                .font(AppFont.font(.title3))
                            Text("\(food.portion) 기준으로 봤어")
                                .font(AppFont.font(.subheadline)).foregroundStyle(Color.repickSecondaryText)
                        } else {
                            Text(model.selectedFood == nil ? "음식을 확인하지 못했어요" : "수정한 영양정보를 확인해 주세요")
                                .font(AppFont.font(.title3))
                            Text(model.analysis?.message ?? "")
                                .font(AppFont.font(.subheadline)).foregroundStyle(Color.repickSecondaryText)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color.repickCream, in: RoundedRectangle(cornerRadius: 20))
                    .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(Color.repickBorder, lineWidth: 1) }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("위 음식이 아니라면?")
                        .font(AppFont.font(.subheadline)).foregroundStyle(Color.repickSecondaryText)
                    ScrollView(.horizontal) {
                        HStack(spacing: 9) {
                            ForEach(Array(model.foodCandidates.enumerated()), id: \.offset) { index, food in
                                if index != model.selectedCandidateIndex {
                                    Button(food.name) { model.selectCandidate(index) }
                                        .accessibilityIdentifier("food.candidate.\(index)")
                                }
                            }
                            Button("직접입력") { model.confirmFood() }
                                .accessibilityIdentifier("food.directInput")
                        }
                        .buttonStyle(FoodAlternativeStyle())
                    }
                    .scrollIndicators(.hidden)
                }
                if let food = model.displayedFood {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("추정된 열량").font(AppFont.font(.subheadline)).foregroundStyle(Color.repickSecondaryText)
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("약 \(food.calories)").font(AppFont.font(.largeTitle, weight: .bold))
                                .accessibilityIdentifier("food.estimatedCalories")
                            Text("kcal").font(AppFont.font(.body)).foregroundStyle(Color.repickSecondaryText)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 94, alignment: .topLeading)
                    .padding(20)
                    .background(Color.repickSurface, in: RoundedRectangle(cornerRadius: 20))
                    .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(Color.repickBorder, lineWidth: 1) }
                    Button {
                        model.register(in: store)
                    } label: {
                        HStack {
                            if model.isSaving { ProgressView() }
                            Text(model.isSaving ? String(localized: "기록 저장 중…") : String(localized: "기록 등록하기"))
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("food.confirm")
                }
                Text("사진으로 추정한 값이에요. 먹은 양과 영양정보는 직접입력에서 확인하고 수정할 수 있어요.")
                    .font(AppFont.font(.caption)).foregroundStyle(Color.repickSecondaryText)
            }
            .padding(20)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 30))
            .foregroundStyle(Color(red: 0.23, green: 0.19, blue: 0.13))
            .environment(\.colorScheme, .light)
            .disabled(model.isSaving)
        }
    }
    private var reviewContent: some View {
        VStack(alignment: .leading, spacing: Design.sectionSpacing) {
            Text("먹은 양에 맞게 수정해 주세요")
                .font(AppFont.font(.title2, weight: .bold))
            Text(model.selectedFood == nil ? "음식 이름, 먹은 양과 영양정보를 직접 입력해 주세요." : "사진에서 추정한 값이에요. 포장지의 영양정보나 실제 먹은 양을 확인해 주세요.")
                .font(AppFont.font(.subheadline)).foregroundStyle(Color.repickSecondaryText)
            PaperCard {
                VStack(spacing: 16) {
                    textField("음식 이름", text: draftBinding(\.name), id: "food.name")
                    Divider()
                    textField("먹은 양", text: draftBinding(\.portion), id: "food.portion")
                }
            }
            PaperCard {
                VStack(spacing: 16) {
                    numberField("칼로리", text: draftBinding(\.calories), unit: "kcal", id: "food.calories", keyboard: .numberPad)
                    Divider()
                    numberField("탄수화물", text: draftBinding(\.carbohydrates), unit: "g", id: "food.carbs")
                    numberField("단백질", text: draftBinding(\.protein), unit: "g", id: "food.protein")
                    numberField("지방", text: draftBinding(\.fat), unit: "g", id: "food.fat")
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                if let energy = model.draft?.macroEnergy {
                    Text("영양소로 계산한 열량 \(energy.formatted(.number.precision(.fractionLength(0...1)))) kcal")
                        .font(AppFont.font(.subheadline, weight: .semibold))
                        .accessibilityIdentifier("food.macroEnergy")
                }
                Text("탄수화물 4 · 단백질 4 · 지방 9 kcal/g으로 계산해요. 식이섬유와 반올림 등으로 표시 칼로리와 차이가 날 수 있어요.")
                    .font(AppFont.font(.footnote)).foregroundStyle(Color.repickSecondaryText)
                if let notes = model.selectedFood?.notes, !notes.isEmpty {
                    Text(notes).font(AppFont.font(.footnote)).foregroundStyle(Color.repickSecondaryText)
                }
            }
            .padding(Design.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.repickRewardSurface, in: RoundedRectangle(cornerRadius: Design.controlRadius))
            Button {
                focusedField = nil
                model.register(in: store)
            } label: {
                HStack {
                    if model.isSaving { ProgressView().tint(Color.repickActionInk) }
                    Text(model.isSaving ? "기록 저장 중…" : "이 내용으로 등록하기")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("food.register")
        }
        .disabled(model.isSaving)
    }

    private var savedContent: some View {
        VStack(spacing: Design.sectionSpacing) {
            MapUsagiView(bodyScale: store.state.bodyScale, outfit: store.state.equippedOutfit,
                         heading: 180, motion: .eating, isAnimating: isSelected,
                         accessibilityIdentifier: "food.usagi", character: store.state.preferences.character,
                         equippedItems: store.state.equippedItems,
                         eatingStyle: model.eatingStyle, muscleLevel: store.state.muscleLevel,
                         fieryEyes: store.state.attendanceNeedsAttention, nutritionMood: store.state.nutritionMood,
                         costume: store.state.currentCostume)
                .frame(height: 300)
                .frame(maxWidth: .infinity)
                .background(Color.repickRewardSurface, in: RoundedRectangle(cornerRadius: Design.cardRadius))
            Text("푸루(기록했어!)")
                .font(AppFont.font(.title, weight: .bold)).foregroundStyle(Color.repickGold)
                .accessibilityIdentifier("food.saved")
            Text("확인한 음식과 영양정보를 저장했어요.")
                .foregroundStyle(Color.repickSecondaryText)
            Button("완료") { model.reset() }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("food.done")
            Button("새 음식 촬영하기") { model.reset() }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("food.newPhoto")
        }
        .frame(maxWidth: .infinity)
    }

    private func draftBinding(_ keyPath: WritableKeyPath<FoodNutritionDraft, String>) -> Binding<String> {
        Binding(get: { model.draft?[keyPath: keyPath] ?? "" }, set: { model.draft?[keyPath: keyPath] = $0 })
    }

    private func textField(_ title: LocalizedStringKey, text: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(AppFont.font(.subheadline, weight: .semibold)).foregroundStyle(Color.repickSecondaryText)
            TextField(title, text: text)
                .focused($focusedField, equals: id)
                .frame(minHeight: Design.controlHeight)
                .accessibilityIdentifier(id)
        }
        .id(id)
    }

    private func numberField(_ title: LocalizedStringKey, text: Binding<String>, unit: String,
                             id: String, keyboard: UIKeyboardType = .decimalPad) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                Text(title).fixedSize()
                Spacer()
                numericInput(title, text: text, unit: unit, id: id, keyboard: keyboard)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                numericInput(title, text: text, unit: unit, id: id, keyboard: keyboard)
            }
        }
        .frame(minHeight: Design.controlHeight)
        .id(id)
    }

    private func numericInput(_ title: LocalizedStringKey, text: Binding<String>, unit: String,
                              id: String, keyboard: UIKeyboardType) -> some View {
        HStack(spacing: 8) {
            TextField(title, text: text)
                .focused($focusedField, equals: id)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .accessibilityIdentifier(id)
            Text(unit).foregroundStyle(Color.repickSecondaryText)
        }
    }

    private func takePhoto() {
        if model.stage == .preview { model.reset(); return }
        let selectionID = model.beginPhotoSelection()
        let kind = model.selectedMealKind
        model.errorMessage = nil
        Task {
            if camera.status != .ready { await camera.start(); return }
            if let photo = await camera.capture(), model.selectionIsCurrent(selectionID) {
                model.acceptPhoto(photo, kind: kind)
                camera.stop()
            } else if model.selectionIsCurrent(selectionID) {
                model.errorMessage = camera.errorMessage
            }
        }
    }
}

private struct FoodAlternativeStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.font(.footnote))
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(Color.repickSurface.opacity(configuration.isPressed ? 0.7 : 1), in: Capsule())
            .overlay { Capsule().strokeBorder(Color.repickBorder, lineWidth: 1) }
    }
}

private struct FoodFramingGuides: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let arm = min(rect.width, rect.height) * 0.14
        for (x, y, dx, dy) in [
            (rect.minX, rect.minY, CGFloat(1), CGFloat(1)),
            (rect.maxX, rect.minY, CGFloat(-1), CGFloat(1)),
            (rect.minX, rect.maxY, CGFloat(1), CGFloat(-1)),
            (rect.maxX, rect.maxY, CGFloat(-1), CGFloat(-1))
        ] {
            path.move(to: CGPoint(x: x, y: y + dy * arm))
            path.addLine(to: CGPoint(x: x, y: y + dy * 12))
            path.addQuadCurve(to: CGPoint(x: x + dx * 12, y: y), control: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x + dx * arm, y: y))
        }
        return path
    }
}
