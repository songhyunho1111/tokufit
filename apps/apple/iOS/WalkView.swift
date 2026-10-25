import SwiftUI
import MapKit
import CoreLocation
import REPickShared

struct WalkView: View {
    @Environment(UsagiStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let steps: StepTracker
    @State private var location = LocationTracker()
    @State private var camera: MapCameraPosition = .automatic
    @State private var cameraHeading = 0.0
    @State private var cameraDistance = 800.0
    @State private var visibleCameraDistance = 800.0
    @State private var followsUsagi = true
    @State private var activeSheet: WalkSheet?
    @State private var destination: WalkingDestination?
    @State private var isOpeningDirections = false
    @State private var showsDirectionsError = false

    private var isWalkingSession: Bool { store.state.activeWorkout?.mode == .outdoor }

    private enum WalkSheet: Identifiable {
        case workout, destination
        case completion(WorkoutSession, Date)
        var id: String {
            switch self {
            case .workout: "workout"
            case .destination: "destination"
            case .completion(let session, _): session.id.uuidString
            }
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            mapContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if !isWalkingSession {
                startPanel.frame(maxWidth: 560).padding(.horizontal, Design.pagePadding).padding(.bottom, 12)
            }
        }
        .clipped()
        .background(Color.repickCream.ignoresSafeArea())
        .ignoresSafeArea(edges: isWalkingSession ? [.top, .bottom] : [])
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isWalkingSession {
                HStack {
                    Spacer()
                    Button { activeSheet = .workout } label: {
                        Image(systemName: "ellipsis").font(.title2.bold())
                            .frame(width: 54, height: 54)
                            .background(.regularMaterial, in: Circle())
                    }
                    .accessibilityLabel("운동 메뉴")
                    .accessibilityIdentifier("workout.menu")
                }.padding(.horizontal, 22).padding(.bottom, 12)
            }
        }
        .toolbarBackground(Color.repickCream, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbar(isWalkingSession ? .hidden : .visible, for: .tabBar)
        .sheet(item: $activeSheet, onDismiss: resumeLocation) { sheet in
            switch sheet {
            case .workout: workoutMenu
            case .destination:
                DestinationSearchView(origin: location.coordinate, onSelect: selectDestination)
            case .completion(let session, let endedAt):
                WorkoutCompletionView(session: session, endedAt: endedAt)
            }
        }
        .alert("길찾기를 열지 못했어요", isPresented: $showsDirectionsError) {
            Button("다시 시도", action: openDirections)
            Button("취소", role: .cancel) { }
        } message: {
            Text("Apple 지도 앱을 확인한 뒤 다시 시도해 주세요.")
        }
        .onChange(of: location.coordinate.map { [$0.latitude, $0.longitude] }) { old, _ in
            if old == nil || followsUsagi { recenter() }
        }
        .onChange(of: location.heading) { _, _ in
            if isWalkingSession && followsUsagi { recenter() }
        }
        .onChange(of: location.authorization) { _, authorization in
            if authorization == .denied || authorization == .restricted {
                location.stop()
                if isWalkingSession { activeSheet = .workout }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { location.stop() }
            else { resumeLocation() }
        }
        .onChange(of: store.state.activeWorkout?.id) { _, _ in
            if isWalkingSession { resumeLocation() }
            else { location.stop(); activeSheet = nil }
        }
        .onDisappear { location.stop() }
        .onAppear(perform: resumeLocation)
    }

    private var mapContent: some View {
        Map(position: $camera) {
            if let destination {
                Marker(destination.name, systemImage: "flag.fill", coordinate: destination.coordinate)
                    .tint(Color.repickGreen)
            }
            if let coordinate = location.coordinate {
                Annotation(store.state.preferences.name, coordinate: coordinate, anchor: .bottom) {
                    MapUsagiView(bodyScale: store.state.bodyScale, outfit: store.state.equippedOutfit,
                                 isWalking: location.isWalking, heading: location.heading ?? 0,
                                 cameraHeading: cameraHeading,
                                 character: store.state.preferences.character, equippedItems: store.state.equippedItems)
                        .frame(width: 100 * avatarZoomScale, height: 130 * avatarZoomScale)
                        .accessibilityLabel("지도 위 \(store.state.preferences.name)")
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .mapControls {
            if !isWalkingSession { MapCompass(); MapScaleView() }
        }
        .onMapCameraChange(frequency: .continuous) { context in
            cameraHeading = context.camera.heading
            if context.camera.distance.isFinite && context.camera.distance > 0 {
                visibleCameraDistance = context.camera.distance
            }
            if camera.positionedByUser {
                followsUsagi = false
                cameraDistance = context.camera.distance
            }
        }
        .overlay {
            if location.coordinate == nil && isWalkingSession {
                Group {
                    if location.authorization == .denied || location.authorization == .restricted {
                        Label("위치 접근을 허용해 주세요", systemImage: "location.slash")
                    } else { ProgressView("GPS 수신 중") }
                }.padding(16).background(.regularMaterial, in: Capsule())
            }
        }
    }


    private var startPanel: some View {
        ViewThatFits(in: .vertical) {
            startPanelContent
            ScrollView { startPanelContent }
        }
        .frame(maxWidth: .infinity)
        .modifier(StartPanelGlass())
    }

    private var startPanelContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            destinationControls
            Divider()
            HStack {
                Label("\(store.state.daily.steps.formatted())보", systemImage: "shoeprints.fill")
                    .font(.title3.weight(.semibold)).monospacedDigit()
                Spacer()
                Text("목표 \(store.state.daily.goalSteps.formatted())보").font(.subheadline).foregroundStyle(Color.repickSecondaryText)
            }
            HStack(spacing: 12) {
                Text(location.status).font(.footnote).foregroundStyle(Color.repickSecondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    cameraDistance = visibleCameraDistance
                    followsUsagi = true
                    recenter()
                } label: {
                    Image(systemName: "location.fill").frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("현재 위치로 이동")
                .disabled(location.coordinate == nil)
            }
            Button("야외 운동 시작", action: startWalk)
                .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("walk.start")
                .disabled(store.isSaving || store.state.profile == nil)
            if location.authorization == .denied || location.authorization == .restricted {
                Button("위치 권한 설정 열기") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }.font(.subheadline).frame(minHeight: 44)
            }
            Text("앱 사용 중에만 위치를 표시합니다.").font(.footnote).foregroundStyle(Color.repickSecondaryText)
        }
        .padding(Design.cardPadding)
    }

    private var destinationControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Button { activeSheet = .destination } label: {
                    HStack(spacing: 10) {
                        Image(systemName: destination == nil ? "magnifyingglass" : "mappin.circle.fill")
                        VStack(alignment: .leading, spacing: 3) {
                            Text(destination?.name ?? String(localized: "목적지 검색"))
                                .font(.body.weight(.semibold))
                                .lineLimit(2)
                            if let destination, !destination.address.isEmpty {
                                Text(destination.address).font(.caption)
                                    .foregroundStyle(Color.repickSecondaryText).lineLimit(2)
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("walk.destination")
                if destination != nil {
                    Button { destination = nil } label: {
                        Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.repickSecondaryText)
                    .accessibilityLabel("목적지 지우기")
                    .accessibilityIdentifier("walk.clearDestination")
                }
            }
            if destination != nil {
                Button(action: openDirections) {
                    HStack(spacing: 8) {
                        Label("Apple 지도에서 길찾기", systemImage: "arrow.triangle.turn.up.right.diamond")
                        if isOpeningDirections { ProgressView() }
                    }.frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(isOpeningDirections)
                .accessibilityIdentifier("walk.openDirections")
                Text("길 안내는 Apple 지도에서 진행됩니다.")
                    .font(.footnote).foregroundStyle(Color.repickSecondaryText)
            }
        }
    }

    private func selectDestination(_ result: WalkingDestination) {
        destination = result
        activeSheet = nil
        if !isWalkingSession {
            followsUsagi = false
            camera = .region(MKCoordinateRegion(center: result.coordinate, latitudinalMeters: 1_200, longitudinalMeters: 1_200))
        }
    }

    private func openDirections() {
        guard let destination, !isOpeningDirections else { return }
        isOpeningDirections = true
        activeSheet = nil
        Task { @MainActor in
            defer { isOpeningDirections = false }
            let opened = await MKMapItem.openMaps(with: [.forCurrentLocation(), destination.mapItem],
                                                  launchOptions: destination.walkingLaunchOptions, from: nil)
            if !opened { showsDirectionsError = true }
        }
    }

    private var workoutMenu: some View {
        NavigationStack {
            List {
                Section {
                    destinationControls
                } header: { Text("목적지") }
                Section {
                    if let session = store.state.activeWorkout {
                        HStack {
                            Text("운동 시간")
                            Spacer()
                            Text(session.startedAt, style: .timer).monospacedDigit()
                        }
                    }
                    LabeledContent("오늘 걸음 수", value: "\(store.state.daily.steps.formatted())보")
                    LabeledContent("목표", value: "\(store.state.daily.goalSteps.formatted())보")
                    Text(location.status).font(.footnote).foregroundStyle(Color.repickSecondaryText)
                    if !location.isTracking {
                        Button("위치 다시 연결") { location.start() }
                    }
                    if location.authorization == .denied || location.authorization == .restricted {
                        Button("위치 권한 설정 열기") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                    }
                }
                Section {
                    Button("위치와 방향 따라가기", systemImage: "location.north.line.fill") {
                        cameraDistance = visibleCameraDistance
                        followsUsagi = true
                        recenter()
                        activeSheet = nil
                    }
                    .accessibilityIdentifier("walk.follow")
                    Button("운동 완료", action: endWalk)
                        .accessibilityIdentifier("workout.end")
                }
            }
            .navigationTitle("야외 운동").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { activeSheet = nil } } }
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }

    private func startWalk() {
        guard location.authorization != .denied,
              location.authorization != .restricted else { location.start(); return }
        Task {
            if await store.update({ try $0.startWorkout(mode: .outdoor) }) {
                followsUsagi = true
                cameraDistance = 450
                steps.start()
                location.start()
                recenter()
            }
        }
    }

    private func endWalk() {
        cameraDistance = visibleCameraDistance
        location.stop()
        guard let session = store.state.activeWorkout else { return }
        activeSheet = .completion(session, Date())
    }

    private func resumeLocation() {
        guard isWalkingSession, scenePhase == .active else { return }
        if case .completion = activeSheet { return }
        steps.start()
        location.start()
    }

    private var avatarZoomScale: Double {
        min(2.2, max(0.16, 450 / visibleCameraDistance))
    }

    private func recenter() {
        guard let coordinate = location.coordinate else { return }
        let heading = location.heading ?? cameraHeading
        var target = MKMapPoint(coordinate)
        if isWalkingSession {
            // Look ahead geographically so the avatar stays at its actual GPS coordinate.
            let offset = cameraDistance * 0.22 / MKMetersPerMapPointAtLatitude(coordinate.latitude)
            let bearing = heading * .pi / 180
            target.x += sin(bearing) * offset
            target.y -= cos(bearing) * offset
        }
        let next = MapCameraPosition.camera(MapCamera(centerCoordinate: target.coordinate, distance: cameraDistance,
                                                      heading: heading, pitch: isWalkingSession ? 60 : 45))
        withAnimation(reduceMotion ? nil : .linear(duration: 0.6)) {
            camera = next
        }
    }
}


private struct StartPanelGlass: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color.repickCream, in: RoundedRectangle(cornerRadius: 24))
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        }
    }
}
