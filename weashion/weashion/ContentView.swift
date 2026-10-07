import SwiftUI


struct ContentView: View {
    
    // 위치 관리
    @StateObject private var locationManager =
        LocationManager()
    
    
    // 날씨 관리
    @StateObject private var weatherManager =
        WeatherManager()
    
    
    // 사용자의 신체 정보
    @State private var bodyData =
        UserBody()

    @State private var mannequinBase =
        MannequinBase.male
    
    
    // 캐릭터 편집 화면 표시 여부
    @State private var showEditor =
        false
    
    
    // 현재 날씨
    private var weather: WeatherInfo {
        
        weatherManager.weather
            ?? WeatherInfo.sample
    }
    
    
    // 추천 Outfit
    private var outfit: Outfit {
        
        OutfitRecommendation.recommend(
            weather: weather
        )
    }
    
    
    var body: some View {
        
        NavigationStack {
            
            ScrollView {
                
                VStack(spacing: 16) {
                    
                    // ----------------------------
                    // 날씨 Header
                    // ----------------------------
                    
                    weatherHeader
                    
                    
                    // ----------------------------
                    // 3D Avatar
                    // ----------------------------
                    
                    
                    
                    // ----------------------------
                    // 오늘의 Outfit
                    // ----------------------------
                    
                    outfitCard
                    
                    
                    // ----------------------------
                    // Weather Scene
                    // ----------------------------
                    
                    WEASHIONSceneView(
                        bodyData: bodyData,
                        mannequinBase: mannequinBase,
                        weather: weather
                    )
                    
                    
                    // ----------------------------
                    // 캐릭터 수정
                    // ----------------------------
                    
                    Button {
                        
                        showEditor = true
                        
                    } label: {
                        
                        Text("Customize My Avatar")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            
            
            .navigationTitle("WEASHION")
            
            
            // 캐릭터 수정 화면
            .sheet(
                isPresented: $showEditor
            ) {
                
                NavigationStack {
                    
                    BodyEditorView(
                        bodyData: $bodyData,
                        mannequinBase: $mannequinBase
                    )
                }
            }
            
            
            // 앱이 실행되면 위치 요청
            .task {
                
                locationManager.requestLocation()
            }
            
            
            // 위치가 변경되면 날씨 요청
            .onChange(
                of: locationManager.location
            ) { _, newLocation in
                
                guard let newLocation else {
                    return
                }
                
                
                Task {
                    
                    await weatherManager.loadWeather(
                        for: newLocation
                    )
                }
            }
        }
    }
    
    
    // MARK: - Weather Header
    
    private var weatherHeader: some View {
        
        VStack(
            alignment: .leading,
            spacing: 6
        ) {
            
            HStack {
                
                VStack(
                    alignment: .leading
                ) {
                    
                    Text(
                        weather.locationName
                    )
                    .font(.headline)
                    
                    
                    Text(
                        weather.condition
                    )
                    .foregroundStyle(
                        .secondary
                    )
                }
                
                
                Spacer()
                
                
                Text(
                    "\(weather.temperature, specifier: "%.0f")°"
                )
                .font(
                    .system(
                        size: 42,
                        weight: .bold
                    )
                )
            }
            
            
            HStack {
                
                Label(
                    "\(weather.feelsLike, specifier: "%.0f")° feels like",
                    systemImage: "thermometer.medium"
                )
                
                
                Spacer()
                
                
                Label(
                    "\(weather.windSpeed, specifier: "%.1f") m/s",
                    systemImage: "wind"
                )
            }
            .font(.caption)
            .foregroundStyle(
                .secondary
            )
        }
    }
    
    
    // MARK: - Outfit Card
    
    private var outfitCard: some View {
        
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            
            Text("Today's Outfit")
                .font(.title3.bold())
            
            
            outfitRow(
                "Top",
                outfit.top
            )
            
            
            if let outer = outfit.outer {
                
                outfitRow(
                    "Outer",
                    outer
                )
            }
            
            
            outfitRow(
                "Bottom",
                outfit.bottom
            )
            
            
            outfitRow(
                "Shoes",
                outfit.shoes
            )
            
            
            Divider()
            
            
            Text(outfit.reason)
                .font(.subheadline)
                .foregroundStyle(
                    .secondary
                )
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .padding()
        .background(.thinMaterial)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 20
            )
        )
    }
    
    
    // MARK: - Outfit Row
    
    private func outfitRow(
        _ category: String,
        _ item: String
    ) -> some View {
        
        HStack {
            
            Text(category)
                .foregroundStyle(
                    .secondary
                )
            
            
            Spacer()
            
            
            Text(item)
                .fontWeight(.medium)
        }
    }
}
