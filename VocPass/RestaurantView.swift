//
//  RestaurantView.swift
//  VocPass
//

import SwiftUI
import MapKit
import CoreLocation
import Combine
import PhotosUI

// MARK: - 定位管理
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var location: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorizationStatus = manager.authorizationStatus
    }

    func requestLocation() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async { self.authorizationStatus = manager.authorizationStatus }
        if manager.authorizationStatus == .authorizedWhenInUse ||
           manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last, loc.horizontalAccuracy >= 0 else { return }
        DispatchQueue.main.async { self.location = loc }
        manager.stopUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("❌ [Location] \(error.localizedDescription)")
    }
}

// MARK: - 餐廳距離輔助
extension Restaurant {
    func distance(from userLocation: CLLocation) -> CLLocationDistance? {
        guard let map else { return nil }
        return CLLocation(latitude: map.lat, longitude: map.lon).distance(from: userLocation)
    }
}

private func formattedDistance(_ meters: Double) -> String {
    meters < 1000
        ? String(format: "%.0f m", meters)
        : String(format: "%.1f km", meters / 1000)
}

// MARK: - 餐廳列表
struct RestaurantView: View {
    @EnvironmentObject var apiService: APIService
    @StateObject private var schoolConfigManager = SchoolConfigManager.shared
    @StateObject private var locationManager = LocationManager()

    @State private var restaurants: [Restaurant] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var pickedRestaurant: Restaurant?
    @State private var selectedSchoolName: String = ""
    @State private var showSchoolPicker = false
    @State private var showAddRestaurant = false
    @State private var viewMode: ViewMode = .list
    @State private var deletingRestaurant: Restaurant?
    @State private var deleteError: String?
    @State private var reportingContext: ReportContext?

    enum ViewMode { case list, map }

    private var sortedRestaurants: [Restaurant] {
        guard let userLoc = locationManager.location else { return restaurants }
        return restaurants.sorted {
            ($0.distance(from: userLoc) ?? .infinity) < ($1.distance(from: userLoc) ?? .infinity)
        }
    }

    var body: some View {
        Group {
            if viewMode == .list {
                listContent
            } else {
                RestaurantMapView(
                    restaurants: sortedRestaurants.filter { $0.map != nil },
                    userLocation: locationManager.location
                )
            }
        }
        .navigationTitle("吃啥？")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    viewMode = viewMode == .list ? .map : .list
                } label: {
                    Image(systemName: viewMode == .list ? "map" : "list.bullet")
                }
                .disabled(restaurants.isEmpty)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddRestaurant = true
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(selectedSchoolName.isEmpty)
            }
        }
        .onAppear {
            locationManager.requestLocation()
            if schoolConfigManager.schools.isEmpty {
                schoolConfigManager.loadSchools()
            }
            if selectedSchoolName.isEmpty {
                selectedSchoolName = schoolConfigManager.selectedSchool?.name
                    ?? schoolConfigManager.schools.first?.name
                    ?? ""
            }
        }
        .onChange(of: schoolConfigManager.schools.count) { _, _ in
            if selectedSchoolName.isEmpty {
                selectedSchoolName = schoolConfigManager.selectedSchool?.name
                    ?? schoolConfigManager.schools.first?.name
                    ?? ""
            }
        }
        .onChange(of: selectedSchoolName) { _, _ in
            restaurants = []
            Task { await loadRestaurants() }
        }
        .sheet(isPresented: $showSchoolPicker) {
            SchoolPickerSheet(schools: schoolConfigManager.schools, selected: $selectedSchoolName)
        }
        .sheet(item: $pickedRestaurant) { r in
            PickedRestaurantSheet(finalRestaurant: r, allRestaurants: restaurants)
                .environmentObject(apiService)
        }
        .sheet(isPresented: $showAddRestaurant) {
            AddRestaurantSheet(school: selectedSchoolName, userLocation: locationManager.location) {
                Task { await loadRestaurants() }
            }
            .environmentObject(apiService)
        }
        .confirmationDialog(
            "確定刪除「\(deletingRestaurant?.name ?? "")」？",
            isPresented: Binding(get: { deletingRestaurant != nil }, set: { if !$0 { deletingRestaurant = nil } }),
            titleVisibility: .visible
        ) {
            Button("刪除", role: .destructive) {
                if let r = deletingRestaurant {
                    deletingRestaurant = nil
                    Task { await confirmDeleteRestaurant(r) }
                }
            }
            Button("取消", role: .cancel) { deletingRestaurant = nil }
        }
        .alert("刪除失敗", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("確定", role: .cancel) { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
        .sheet(item: $reportingContext) { ctx in
            ReportSheet(context: ctx)
                .environmentObject(apiService)
        }
    }

    @ViewBuilder
    private var listContent: some View {
        List {
            // 學校選擇器
            Section {
                if schoolConfigManager.schools.isEmpty {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .listRowBackground(Color.clear)
                } else {
                    Button {
                        showSchoolPicker = true
                    } label: {
                        HStack {
                            Text("學校")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(selectedSchoolName.isEmpty ? "請選擇" : selectedSchoolName)
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !selectedSchoolName.isEmpty {
                if !sortedRestaurants.isEmpty {
                    Section {
                        Button {
                            pickRandom()
                        } label: {
                            HStack {
                                Image(systemName: "dice.fill")
                                    .foregroundStyle(.white)
                                    .frame(width: 32, height: 32)
                                    .background(Color.orange)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                Text("隨機挑一間")
                                    .fontWeight(.semibold)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }

                Section("\(selectedSchoolName) 的餐廳") {
                    if isLoading {
                        HStack { Spacer(); ProgressView(); Spacer() }
                            .listRowBackground(Color.clear)
                    } else if let error = errorMessage {
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                            Text(error)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Button("重試") {
                                Task { await loadRestaurants() }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .listRowBackground(Color.clear)
                    } else if sortedRestaurants.isEmpty {
                        Text("目前尚無餐廳資料")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 12)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(sortedRestaurants) { restaurant in
                            NavigationLink(destination: RestaurantDetailView(restaurant: restaurant)) {
                                RestaurantRowView(
                                    restaurant: restaurant,
                                    distance: locationManager.location.flatMap { restaurant.distance(from: $0) }
                                )
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if restaurant.user == VocPassAuthService.shared.currentUser?.id {
                                    Button(role: .destructive) {
                                        deletingRestaurant = restaurant
                                    } label: {
                                        Label("刪除", systemImage: "trash")
                                    }
                                } else {
                                    Button {
                                        reportingContext = ReportContext(restaurantID: restaurant.id)
                                    } label: {
                                        Label("檢舉", systemImage: "flag")
                                    }
                                    .tint(.orange)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func loadRestaurants() async {
        guard !selectedSchoolName.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        do {
            restaurants = try await apiService.fetchRestaurants(school: selectedSchoolName)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func pickRandom() {
        guard !restaurants.isEmpty else { return }
        pickedRestaurant = restaurants.randomElement()
    }

    private func confirmDeleteRestaurant(_ restaurant: Restaurant) async {
        do {
            try await apiService.deleteRestaurant(id: restaurant.id)
            restaurants.removeAll { $0.id == restaurant.id }
        } catch {
            deleteError = error.localizedDescription
        }
    }
}

/// MARK: - 檢舉 Context
struct ReportContext: Identifiable {
    let id = UUID()
    var restaurantID: String?
    var restaurantEvaluateID: String?
    var restaurantMenuID: String?
    var forumPostID: String?
    var forumMessageID: String?
}

// MARK: - 餐廳列表 Row
struct RestaurantRowView: View {
    let restaurant: Restaurant
    var distance: CLLocationDistance? = nil

    var body: some View {
        HStack(spacing: 12) {
            RestaurantIcon(url: restaurant.iconURL, size: 44, cornerRadius: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(restaurant.name)
                    .font(.body)
                if let d = distance {
                    Text(formattedDistance(d))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 餐廳詳細頁
struct RestaurantDetailView: View {
    let restaurant: Restaurant
    @EnvironmentObject var apiService: APIService

    @State private var evaluations: [RestaurantEvaluation] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showAddEvaluation = false
    @State private var editingEvaluation: RestaurantEvaluation?
    @State private var deletingEvaluation: RestaurantEvaluation?
    @State private var reportingContext: ReportContext?
    @State private var actionError: String?

    // 菜單
    @State private var menuItems: [RestaurantMenu] = []
    @State private var isLoadingMenu = false
    @State private var menuError: String?
    @State private var showAddMenu = false
    @State private var deletingMenu: RestaurantMenu?
    @State private var viewingMenu: RestaurantMenu?

    private var averageScore: Double? {
        guard !evaluations.isEmpty else { return nil }
        return Double(evaluations.reduce(0) { $0 + $1.score }) / Double(evaluations.count)
    }

    var body: some View {
        List {
            // 頂部資訊 + 導航按鈕
            Section {
                HStack(spacing: 16) {
                    RestaurantIcon(url: restaurant.iconURL, size: 64, cornerRadius: 14)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(restaurant.name)
                            .font(.title3)
                            .fontWeight(.semibold)
                        if let address = restaurant.address, !address.isEmpty {
                            Text(address)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if let map = restaurant.map {
                            Text(String(format: "%.5f, %.5f", map.lat, map.lon))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let avg = averageScore {
                            HStack(spacing: 4) {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(.yellow)
                                    .font(.caption)
                                Text(String(format: "%.1f", avg))
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Text("(\(evaluations.count) 則評價)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else if !isLoading {
                            Text("暫無評價")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 4)

                if let map = restaurant.map {
                    Button {
                        openMaps(lat: map.lat, lon: map.lon, name: restaurant.name)
                    } label: {
                        Label("導航", systemImage: "map.fill")
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                }
            }

            // 菜單
            Section {
                if isLoadingMenu {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .listRowBackground(Color.clear)
                } else if let error = menuError {
                    Text(error).font(.subheadline).foregroundStyle(.secondary)
                } else if menuItems.isEmpty {
                    Text("目前尚無菜單圖片")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                        ForEach(menuItems) { item in
                            CachedAsyncImage(url: item.menuURL) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable().scaledToFill()
                                default:
                                    Color(.systemGray5)
                                        .overlay(ProgressView())
                                }
                            }
                            .frame(width: 100, height: 100)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .onTapGesture { viewingMenu = item }
                            .contextMenu {
                                if item.user == VocPassAuthService.shared.currentUser?.id {
                                    Button(role: .destructive) {
                                        deletingMenu = item
                                    } label: {
                                        Label("刪除", systemImage: "trash")
                                    }
                                } else {
                                    Button {
                                        reportingContext = ReportContext(restaurantMenuID: item.id)
                                    } label: {
                                        Label("檢舉", systemImage: "flag")
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            } header: {
                HStack {
                    Text("菜單")
                    Spacer()
                    Button {
                        showAddMenu = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }

            // 評價
            Section("評價") {
                if isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .listRowBackground(Color.clear)
                } else if let error = errorMessage {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if evaluations.isEmpty {
                    Text("目前尚無評價")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                } else {
                    ForEach(evaluations) { ev in
                        EvaluationRowView(evaluation: ev)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if ev.user == VocPassAuthService.shared.currentUser?.id {
                                    Button(role: .destructive) {
                                        deletingEvaluation = ev
                                    } label: {
                                        Label("刪除", systemImage: "trash")
                                    }
                                    Button {
                                        editingEvaluation = ev
                                    } label: {
                                        Label("編輯", systemImage: "pencil")
                                    }
                                    .tint(.blue)
                                } else {
                                    Button {
                                        reportingContext = ReportContext(restaurantEvaluateID: ev.id)
                                    } label: {
                                        Label("檢舉", systemImage: "flag")
                                    }
                                    .tint(.orange)
                                }
                            }
                    }
                }
            }
        }
        .navigationTitle(restaurant.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddEvaluation = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
            }
        }
        .task {
            await loadEvaluations()
            await loadMenu()
        }
        .sheet(isPresented: $showAddEvaluation) {
            AddEvaluationSheet(restaurant: restaurant) {
                Task { await loadEvaluations() }
            }
            .environmentObject(apiService)
        }
        .sheet(item: $editingEvaluation) { ev in
            EditEvaluationSheet(evaluation: ev) {
                Task { await loadEvaluations() }
            }
            .environmentObject(apiService)
        }
        .sheet(item: $reportingContext) { ctx in
            ReportSheet(context: ctx)
                .environmentObject(apiService)
        }
        .sheet(isPresented: $showAddMenu) {
            AddMenuSheet(restaurantID: restaurant.id) {
                Task { await loadMenu() }
            }
            .environmentObject(apiService)
        }
        .fullScreenCover(item: $viewingMenu) { item in
            MenuImageViewer(url: item.menuURL)
        }
        .confirmationDialog(
            "確定刪除這則評價？",
            isPresented: Binding(get: { deletingEvaluation != nil }, set: { if !$0 { deletingEvaluation = nil } }),
            titleVisibility: .visible
        ) {
            Button("刪除", role: .destructive) {
                if let ev = deletingEvaluation {
                    deletingEvaluation = nil
                    Task { await confirmDeleteEvaluation(ev) }
                }
            }
            Button("取消", role: .cancel) { deletingEvaluation = nil }
        }
        .confirmationDialog(
            "確定刪除這張菜單圖片？",
            isPresented: Binding(get: { deletingMenu != nil }, set: { if !$0 { deletingMenu = nil } }),
            titleVisibility: .visible
        ) {
            Button("刪除", role: .destructive) {
                if let item = deletingMenu {
                    deletingMenu = nil
                    Task { await confirmDeleteMenu(item) }
                }
            }
            Button("取消", role: .cancel) { deletingMenu = nil }
        }
        .alert("操作失敗", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("確定", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
    }

    private func confirmDeleteEvaluation(_ ev: RestaurantEvaluation) async {
        do {
            try await apiService.deleteEvaluation(id: ev.id)
            evaluations.removeAll { $0.id == ev.id }
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func confirmDeleteMenu(_ item: RestaurantMenu) async {
        do {
            try await apiService.deleteRestaurantMenu(id: item.id)
            menuItems.removeAll { $0.id == item.id }
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func loadEvaluations() async {
        isLoading = true
        errorMessage = nil
        do {
            evaluations = try await apiService.fetchRestaurantEvaluations(id: restaurant.id)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func loadMenu() async {
        isLoadingMenu = true
        menuError = nil
        do {
            menuItems = try await apiService.fetchRestaurantMenu(id: restaurant.id)
        } catch {
            menuError = error.localizedDescription
        }
        isLoadingMenu = false
    }

    private func openMaps(lat: Double, lon: Double, name: String) {
        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        mapItem.name = name
        mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
}

// MARK: - 評價 Row
struct EvaluationRowView: View {
    let evaluation: RestaurantEvaluation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(evaluation.title)
                    .font(.headline)
                Spacer()
                StarRatingView(score: evaluation.score)
            }
            if !evaluation.plainDescription.isEmpty {
                Text(evaluation.plainDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 星星評分
struct StarRatingView: View {
    let score: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: i <= score ? "star.fill" : "star")
                    .font(.caption)
                    .foregroundStyle(i <= score ? Color.yellow : Color(.systemGray4))
            }
        }
    }
}

// MARK: - 共用圖示元件
struct RestaurantIcon: View {
    let url: URL?
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        Group {
            if let url {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    private var placeholder: some View {
        Image(systemName: "fork.knife")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGray5))
    }
}

// MARK: - 隨機結果 Sheet
struct PickedRestaurantSheet: View {
    let finalRestaurant: Restaurant
    let allRestaurants: [Restaurant]
    @Environment(\.dismiss) private var dismiss

    @State private var displayedName: String = ""
    @State private var isRolling = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                RestaurantIcon(url: isRolling ? nil : finalRestaurant.iconURL, size: 100, cornerRadius: 20)
                    .animation(.easeInOut(duration: 0.3), value: isRolling)

                VStack(spacing: 8) {
                    Text("今天就吃")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text(displayedName)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                        .contentTransition(.numericText())
                        .animation(.default, value: displayedName)
                        .frame(minHeight: 44)
                }

                Spacer()

                VStack(spacing: 12) {
                    NavigationLink(destination: RestaurantDetailView(restaurant: finalRestaurant)) {
                        Text("查看評價")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isRolling)

                    Button {
                        dismiss()
                    } label: {
                        Text("算了")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(isRolling)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 16)
            }
            .navigationTitle("吃啥？")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { dismiss() }
                }
            }
            .task {
                await rollAnimation()
            }
        }
    }

    private func rollAnimation() async {
        guard allRestaurants.count > 1 else {
            displayedName = finalRestaurant.name
            isRolling = false
            return
        }

        // 快速滾動階段：每 80ms 換一個
        let fastRounds = 10
        for _ in 0..<fastRounds {
            displayedName = allRestaurants.randomElement()!.name
            try? await Task.sleep(for: .milliseconds(80))
        }

        // 慢速收尾：逐漸拉長間隔
        let slowDelays: [UInt64] = [130, 180, 240, 320, 420]
        for delay in slowDelays {
            displayedName = allRestaurants.randomElement()!.name
            try? await Task.sleep(for: .milliseconds(delay))
        }

        // 最終結果
        displayedName = finalRestaurant.name
        isRolling = false
    }
}

// MARK: - 地圖視圖
struct RestaurantMapView: View {
    let restaurants: [Restaurant]
    let userLocation: CLLocation?

    @State private var selectedId: String?
    @State private var cameraPosition: MapCameraPosition = .automatic

    private var selectedRestaurant: Restaurant? {
        guard let id = selectedId else { return nil }
        return restaurants.first { $0.id == id }
    }

    var body: some View {
        Map(position: $cameraPosition, selection: $selectedId) {
            ForEach(restaurants) { r in
                if let map = r.map {
                    Marker(r.name, coordinate: .init(latitude: map.lat, longitude: map.lon))
                        .tag(r.id)
                }
            }
            UserAnnotation()
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
        .safeAreaInset(edge: .bottom) {
            if let r = selectedRestaurant {
                RestaurantMapCard(restaurant: r, userLocation: userLocation)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: selectedId)
    }
}

struct RestaurantMapCard: View {
    let restaurant: Restaurant
    let userLocation: CLLocation?
    @EnvironmentObject var apiService: APIService

    var body: some View {
        HStack(spacing: 14) {
            RestaurantIcon(url: restaurant.iconURL, size: 52, cornerRadius: 10)

            VStack(alignment: .leading, spacing: 3) {
                Text(restaurant.name)
                    .font(.headline)
                    .lineLimit(1)
                if let d = userLocation.flatMap({ restaurant.distance(from: $0) }) {
                    Text(formattedDistance(d))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let map = restaurant.map {
                Button {
                    let coord = CLLocationCoordinate2D(latitude: map.lat, longitude: map.lon)
                    let item = MKMapItem(placemark: MKPlacemark(coordinate: coord))
                    item.name = restaurant.name
                    item.openInMaps(launchOptions: [
                        MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
                    ])
                } label: {
                    Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                        .font(.title)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }

            NavigationLink(destination: RestaurantDetailView(restaurant: restaurant)
                .environmentObject(apiService)) {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.title)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}

// MARK: - 新增評價 Sheet
struct AddEvaluationSheet: View {
    let restaurant: Restaurant
    var onAdded: () -> Void

    @EnvironmentObject var apiService: APIService
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var evalDescription = ""
    @State private var score = 3
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("評價") {
                    TextField("標題", text: $title)
                    TextField("內容", text: $evalDescription, axis: .vertical)
                        .lineLimit(3...6)
                    HStack {
                        Text("評分")
                        Spacer()
                        InteractiveStarRating(score: $score)
                    }
                }

                Section {
                    Button {
                        print("🔘 [UI] 送出評價 tapped, title='\(title)' isSubmitting=\(isSubmitting)")
                        Task { await submit() }
                    } label: {
                        if isSubmitting {
                            HStack { Spacer(); ProgressView(); Spacer() }
                        } else {
                            Text("送出")
                                .frame(maxWidth: .infinity, alignment: .center)
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(isSubmitting || title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("新增評價")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .alert("送出失敗", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("確定", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func submit() async {
        let trimTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimTitle.isEmpty else { return }
        isSubmitting = true
        errorMessage = nil
        do {
            try await apiService.createEvaluation(
                restaurantID: restaurant.id,
                title: trimTitle,
                description: evalDescription.trimmingCharacters(in: .whitespaces),
                score: score
            )
            onAdded()
            dismiss()
        } catch {
            print("❌ [UI] createEvaluation failed: \(error)")
            errorMessage = error.localizedDescription
        }
        isSubmitting = false
    }
}

// MARK: - 編輯評價 Sheet
struct EditEvaluationSheet: View {
    let evaluation: RestaurantEvaluation
    var onUpdated: () -> Void

    @EnvironmentObject var apiService: APIService
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var evalDescription: String
    @State private var score: Int
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    init(evaluation: RestaurantEvaluation, onUpdated: @escaping () -> Void) {
        self.evaluation = evaluation
        self.onUpdated = onUpdated
        _title = State(initialValue: evaluation.title)
        _evalDescription = State(initialValue: evaluation.plainDescription)
        _score = State(initialValue: evaluation.score)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("評價") {
                    TextField("標題", text: $title)
                    TextField("內容", text: $evalDescription, axis: .vertical)
                        .lineLimit(3...6)
                    HStack {
                        Text("評分")
                        Spacer()
                        InteractiveStarRating(score: $score)
                    }
                }

                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        if isSubmitting {
                            HStack { Spacer(); ProgressView(); Spacer() }
                        } else {
                            Text("儲存")
                                .frame(maxWidth: .infinity, alignment: .center)
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(isSubmitting || title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("編輯評價")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .alert("更新失敗", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("確定", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func submit() async {
        let trimTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimTitle.isEmpty else { return }
        isSubmitting = true
        errorMessage = nil
        do {
            try await apiService.updateEvaluation(
                id: evaluation.id,
                title: trimTitle,
                description: evalDescription.trimmingCharacters(in: .whitespaces),
                score: score
            )
            onUpdated()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSubmitting = false
    }
}

// MARK: - 新增餐廳 Sheet (Apple Maps 搜尋 → 強制評價)
struct AddRestaurantSheet: View {
    let school: String
    var userLocation: CLLocation? = nil
    var onAdded: () -> Void

    @EnvironmentObject var apiService: APIService
    @Environment(\.dismiss) private var dismiss

    enum Stage { case search, mapPick, evaluate }
    @State private var stage: Stage = .search
    @State private var pickedFromMap = false

    // Search
    @State private var searchText = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var isSearching = false
    @State private var selectedMapItem: MKMapItem?

    // Map pick — tap POI markers
    @State private var mapCameraPosition: MapCameraPosition = .automatic
    @State private var selectedFeature: MapFeature?
    @State private var isLoadingFeature = false

    // Shared restaurant info
    @State private var restaurantAddress = ""

    // Evaluation
    @State private var evalTitle = ""
    @State private var evalDescription = ""
    @State private var evalScore = 3

    // Submission
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var navTitle: String {
        switch stage {
        case .search: return "搜尋餐廳"
        case .mapPick: return "從地圖選擇"
        case .evaluate: return "新增評價"
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .search: searchStage
                case .mapPick: mapPickStage
                case .evaluate: evaluateStage
                }
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    switch stage {
                    case .search:
                        Button("取消") { dismiss() }
                    case .mapPick:
                        Button("上一步") {
                            selectedFeature = nil
                            stage = .search
                        }
                    case .evaluate:
                        Button("上一步") {
                            if pickedFromMap {
                                selectedMapItem = nil
                                selectedFeature = nil
                                stage = .mapPick
                            } else {
                                stage = .search
                            }
                            errorMessage = nil
                        }
                    }
                }
            }
            .alert("送出失敗", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("確定", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - 搜尋頁
    private var searchStage: some View {
        List {
            Section {
                Button {
                    if let loc = userLocation {
                        mapCameraPosition = .region(MKCoordinateRegion(
                            center: loc.coordinate,
                            span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                        ))
                    } else {
                        mapCameraPosition = .region(MKCoordinateRegion(
                            center: CLLocationCoordinate2D(latitude: 23.5, longitude: 121.0),
                            span: MKCoordinateSpan(latitudeDelta: 3.0, longitudeDelta: 3.0)
                        ))
                    }
                    selectedFeature = nil
                    stage = .mapPick
                } label: {
                    Label("從地圖選擇店家", systemImage: "map")
                }
            }

            if isSearching {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .listRowBackground(Color.clear)
            } else if searchResults.isEmpty && !searchText.isEmpty {
                Text("找不到結果")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(searchResults, id: \.self) { item in
                    Button {
                        selectedMapItem = item
                        restaurantAddress = item.placemark.title ?? ""
                        pickedFromMap = false
                        evalTitle = ""
                        evalDescription = ""
                        evalScore = 3
                        errorMessage = nil
                        stage = .evaluate
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name ?? "未知名稱")
                                .foregroundStyle(.primary)
                            if let address = item.placemark.title {
                                Text(address)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "輸入餐廳名稱")
        .onSubmit(of: .search) {
            Task { await performSearch() }
        }
        .onChange(of: searchText) { _, newValue in
            if newValue.isEmpty { searchResults = [] }
        }
    }

    // MARK: - 地圖選擇頁（點選 POI 標記）
    private var mapPickStage: some View {
        ZStack(alignment: .bottom) {
            Map(position: $mapCameraPosition, selection: $selectedFeature) {
                UserAnnotation()
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .ignoresSafeArea(edges: .bottom)

            if let feature = selectedFeature {
                // 已選擇 POI — 顯示確認卡
                VStack(spacing: 12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(feature.title ?? "未知店家")
                                .font(.headline)
                                .lineLimit(2)
                        }
                        Spacer()
                        Button { selectedFeature = nil } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        Task { await selectFeature(feature) }
                    } label: {
                        if isLoadingFeature {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text("選擇此店家")
                                .frame(maxWidth: .infinity)
                                .fontWeight(.semibold)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isLoadingFeature)
                }
                .padding()
                .background(.ultraThinMaterial)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                // 尚未選擇 — 顯示提示
                Text("點選地圖上的店家標記來選擇餐廳")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 40)
                    .transition(.opacity)
            }
        }
        .animation(.spring(duration: 0.3), value: selectedFeature == nil)
    }

    // MARK: - 評價頁
    private var evaluateStage: some View {
        Form {
            Section("餐廳") {
                if let item = selectedMapItem {
                    Text(item.name ?? "")
                        .font(.headline)
                        .padding(.vertical, 4)
                }
                TextField("地址", text: $restaurantAddress)
                    .foregroundStyle(.secondary)
            }

            Section("評價") {
                TextField("標題", text: $evalTitle)
                TextField("內容", text: $evalDescription, axis: .vertical)
                    .lineLimit(3...6)

                HStack {
                    Text("評分")
                    Spacer()
                    InteractiveStarRating(score: $evalScore)
                }
            }

            Section {
                Button {
                    Task { await submit() }
                } label: {
                    if isSubmitting {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    } else {
                        Text("送出")
                            .frame(maxWidth: .infinity, alignment: .center)
                            .fontWeight(.semibold)
                    }
                }
                .disabled(isSubmitting || evalTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: - Logic
    private func performSearch() async {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        isSearching = true
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        do {
            let response = try await MKLocalSearch(request: request).start()
            let items = response.mapItems
            if let userLoc = userLocation {
                searchResults = items.sorted {
                    ($0.placemark.location?.distance(from: userLoc) ?? .infinity) <
                    ($1.placemark.location?.distance(from: userLoc) ?? .infinity)
                }
            } else {
                searchResults = items
            }
        } catch {
            searchResults = []
        }
        isSearching = false
    }

    private func selectFeature(_ feature: MapFeature) async {
        isLoadingFeature = true
        let coord = feature.coordinate
        let placemark = MKPlacemark(coordinate: coord)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = feature.title ?? ""

        // 反向地理編碼取得地址
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        if let pm = try? await geocoder.reverseGeocodeLocation(location).first {
            restaurantAddress = [pm.thoroughfare, pm.subLocality, pm.locality, pm.administrativeArea]
                .compactMap { $0 }.joined(separator: ", ")
        } else {
            restaurantAddress = ""
        }

        selectedMapItem = mapItem
        pickedFromMap = true
        evalTitle = ""
        evalDescription = ""
        evalScore = 3
        errorMessage = nil
        isLoadingFeature = false
        stage = .evaluate
    }

    private func submit() async {
        guard let item = selectedMapItem else { return }
        let title = evalTitle.trimmingCharacters(in: .whitespaces)
        let desc  = evalDescription.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }

        isSubmitting = true
        errorMessage = nil
        do {
            let coord = item.placemark.coordinate
            let restaurantID = try await apiService.createRestaurant(
                school: school,
                name: item.name ?? title,
                lat: coord.latitude,
                lon: coord.longitude,
                address: restaurantAddress.trimmingCharacters(in: .whitespaces).isEmpty ? nil : restaurantAddress
            )
            try await apiService.createEvaluation(
                restaurantID: restaurantID,
                title: title,
                description: desc,
                score: evalScore
            )
            onAdded()
            dismiss()
        } catch {
            print("❌ [UI] createRestaurant/Evaluation failed: \(error)")
            errorMessage = error.localizedDescription
        }
        isSubmitting = false
    }
}

// MARK: - 菜單圖片全螢幕檢視
struct MenuImageViewer: View {
    let url: URL?
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            CachedAsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in scale = max(1, value) }
                                .onEnded { _ in
                                    if scale < 1 { withAnimation { scale = 1; offset = .zero } }
                                }
                                .simultaneously(with:
                                    DragGesture()
                                        .onChanged { value in
                                            if scale > 1 { offset = value.translation }
                                        }
                                        .onEnded { _ in
                                            if scale <= 1 { withAnimation { offset = .zero } }
                                        }
                                )
                        )
                        .onTapGesture(count: 2) {
                            withAnimation {
                                scale = scale > 1 ? 1 : 2.5
                                offset = .zero
                            }
                        }
                default:
                    ProgressView().tint(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding()
            }
        }
    }
}

// MARK: - 新增菜單 Sheet
struct AddMenuSheet: View {
    let restaurantID: String
    let onAdded: () -> Void

    @EnvironmentObject var apiService: APIService
    @Environment(\.dismiss) private var dismiss

    @State private var selectedItem: PhotosPickerItem?
    @State private var previewImage: Image?
    @State private var imageData: Data?
    @State private var mimeType = "image/jpeg"
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private let maxBytes = 5 * 1024 * 1024   // 5 MB

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        if let previewImage {
                            previewImage
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 200)
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        } else {
                            Label("選擇圖片", systemImage: "photo")
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 12)
                        }
                    }
                    .onChange(of: selectedItem) { _, newItem in
                        Task { await loadImage(from: newItem) }
                    }
                    if imageData != nil {
                        Text("上限 5 MB")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }

                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        if isSubmitting {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                        } else {
                            Text("上傳")
                                .frame(maxWidth: .infinity, alignment: .center)
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(isSubmitting || imageData == nil)
                }
            }
            .navigationTitle("新增菜單圖片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func loadImage(from item: PhotosPickerItem?) async {
        guard let item else { return }
        errorMessage = nil

        // Try PNG first, fallback to JPEG
        if let data = try? await item.loadTransferable(type: Data.self) {
            // Detect PNG by magic bytes
            let isPNG = data.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47])
            if data.count > maxBytes {
                errorMessage = "圖片超過 5 MB，請選擇較小的圖片"
                imageData = nil
                previewImage = nil
                return
            }
            imageData = data
            mimeType = isPNG ? "image/png" : "image/jpeg"
            if let uiImage = UIImage(data: data) {
                previewImage = Image(uiImage: uiImage)
            }
        }
    }

    private func submit() async {
        guard let data = imageData else { return }
        isSubmitting = true
        errorMessage = nil
        do {
            try await apiService.createRestaurantMenu(restaurantID: restaurantID, imageData: data, mimeType: mimeType)
            onAdded()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSubmitting = false
    }
}

// MARK: - 互動星星評分
struct InteractiveStarRating: View {
    @Binding var score: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: i <= score ? "star.fill" : "star")
                    .foregroundStyle(i <= score ? Color.yellow : Color(.systemGray4))
                    .font(.title3)
                    .onTapGesture { score = i }
            }
        }
    }
}

// MARK: - 學校搜尋 Sheet
struct SchoolPickerSheet: View {
    let schools: [SchoolConfig]
    @Binding var selected: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [SchoolConfig] {
        query.isEmpty ? schools : schools.filter { $0.name.localizedStandardContains(query) }
    }

    var body: some View {
        NavigationStack {
            List(filtered, id: \.name) { school in
                Button {
                    selected = school.name
                    dismiss()
                } label: {
                    HStack {
                        Text(school.name)
                            .foregroundStyle(.primary)
                        Spacer()
                        if school.name == selected {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "搜尋學校")
            .navigationTitle("選擇學校")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 檢舉 Sheet
struct ReportSheet: View {
    let context: ReportContext
    @EnvironmentObject var apiService: APIService
    @Environment(\.dismiss) private var dismiss

    private let reasons = ["不當內容", "垃圾內容", "錯誤資訊", "騷擾", "其他"]
    @State private var reason = "不當內容"
    @State private var description = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("檢舉原因") {
                    Picker("原因", selection: $reason) {
                        ForEach(reasons, id: \.self) { Text($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section("補充說明（選填）") {
                    TextField("請輸入補充說明", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        if isSubmitting {
                            HStack { Spacer(); ProgressView(); Spacer() }
                        } else {
                            Text("送出檢舉")
                                .frame(maxWidth: .infinity, alignment: .center)
                                .fontWeight(.semibold)
                                .foregroundStyle(.red)
                        }
                    }
                    .disabled(isSubmitting)
                }
            }
            .navigationTitle("檢舉")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .alert("送出失敗", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("確定", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func submit() async {
        isSubmitting = true
        errorMessage = nil
        do {
            try await apiService.reportContent(
                restaurantID: context.restaurantID,
                restaurantEvaluateID: context.restaurantEvaluateID,
                restaurantMenuID: context.restaurantMenuID,
                forumPostID: context.forumPostID,
                forumMessageID: context.forumMessageID,
                reason: reason,
                description: description.isEmpty ? nil : description
            )
            dismiss()
        } catch {
            print("❌ [UI] reportContent failed: \(error)")
            errorMessage = error.localizedDescription
        }
        isSubmitting = false
    }
}
