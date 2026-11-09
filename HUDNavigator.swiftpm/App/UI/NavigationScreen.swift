import SwiftUI
import MapKit

struct NavigationScreen: View {
    @Environment(AppModel.self) private var model
    @State private var completer = SearchCompleterModel()
    @State private var query = ""
    @State private var searchResults: [PlaceResult] = []
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var isSearching = false
    @State private var searchMessage: String?
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                NavMapView(position: $position, searchResults: searchResults) { place in
                    choose(place)
                }
                VStack(spacing: 8) {
                    SearchBar(query: $query, isSearching: isSearching, focused: $searchFocused) {
                        Task { await runSearch(query) }
                    }
                    .onChange(of: query) { _, newValue in
                        completer.update(query: newValue, near: model.location.lastSample?.coordinate)
                    }
                    if searchFocused && !completer.suggestions.isEmpty {
                        SuggestionList(suggestions: completer.suggestions) { completion in
                            Task { await runSearch(completion: completion) }
                        }
                    } else if !model.navigation.isGuiding {
                        CategoryChips { category in
                            Task { await runNearby(category) }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
            .safeAreaInset(edge: .bottom) {
                NavigationBottomPanel(searchResults: $searchResults, searchMessage: $searchMessage) { place in
                    choose(place)
                }
            }
            .navigationTitle("ナビ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            startDemo()
                        } label: {
                            Label("デモ案内（皇居外苑・シミュレーション）", systemImage: "play.circle")
                        }
                        Section("お気に入り") {
                            ForEach(model.favorites) { fav in
                                Button(fav.name) {
                                    choose(PlaceResult(name: fav.name, address: fav.address, coordinate: fav.coordinate))
                                }
                            }
                        }
                        Section("地図") {
                            Toggle("3D表示", isOn: Binding(get: { model.settings.map.use3D }, set: { model.settings.map.use3D = $0 }))
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .serviceDemand([.location, .heading, .navigation])
        .onChange(of: model.pendingSearch) { _, newValue in
            guard let q = newValue else { return }
            query = q
            model.pendingSearch = nil
            Task { await runSearch(q) }
        }
        .onChange(of: model.nearbyResults) { _, results in
            if !results.isEmpty { searchResults = results }
        }
        .onChange(of: model.navigationMapZoom) { _, zoom in
            if let c = model.location.lastSample?.coordinate {
                position = .camera(MapCamera(centerCoordinate: c.clCoordinate, distance: 1500 * zoom, heading: 0, pitch: model.settings.map.use3D ? 50 : 0))
            }
        }
        .onChange(of: model.navigation.phase) { _, phase in
            if phase == .guiding {
                position = .userLocation(followsHeading: model.settings.map.orientation == .headingUp, fallback: .automatic)
            }
        }
    }

    private func choose(_ place: PlaceResult) {
        searchFocused = false
        searchResults = []
        Task {
            await model.navigation.plan(to: place, transport: model.settings.map.defaultTransport)
            if let route = model.navigation.selectedRoute {
                position = .rect(boundingRect(route.polyline))
            }
        }
    }

    private func runSearch(_ text: String) async {
        let q = text.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        isSearching = true
        defer { isSearching = false }
        searchFocused = false
        do {
            searchResults = try await model.searchPlaces(q)
            searchMessage = searchResults.isEmpty ? "見つかりませんでした" : nil
            if let first = searchResults.first { position = .region(MKCoordinateRegion(center: first.coordinate.clCoordinate, latitudinalMeters: 3000, longitudinalMeters: 3000)) }
        } catch {
            searchMessage = model.network.isOnline ? "検索できませんでした" : "オフラインのため検索できません"
        }
    }

    private func runSearch(completion: MKLocalSearchCompletion) async {
        isSearching = true
        defer { isSearching = false }
        searchFocused = false
        query = completion.title
        if let results = try? await MapSearch.search(completion: completion, near: model.location.lastSample?.coordinate), let first = results.first {
            if results.count == 1 { choose(first) } else { searchResults = results }
        }
    }

    private func runNearby(_ category: NearbyCategory) async {
        isSearching = true
        defer { isSearching = false }
        let outcome = await model.perform(.searchNearby(category))
        searchResults = model.nearbyResults
        searchMessage = model.nearbyResults.isEmpty ? outcome.message : nil
    }

    private func startDemo() {
        let route = DemoRoutes.walkingRoute()
        model.location.startSimulation(points: route.polyline, speed: 1.6, name: "デモ（皇居外苑）")
        model.navigation.startDemo()
        model.refreshServices()
        position = .rect(boundingRect(route.polyline))
    }

    private func boundingRect(_ points: [GeoCoordinate]) -> MKMapRect {
        var rect = MKMapRect.null
        for p in points {
            let mp = MKMapPoint(p.clCoordinate)
            rect = rect.union(MKMapRect(x: mp.x, y: mp.y, width: 0, height: 0))
        }
        return rect.insetBy(dx: -rect.size.width * 0.25 - 400, dy: -rect.size.height * 0.25 - 400)
    }
}

struct NavMapView: View {
    @Environment(AppModel.self) private var model
    @Binding var position: MapCameraPosition
    let searchResults: [PlaceResult]
    var onSelect: (PlaceResult) -> Void

    var body: some View {
        let nav = model.navigation
        let shownRoutes: [NavRoute] = nav.isGuiding ? (nav.activeRoute.map { [$0] } ?? []) : nav.routes
        let highlightedID: UUID? = nav.activeRoute?.id ?? nav.selectedRouteID
        MapReader { proxy in
            Map(position: $position) {
                UserAnnotation()
                if model.location.isSimulating, let s = model.location.lastSample {
                    Annotation("シミュレーション", coordinate: s.coordinate.clCoordinate) {
                        Image(systemName: "location.north.circle.fill")
                            .font(.title)
                            .foregroundStyle(.orange)
                            .rotationEffect(.degrees(s.course >= 0 ? s.course : 0))
                    }
                }
                ForEach(shownRoutes) { route in
                    let isHighlighted = route.id == highlightedID
                    MapPolyline(coordinates: route.polyline.map(\.clCoordinate))
                        .stroke(isHighlighted ? Color.blue : Color.gray.opacity(0.7), lineWidth: isHighlighted ? 7 : 4)
                }
                if let dest = nav.destination {
                    Marker(dest.name, systemImage: "flag.checkered", coordinate: dest.coordinate.clCoordinate)
                        .tint(.red)
                }
                ForEach(searchResults) { place in
                    Marker(place.name, coordinate: place.coordinate.clCoordinate)
                        .tint(.orange)
                }
                ForEach(model.favorites) { fav in
                    Marker(fav.name, systemImage: "star.fill", coordinate: fav.coordinate.clCoordinate)
                        .tint(.yellow)
                }
            }
            .mapStyle(model.settings.map.use3D ? .standard(elevation: .realistic) : .standard)
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapPitchToggle()
                MapScaleView()
            }
            .onTapGesture { point in
                guard !nav.isGuiding, let coordinate = proxy.convert(point, from: .local) else { return }
                let geo = GeoCoordinate(coordinate)
                Task {
                    let name = await MapSearch.placeName(for: geo) ?? "地図上の地点"
                    onSelect(PlaceResult(name: name, address: "", coordinate: geo))
                }
            }
        }
    }
}

struct SearchBar: View {
    @Binding var query: String
    var isSearching: Bool
    var focused: FocusState<Bool>.Binding
    var onSubmit: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("施設名・住所で検索", text: $query)
                .focused(focused)
                .submitLabel(.search)
                .onSubmit(onSubmit)
            if isSearching { ProgressView() }
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct SuggestionList: View {
    let suggestions: [MKLocalSearchCompletion]
    var onSelect: (MKLocalSearchCompletion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(suggestions, id: \.self) { s in
                Button {
                    onSelect(s)
                } label: {
                    VStack(alignment: .leading) {
                        Text(s.title).foregroundStyle(.primary)
                        if !s.subtitle.isEmpty { Text(s.subtitle).font(.caption).foregroundStyle(.secondary) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                }
                Divider()
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct CategoryChips: View {
    var onSelect: (NearbyCategory) -> Void
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(NearbyCategory.allCases, id: \.self) { c in
                    Button { onSelect(c) } label: {
                        Label(c.displayName, systemImage: c.systemImage)
                            .font(.footnote)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.regularMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct NavigationBottomPanel: View {
    @Environment(AppModel.self) private var model
    @Binding var searchResults: [PlaceResult]
    @Binding var searchMessage: String?
    var onSelect: (PlaceResult) -> Void

    var body: some View {
        let nav = model.navigation
        VStack(alignment: .leading, spacing: 10) {
            switch nav.phase {
            case .guiding:
                GuidancePanel()
            case .arrived:
                HStack {
                    Label("\(nav.activeRoute?.destinationName ?? "目的地")に到着しました", systemImage: "flag.checkered").font(.headline)
                    Spacer()
                    Button("終了") { nav.stop() }.buttonStyle(.borderedProminent)
                }
            case .planning:
                HStack { ProgressView(); Text("ルートを検索中…") }
            case .choosing:
                RouteChoicePanel()
            case .idle:
                if let message = nav.message {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(message).font(.footnote)
                        if let dest = nav.destination {
                            HStack {
                                Button("Apple マップで開く") { RoutePlanner.openInMaps(dest, transport: nav.transport) }
                                Picker("移動手段", selection: Binding(get: { nav.transport }, set: { t in Task { await nav.plan(to: dest, transport: t) } })) {
                                    ForEach(TransportMode.allCases, id: \.self) { Label($0.displayName, systemImage: $0.systemImage).tag($0) }
                                }
                                .pickerStyle(.menu)
                            }
                        }
                    }
                }
                if !searchResults.isEmpty {
                    PlaceList(places: searchResults, onSelect: onSelect)
                } else if let searchMessage {
                    Text(searchMessage).font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("地図をタップ・検索・カテゴリ・「〇〇までナビして」で目的地を選べます。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
    }
}

struct PlaceList: View {
    let places: [PlaceResult]
    var onSelect: (PlaceResult) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(places.prefix(12)) { place in
                    Button { onSelect(place) } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(place.name).foregroundStyle(.primary)
                                Text([place.category, place.address.isEmpty ? nil : place.address].compactMap { $0 }.joined(separator: "・"))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                if place.rating != nil || place.openNow != nil {
                                    HStack(spacing: 6) {
                                        if let r = place.rating {
                                            Label(String(format: "%.1f", r) + (place.ratingCount.map { "（\($0)件）" } ?? ""), systemImage: "star.fill")
                                                .foregroundStyle(.orange)
                                        }
                                        if let open = place.openNow {
                                            Text(open ? "営業中" : "営業時間外").foregroundStyle(open ? Color.green : Color.secondary)
                                        }
                                        if let today = todayHours(place) {
                                            Text(today).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                    }
                                    .font(.caption2)
                                }
                            }
                            Spacer()
                            if let d = place.distance { Text(HUDFormat.distance(d)).font(.caption).foregroundStyle(.secondary) }
                        }
                        .padding(.vertical, 6)
                    }
                    Divider()
                }
                if places.contains(where: { $0.source == "Apple" }) {
                    Text("営業時間・評価は Apple マップでは取得できません（Google Maps の APIキーを設定すると表示します）。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                } else if !places.isEmpty {
                    Text("検索：Google Maps").font(.caption2).foregroundStyle(.secondary).padding(.top, 4)
                }
            }
        }
        .frame(maxHeight: 240)
    }

    /// 今日の営業時間（Google の weekdayDescriptions は月曜始まり）
    private func todayHours(_ place: PlaceResult) -> String? {
        guard place.openingHours.count == 7 else { return nil }
        let weekday = Calendar(identifier: .gregorian).component(.weekday, from: Date()) // 1=日曜
        let index = (weekday + 5) % 7
        return place.openingHours[index]
    }
}

struct RouteChoicePanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let nav = model.navigation
        VStack(alignment: .leading, spacing: 8) {
            if let dest = nav.destination {
                HStack {
                    VStack(alignment: .leading) {
                        Text(dest.name).font(.headline)
                        if !dest.address.isEmpty { Text(dest.address).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Button { model.addFavorite(dest) } label: { Image(systemName: "star") }
                        .accessibilityLabel("お気に入りに追加")
                    Button { nav.clearPlan() } label: { Image(systemName: "xmark.circle.fill") }
                        .foregroundStyle(.secondary)
                }
                Picker("移動手段", selection: Binding(get: { nav.transport }, set: { t in Task { await nav.plan(to: dest, transport: t) } })) {
                    ForEach(TransportMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                if !nav.routes.isEmpty {
                    Text("経路：\(nav.routeSource == "Google" ? "Google Maps" : "Apple マップ")")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            ForEach(nav.routes) { route in
                let selected = route.id == (nav.selectedRouteID ?? nav.routes.first?.id)
                Button {
                    nav.selectedRouteID = route.id
                } label: {
                    HStack {
                        Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                        VStack(alignment: .leading) {
                            Text("\(HUDFormat.duration(route.expectedTravelTime))・\(HUDFormat.distance(route.distance))").font(.headline)
                            Text("\(route.name)・到着 \(HUDFormat.clock(Date().addingTimeInterval(route.expectedTravelTime)))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .foregroundStyle(.primary)
                }
                ForEach(route.advisoryNotices, id: \.self) { Text($0).font(.caption2).foregroundStyle(UIStyle.warning) }
            }
            Button {
                nav.start()
            } label: {
                Label("案内を開始", systemImage: "location.north.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(nav.routes.isEmpty)
        }
    }
}

struct GuidancePanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let nav = model.navigation
        VStack(alignment: .leading, spacing: 8) {
            if let step = nav.nextStep, let d = nav.progress?.distanceToNextManeuver {
                HStack(spacing: 12) {
                    Image(systemName: step.maneuver.systemImage).font(.largeTitle).foregroundStyle(UIStyle.accent)
                    VStack(alignment: .leading) {
                        Text(HUDFormat.distance(d)).font(.title.bold()).monospacedDigit()
                        Text(step.instruction).font(.subheadline).lineLimit(2)
                    }
                }
            } else {
                Text("現在地を取得しています…").font(.subheadline)
            }
            if let p = nav.progress {
                Text("残り \(HUDFormat.distance(p.remainingDistance))・約\(HUDFormat.duration(p.remainingTime))・到着 \(HUDFormat.clock(p.eta(from: Date())))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if p.isOffRoute { Text("ルートから外れています").font(.footnote).foregroundStyle(UIStyle.warning) }
            }
            if nav.isDemo { Text("デモ（位置はシミュレーション）").font(.caption).foregroundStyle(.orange) }
            if let m = nav.message { Text(m).font(.caption).foregroundStyle(UIStyle.warning) }
            HStack {
                Button(role: .destructive) { nav.stop() } label: { Label("終了", systemImage: "xmark") }
                    .buttonStyle(.bordered)
                Button {
                    model.settings.voice.guidanceEnabled.toggle()
                } label: {
                    Image(systemName: model.settings.voice.guidanceEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("音声案内の切り替え")
                Button {
                    Task { await model.perform(.repeatGuidance) }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("案内をもう一度")
                Spacer()
                if model.display.mode != .independent {
                    Button { model.isHUDPresented = true } label: { Label("HUD", systemImage: "eyeglasses") }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}
