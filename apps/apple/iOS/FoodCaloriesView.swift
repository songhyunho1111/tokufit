import PhotosUI
import REPickShared
import SwiftUI

struct FoodCaloriesView: View {
    let isSelected: Bool
    @Environment(UsagiStore.self) private var store
    @Environment(\.openURL) private var openURL
    @AppStorage("apiBaseURL") private var configuredURL = ""
    @State private var model = FoodCaloriesModel()
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showsCamera = false
    @State private var cameraAccessDenied = false
    @State private var cameraRequest: Task<Void, Never>?
    @State private var cameraSelectionID = UUID()
    @FocusState private var focusedField: String?

    private var baseURL: String {
        configuredURL.isEmpty ? Bundle.main.object(forInfoDictionaryKey: "REPickAPIBaseURL") as? String ?? "" : configuredURL
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: Design.sectionSpacing) {
                        if model.isImporting {
                            HStack {
                                ProgressView("사진 준비 중")
                                Spacer()
                                Button("취소") { model.cancelPending() }
                            }
                        } else {
                            content
                        }
                        if let message = model.errorMessage {
                            Text(message)
                                .font(.subheadline).foregroundStyle(Color.repickDanger)
                                .accessibilityIdentifier("food.status")
                        }
                        if cameraAccessDenied {
                            Button("카메라 권한 설정 열기") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }
                    }
                    .padding(Design.pagePadding)
                    .frame(maxWidth: Design.contentWidth)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .background(Color.repickCream)
                .foregroundStyle(Color.repickInk)
                .navigationTitle(navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if [.preview, .confirmation, .review].contains(model.stage) {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("이전") { focusedField = nil; model.back() }
                                .disabled(model.isSaving)
                                .accessibilityIdentifier("food.back")
                        }
                    }
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("완료") { focusedField = nil }
                            .accessibilityIdentifier("food.keyboardDone")
                    }
                }
                .fullScreenCover(isPresented: $showsCamera) {
                    let selectionID = cameraSelectionID
                    FoodPhotoCapture { result in
                        guard model.selectionIsCurrent(selectionID) else { return }
                        showsCamera = false
                        switch result {
                        case .success(let photo): if let photo { model.acceptPhoto(photo) }
                        case .failure(let error): model.errorMessage = error.localizedDescription
                        }
                    }
                    .ignoresSafeArea()
                }
                .onChange(of: selectedPhoto) { _, item in
                    guard let item else { return }
                    cameraAccessDenied = false
                    model.importPhoto(item)
                    selectedPhoto = nil
                }
                .onAppear { model.setActive(isSelected) }
                .onChange(of: isSelected) { _, selected in
                    model.setActive(selected)
                    guard !selected else { return }
                    cameraRequest?.cancel()
                    showsCamera = false
                    focusedField = nil
                }
                .onChange(of: focusedField) { _, field in
                    guard let field else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        scroll.scrollTo(field, anchor: .top)
                    }
                }
            }
        }
    }

    private var navigationTitle: LocalizedStringKey {
        switch model.stage {
        case .review: "영양정보 확인"
        case .saved: "기록 완료"
        default: "음식 칼로리"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.stage {
        case .capture: captureContent
        case .preview: previewContent
        case .confirmation: confirmationContent
        case .review: reviewContent
        case .saved: savedContent
        }
    }

    private var captureContent: some View {
        VStack(alignment: .leading, spacing: Design.sectionSpacing) {
            PaperCard {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "fork.knife.circle")
                        .font(.system(size: 44, weight: .light)).foregroundStyle(Color.repickGreen)
                    Text("한 끼를 사진으로")
                        .font(.title2.bold())
                    Text("음식을 찍고, 칼로리와 영양정보를 확인해 기록해요.")
                        .foregroundStyle(Color.repickSecondaryText)
                    Text("음식과 양이 잘 보이도록 촬영해 주세요.")
                        .font(.subheadline).foregroundStyle(Color.repickGreen)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.repickRewardSurface, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            Button(action: openCamera) { Label("음식 촬영하기", systemImage: "camera") }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("food.camera")
            photoPicker
            Text("사진을 고른 뒤 분석 버튼을 눌러야 전송됩니다. 추정 결과는 직접 확인하고 수정할 수 있어요.")
                .font(.footnote).foregroundStyle(Color.repickSecondaryText)
        }
    }

    private var previewContent: some View {
        VStack(alignment: .leading, spacing: Design.sectionSpacing) {
            stepLabel("1 · 사진 확인")
            photoPreview
            PaperCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("이 사진으로 분석할까요?").font(.title3.bold())
                    Text("음식과 영양정보를 추정하기 위해 선택한 사진을 분석 서버와 AI 서비스로 전송합니다. 분석 서버는 사진을 보관하지 않습니다.")
                        .font(.subheadline).foregroundStyle(Color.repickSecondaryText)
                    Text("사진만으로 양과 조리법을 정확히 알기 어려워요. 결과를 확인한 뒤 등록해 주세요.")
                        .font(.footnote).foregroundStyle(Color.repickSecondaryText)
                }
            }
            if model.isAnalyzing {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("음식 분석 중…")
                    Spacer()
                    Button("취소") { model.cancelPending() }
                        .accessibilityIdentifier("food.cancelAnalysis")
                }
                .frame(minHeight: Design.controlHeight)
            } else {
                Button("사진 분석하기") { model.analyze(baseURL: baseURL) }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("food.analyze")
                retakeButton
            }
        }
    }

    private var confirmationContent: some View {
        VStack(alignment: .leading, spacing: Design.sectionSpacing) {
            stepLabel("2 · 음식 확인")
            photoPreview
            PaperCard {
                VStack(alignment: .leading, spacing: 12) {
                    if let food = model.analysis?.food {
                        Text("이 음식이 맞나요?").font(.title3.bold())
                        Text(food.name).font(.title2.bold()).foregroundStyle(Color.repickGreen)
                        Text(food.portion).font(.headline)
                    } else {
                        Label("음식을 확인하지 못했어요", systemImage: "questionmark.circle")
                            .font(.title3.bold())
                    }
                    if let message = model.analysis?.message {
                        Text(message).font(.subheadline).foregroundStyle(Color.repickSecondaryText)
                    }
                }
            }
            if model.analysis?.food != nil {
                Button("네, 영양정보 확인하기") { model.confirmFood() }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("food.confirm")
                Text("아직 기록되지 않았어요. 다음 화면에서 영양정보를 확인해 주세요.")
                    .font(.footnote).foregroundStyle(Color.repickSecondaryText)
            }
            retakeButton
        }
    }

    private var reviewContent: some View {
        VStack(alignment: .leading, spacing: Design.sectionSpacing) {
            stepLabel("3 · 확인 후 등록")
            Text("먹은 양에 맞게 수정해 주세요")
                .font(.title2.bold())
            Text("사진에서 추정한 값이에요. 포장지의 영양정보나 실제 먹은 양을 확인해 주세요.")
                .font(.subheadline).foregroundStyle(Color.repickSecondaryText)
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
                        .font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier("food.macroEnergy")
                }
                Text("탄수화물 4 · 단백질 4 · 지방 9 kcal/g으로 계산해요. 식이섬유와 반올림 등으로 표시 칼로리와 차이가 날 수 있어요.")
                    .font(.footnote).foregroundStyle(Color.repickSecondaryText)
                if let notes = model.analysis?.food?.notes, !notes.isEmpty {
                    Text(notes).font(.footnote).foregroundStyle(Color.repickSecondaryText)
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
            MapUsagiView(heading: 180, motion: .idle, isAnimating: isSelected,
                         accessibilityIdentifier: "food.usagi", reportReaction: .celebrate)
                .frame(height: 300)
                .frame(maxWidth: .infinity)
                .background(Color.repickRewardSurface, in: RoundedRectangle(cornerRadius: Design.cardRadius))
            Text("푸루(기록했어!)")
                .font(.title.bold()).foregroundStyle(Color.repickGreen)
                .accessibilityIdentifier("food.saved")
            Text("확인한 음식과 영양정보를 저장했어요.")
                .foregroundStyle(Color.repickSecondaryText)
            Button("완료") { model.reset() }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("food.done")
            Button("새 음식 촬영하기") { model.reset(); openCamera() }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("food.newPhoto")
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var photoPreview: some View {
        if let data = model.photo?.jpegData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable().scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 260)
                .clipShape(RoundedRectangle(cornerRadius: Design.cardRadius))
                .accessibilityIdentifier("food.preview")
        }
    }

    private var photoPicker: some View {
        PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
            Label("사진 보관함에서 선택", systemImage: "photo.on.rectangle")
        }
        .buttonStyle(SecondaryButtonStyle())
        .accessibilityIdentifier("food.library")
    }

    private var retakeButton: some View {
        Button("다시 촬영하거나 선택하기") { model.reset(); cameraAccessDenied = false }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("food.retake")
    }

    private func stepLabel(_ title: LocalizedStringKey) -> some View {
        Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.repickGreen)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Color.repickGreen.opacity(0.10), in: Capsule())
    }

    private func draftBinding(_ keyPath: WritableKeyPath<FoodNutritionDraft, String>) -> Binding<String> {
        Binding(get: { model.draft?[keyPath: keyPath] ?? "" }, set: { model.draft?[keyPath: keyPath] = $0 })
    }

    private func textField(_ title: LocalizedStringKey, text: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.repickSecondaryText)
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

    private func openCamera() {
        cameraRequest?.cancel()
        let selectionID = model.beginPhotoSelection()
        cameraSelectionID = selectionID
        model.errorMessage = nil
        cameraAccessDenied = false
        cameraRequest = Task {
            do {
                try await FoodPhotoCapture.requestAccess()
                try Task.checkCancellation()
                guard model.selectionIsCurrent(selectionID) else { return }
                showsCamera = true
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled, model.selectionIsCurrent(selectionID) else { return }
                if let photoError = error as? FoodPhotoError, case .cameraAccessDenied = photoError {
                    cameraAccessDenied = true
                }
                model.errorMessage = error.localizedDescription
            }
        }
    }
}
