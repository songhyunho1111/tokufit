import CoreLocation
import MapKit
import Observation
import SwiftUI

@MainActor
struct WalkingDestination: Identifiable {
    let id = UUID()
    let mapItem: MKMapItem
    let coordinate: CLLocationCoordinate2D
    let name: String
    let address: String

    init?(mapItem: MKMapItem) {
        guard !mapItem.isCurrentLocation else { return nil }
        let coordinate: CLLocationCoordinate2D
        let address: String
        if #available(iOS 26.0, *) {
            coordinate = mapItem.location.coordinate
            address = mapItem.address?.fullAddress ?? ""
        } else {
            coordinate = mapItem.placemark.coordinate
            address = mapItem.placemark.title ?? ""
        }
        guard CLLocationCoordinate2DIsValid(coordinate),
              coordinate.latitude.isFinite, coordinate.longitude.isFinite else { return nil }
        self.mapItem = mapItem
        self.coordinate = coordinate
        self.address = address
        let name = mapItem.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.name = name.isEmpty ? String(localized: "선택한 위치") : name
    }

    var walkingLaunchOptions: [String: Any] {
        [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking]
    }
}

@Observable @MainActor
final class DestinationSearchModel {
    private(set) var results: [WalkingDestination] = []
    private(set) var isSearching = false
    private(set) var hasSearched = false
    private(set) var errorMessage: String?
    @ObservationIgnored private var activeSearch: MKLocalSearch?
    @ObservationIgnored private var requestID = UUID()

    nonisolated static func normalizedQuery(_ query: String) -> String? {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return (1...120).contains(value.count) ? value : nil
    }

    nonisolated static func failureMessage(for error: any Error) -> String? {
        if (error as? MKError)?.code == .placemarkNotFound { return nil }
        return String(localized: "검색하지 못했어요. 잠시 후 다시 시도해 주세요.")
    }

    func search(_ query: String, near origin: CLLocationCoordinate2D?) async {
        cancel()
        let id = requestID
        results = []
        errorMessage = nil
        hasSearched = false
        guard let query = Self.normalizedQuery(query) else {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).count > 120 {
                errorMessage = String(localized: "장소나 주소를 120자 이내로 입력해 주세요.")
            }
            return
        }
        isSearching = true
        defer {
            if requestID == id { isSearching = false; activeSearch = nil }
        }
        do {
            try await Task.sleep(for: .milliseconds(350))
            guard requestID == id else { return }
            try Task.checkCancellation()
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.resultTypes = [.address, .pointOfInterest]
            if let origin, CLLocationCoordinate2DIsValid(origin) {
                request.region = MKCoordinateRegion(center: origin, latitudinalMeters: 20_000, longitudinalMeters: 20_000)
            }
            let search = MKLocalSearch(request: request)
            activeSearch = search
            let response = try await withTaskCancellationHandler {
                try await search.start()
            } onCancel: { [weak self] in
                Task { @MainActor [weak self] in self?.cancel(request: id) }
            }
            try Task.checkCancellation()
            guard requestID == id else { return }
            results = response.mapItems.compactMap(WalkingDestination.init(mapItem:))
            hasSearched = true
        } catch {
            guard requestID == id else { return }
            if error is CancellationError || Task.isCancelled { return }
            hasSearched = true
            errorMessage = Self.failureMessage(for: error)
        }
    }

    func cancel() {
        requestID = UUID()
        activeSearch?.cancel()
        activeSearch = nil
        isSearching = false
    }

    private func cancel(request id: UUID) {
        guard requestID == id else { return }
        cancel()
    }
}

struct DestinationSearchView: View {
    @Environment(\.dismiss) private var dismiss
    let origin: CLLocationCoordinate2D?
    let onSelect: (WalkingDestination) -> Void
    @State private var query = ""
    @State private var model = DestinationSearchModel()
    @FocusState private var isQueryFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if model.isSearching {
                    ProgressView("목적지 검색 중")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = model.errorMessage {
                    ContentUnavailableView {
                        Label("검색할 수 없어요", systemImage: "magnifyingglass")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("다시 검색") { Task { await model.search(query, near: origin) } }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("destination.retry")
                    }
                } else if !model.results.isEmpty {
                    List(Array(model.results.enumerated()), id: \.element.id) { index, result in
                        Button { onSelect(result) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.name).font(.body.weight(.semibold)).foregroundStyle(Color.repickInk)
                                if !result.address.isEmpty {
                                    Text(result.address).font(.subheadline).foregroundStyle(Color.repickSecondaryText)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .padding(.vertical, 4)
                        }
                        .accessibilityIdentifier("destination.result.\(index)")
                        .listRowBackground(Color.repickSurface)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                } else if model.hasSearched {
                    ContentUnavailableView("검색 결과가 없어요", systemImage: "mappin.slash", description: Text("다른 장소 이름이나 주소로 검색해 주세요."))
                } else {
                    ContentUnavailableView("어디로 걸어갈까요?", systemImage: "magnifyingglass", description: Text("장소 이름이나 주소를 입력하세요."))
                }
            }
            .background(Color.repickCream)
            .foregroundStyle(Color.repickInk)
            .navigationTitle("목적지 검색")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top, spacing: 0) { searchField }
            .scrollDismissesKeyboard(.interactively)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
            .task(id: query) { await model.search(query, near: origin) }
            .onAppear { isQueryFocused = true }
            .onDisappear { model.cancel() }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Color.repickSecondaryText)
                .accessibilityHidden(true)
            TextField("장소 또는 주소", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isQueryFocused)
                .onSubmit { isQueryFocused = false }
                .accessibilityLabel("목적지 검색어")
                .accessibilityIdentifier("destination.query")
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.repickSecondaryText)
                .accessibilityLabel("검색어 지우기")
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: Design.controlHeight)
        .background(Color.repickSurface, in: RoundedRectangle(cornerRadius: Design.controlRadius))
        .padding(.horizontal, Design.pagePadding)
        .padding(.vertical, 12)
        .background(Color.repickCream)
    }
}
