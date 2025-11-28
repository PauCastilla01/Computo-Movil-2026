// MatchSeguraApp.swift
// Versión Girly Aesthetic 💖 (compatible iOS 17+)
//

import SwiftUI
import MapKit
import CoreLocation

// MARK: - 🔑 Clave de API
let GEMINI_API_KEY = "TU_API_KEY_AQUI"

// MARK: - 🔐 Authentication Manager
// Maneja el estado de la sesión
@Observable
final class AuthManager {
    var isLoggedIn: Bool = false
    
    func login() {
        print("Intentando iniciar sesión...")
        isLoggedIn = true
    }
    
    func register() {
        print("Intentando registrar nuevo usuario...")
        isLoggedIn = true
    }
}

// MARK: - 🌍 Location Manager
@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {
    var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 19.4326, longitude: -99.1332),
        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
    )
    private let manager = CLLocationManager()
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.first else { return }
        Task { @MainActor in
            if self.region.span.latitudeDelta == 0.02 {
                 self.region.center = loc.coordinate
            }
        }
    }
    
    // CORRECCIÓN DE ZOOM: Acercamos el mapa para que se vean los alrededores del estadio
    func centerMap(on coordinate: CLLocationCoordinate2D) {
        region.center = coordinate
        // Zoom mucho más cercano (0.005) para ver los alrededores inmediatos
        region.span = MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
        manager.stopUpdatingLocation()
    }
    
    func startTrackingUser() {
        manager.startUpdatingLocation()
    }
}


// MARK: - 📍 Models

// Implementación manual de Codable para manejar CLLocationCoordinate2D
struct Incident: Identifiable, Codable {
    let id: UUID
    let type: String
    let description: String
    let coordinate: CLLocationCoordinate2D
    let timestamp: Date
    let anonymous: Bool
    
    var location: CLLocation {
        CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    enum CodingKeys: String, CodingKey {
        case id, type, description, coordinate_latitude, coordinate_longitude, timestamp, anonymous
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        description = try container.decode(String.self, forKey: .description)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        anonymous = try container.decode(Bool.self, forKey: .anonymous)

        let lat = try container.decode(Double.self, forKey: .coordinate_latitude)
        let lon = try container.decode(Double.self, forKey: .coordinate_longitude)
        coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(description, forKey: .description)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(anonymous, forKey: .anonymous)
        
        try container.encode(coordinate.latitude, forKey: .coordinate_latitude)
        try container.encode(coordinate.longitude, forKey: .coordinate_longitude)
    }
    
    init(type: String, description: String, coordinate: CLLocationCoordinate2D, timestamp: Date, anonymous: Bool = true) {
        self.id = UUID()
        self.type = type
        self.description = description
        self.coordinate = coordinate
        self.timestamp = timestamp
        self.anonymous = anonymous
    }
}

// NUEVO MODELO: Compañera
struct Companion: Identifiable {
    let id = UUID()
    let name: String
    let status: String
    let coordinate: CLLocationCoordinate2D
    let distance: String // Distancia simulada
}

// NUEVO: Wrapper para combinar Incidentes, Compañeras y ESTADIO (para el mapa)
enum MapItem: Identifiable {
    case incident(Incident)
    case companion(Companion)
    case stadium(CLLocationCoordinate2D, String) // Coordenadas y Nombre
    
    var id: UUID {
        switch self {
        case .incident(let i): return i.id
        case .companion(let c): return c.id
        case .stadium(_, _): return UUID() // Generar un ID único para el estadio
        }
    }
    
    var coordinate: CLLocationCoordinate2D {
        switch self {
        case .incident(let i): return i.coordinate
        case .companion(let c): return c.coordinate
        case .stadium(let coord, _): return coord
        }
    }
}

struct HelpPlace: Identifiable {
    let id = UUID()
    let name: String
    let type: String
    let coordinate: CLLocationCoordinate2D
}

struct Stadium {
    let name: String
    let city: String
    let coordinate: CLLocationCoordinate2D
}

// Modelo simplificado para la respuesta de la API (estable)
struct OpenAIResponse: Codable, Sendable {
    struct Choice: Codable, Sendable {
        struct Message: Codable, Sendable { let role, content: String }
        let message: Message
    }
    let choices: [Choice]
}

// MARK: - 🧠 ViewModel
@Observable
final class AppViewModel {
    
    // --- APP DATA ---
    var incidents: [Incident] = [
        // ⭐️ DATOS DE EJEMPLO DE REPORTES PARA "MIS REPORTES" ⭐️
        Incident(type: "Acoso Verbal", description: "Ocurrió cerca del módulo 3, el sujeto escapó hacia la avenida. Avisé a seguridad.", coordinate: CLLocationCoordinate2D(latitude: 19.3810, longitude: -99.1755), timestamp: Calendar.current.date(byAdding: .hour, value: -2, to: Date())!),
        Incident(type: "Robo de Celular", description: "El incidente fue a la salida del estacionamiento VIP. Sujeto en moto.", coordinate: CLLocationCoordinate2D(latitude: 19.3800, longitude: -99.1760), timestamp: Calendar.current.date(byAdding: .day, value: -1, to: Date())!),
        Incident(type: "Violencia Física", description: "Presencié una pelea en las gradas bajas. Intervino la policía. Reporte anónimo.", coordinate: CLLocationCoordinate2D(latitude: 19.3815, longitude: -99.1770), timestamp: Calendar.current.date(byAdding: .day, value: -3, to: Date())!),
        Incident(type: "Acoso Físico", description: "Toques indebidos en la zona de baños. La persona fue confrontada y huyó.", coordinate: CLLocationCoordinate2D(latitude: 19.3805, longitude: -99.1780), timestamp: Calendar.current.date(byAdding: .hour, value: -8, to: Date())!),
        Incident(type: "Intento de Fraude", description: "Vendedor de boletos falsos en la entrada principal, zona de taquillas.", coordinate: CLLocationCoordinate2D(latitude: 19.3820, longitude: -99.1768), timestamp: Calendar.current.date(byAdding: .hour, value: -4, to: Date())!)
    ]
    var helpPlaces: [HelpPlace] = [
        HelpPlace(name: "💒 Hospital General", type: "Hospital", coordinate: CLLocationCoordinate2D(latitude: 19.427, longitude: -99.135)),
        HelpPlace(name: "👮‍♀️ Módulo de Seguridad", type: "Módulo", coordinate: CLLocationCoordinate2D(latitude: 19.44, longitude: -99.14))
    ]
    
    // CORRECCIÓN: Ubicaciones de compañeras muy cercanas al Estadio Banorte (19.3809, -99.1764)
    var nearbyCompanions: [Companion] = [
        Companion(name: "Ana Sofía", status: "Buscando acompañamiento a la salida", coordinate: CLLocationCoordinate2D(latitude: 19.3812, longitude: -99.1760), distance: "50 m"),
        Companion(name: "Mariana L.", status: "Lista para ir a la estación de metro", coordinate: CLLocationCoordinate2D(latitude: 19.3805, longitude: -99.1769), distance: "120 m"),
        Companion(name: "Ximena R.", status: "Disponible en la zona de autobuses", coordinate: CLLocationCoordinate2D(latitude: 19.3808, longitude: -99.1764), distance: "30 m")
    ]
    
    var showingReport = false
    var showingCompanion = false // Controla la visibilidad de la nueva CompanionView
    var showingHelp = false
    
    // Simplificamos el estado de traducción a una sola frase (sin persistencia)
    var latestTranslation: String?
    var latestOriginal: String?
    
    var isTranslating: Bool = false
    
    // Controla el flujo de navegación post-login
    var showOnboarding = true
    var showStadiumSelector = false
    var showingTranslator = false
    
    // NUEVO: Estado para mostrar el modal de alerta de pánico
    var showAlertSent = false
    
    // NUEVO: Estado para guardar el estadio seleccionado y mostrar su marcador
    var selectedStadiumLocation: CLLocationCoordinate2D?
    var selectedStadiumName: String?
    
    let stadiums: [Stadium] = [
        Stadium(name: "Estadio BBVA", city: "MTY", coordinate: CLLocationCoordinate2D(latitude: 25.6565, longitude: -100.2018)),
        Stadium(name: "Estadio Akron", city: "GDL", coordinate: CLLocationCoordinate2D(latitude: 20.6276, longitude: -103.4912)),
        Stadium(name: "Estadio Banorte", city: "CDMX", coordinate: CLLocationCoordinate2D(latitude: 19.3809, longitude: -99.1764))
    ]
    
    func addIncident(type: String, description: String, location: CLLocationCoordinate2D, anonymous: Bool = true) {
        let inc = Incident(type: type, description: description, coordinate: location, timestamp: Date(), anonymous: anonymous)
        // Agregamos el nuevo incidente al inicio de la lista para que aparezca primero
        incidents.insert(inc, at: 0)
    }
    
    // 🌸 Traducción con API de GEMINI (sin guardar en Firestore)
    func translate(message: String, from: String, to: String) async {
        await MainActor.run {
            self.isTranslating = true
            self.latestTranslation = nil
            self.latestOriginal = nil
        }
        
        let userQuery = "Translate the following phrase from \(from) to \(to): \(message). Provide only the translated text, nothing else."
        
        let payload: [String: Any] = [
            "contents": [[ "parts": [["text": userQuery]] ]],
            "tools": [[ "google_search": [:] ]]
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else {
            await MainActor.run { self.isTranslating = false }
            return
        }
        
        let apiKey = "" // El Canvas proporciona la clave en runtime
        let apiUrl = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-09-2025:generateContent?key=\(apiKey)"
        
        var request = URLRequest(url: URL(string: apiUrl)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            
            if let result = try? JSONDecoder().decode(OpenAIResponse.self, from: data) {
                let translatedText = result.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? "❌ Error en traducción"
                
                await MainActor.run {
                    self.latestTranslation = translatedText
                    self.latestOriginal = message
                }

            } else {
                print("Error: No se pudo decodificar la respuesta de Gemini.")
            }
        } catch {
            print("Error de red al traducir: \(error.localizedDescription)")
        }
        
        await MainActor.run {
            self.isTranslating = false
        }
    }
    
    // 🚨 MODIFICADO: Muestra el modal de confirmación y lo oculta después de 3 segundos
    func sendPanicAlert(location: CLLocationCoordinate2D) {
        print("🚨 Enviando alerta desde: \(location.latitude), \(location.longitude)")
        self.showAlertSent = true // Muestra la alerta

        // Simular el envío y ocultar la alerta después de 3 segundos
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.showAlertSent = false
            print("Alerta de pánico oculta.")
        }
    }
}

// MARK: - 🏟️ Floating Emojis Helper View (Confeti de Estadios o Balones)
struct FloatingEmojisView: View {
    let emoji: String
    @State private var offsetProgress: [CGFloat] = Array(repeating: 0, count: 20)
    
    var body: some View {
        ZStack {
            ForEach(0..<offsetProgress.count, id: \.self) { index in
                let initialX = CGFloat.random(in: -200...200)
                let initialY = CGFloat.random(in: -400...400)
                let duration = Double.random(in: 15...30)
                let travelRange = CGFloat.random(in: 100...250)
                
                Text(emoji)
                    .font(.system(size: CGFloat.random(in: 25...40)))
                    .opacity(CGFloat.random(in: 0.4...0.8))
                    .rotationEffect(.degrees(Double.random(in: -30...30)))
                    .offset(x: initialX, y: initialY + offsetProgress[index] * travelRange)
                    .animation(
                        Animation.linear(duration: duration)
                            .repeatForever(autoreverses: true),
                        value: offsetProgress[index]
                    )
            }
        }
        .blur(radius: 1)
        .opacity(0.7)
        .onAppear {
            for i in 0..<offsetProgress.count {
                DispatchQueue.main.async {
                    self.offsetProgress[i] = 1.0
                }
            }
        }
    }
}


// MARK: - 🩷 LOGIN VIEW (AuthView)
struct AuthView: View {
    @Bindable var authManager: AuthManager
    @State private var email = ""
    @State private var password = ""
    
    var body: some View {
        ZStack {
            LinearGradient(colors: [.purple.opacity(0.2), .pink.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            
            FloatingEmojisView(emoji: "⚽️")
            
            VStack(spacing: 25) {
                
                Text("Bienvenida a\nMatch Segura")
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundColor(Color(red: 0.5, green: 0.2, blue: 0.7))
                    .padding(.top, 50)
                
                VStack(spacing: 18) {
                    
                    HStack {
                        Image(systemName: "envelope.fill").foregroundColor(.pink)
                        TextField("Correo Electrónico", text: $email)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .fontDesign(.rounded)
                    }
                    .padding().background(Color.white.opacity(0.85)).cornerRadius(12).shadow(color: .pink.opacity(0.25), radius: 6, x: 0, y: 6)
                    
                    HStack {
                        Image(systemName: "lock.fill").foregroundColor(.purple)
                        SecureField("Contraseña", text: $password)
                            .fontDesign(.rounded)
                    }
                    .padding().background(Color.white.opacity(0.85)).cornerRadius(12).shadow(color: .purple.opacity(0.25), radius: 6, x: 0, y: 6)
                    
                    Button(action: {
                        authManager.login()
                    }, label: {
                        Text("🔒 Iniciar Sesión")
                            .font(.headline).fontDesign(.rounded).foregroundColor(.white).frame(maxWidth: .infinity).padding()
                            .background(Color.pink.opacity(0.9)).cornerRadius(15).shadow(color: .pink.opacity(0.6), radius: 10)
                    })
                    .padding(.top, 15)

                    Button("✨ Crear Cuenta Nueva") {
                        authManager.register()
                    }
                    .font(.subheadline).fontWeight(.medium).fontDesign(.rounded)
                    .foregroundColor(Color(red: 0.5, green: 0.2, blue: 0.7))
                }
                .padding(30).background(.ultraThinMaterial).cornerRadius(25).padding(.horizontal, 25)
                
                Spacer()
            }
        }
    }
}

// MARK: - 🚀 Vista de Bienvenida (Onboarding)
struct WelcomeOnboardingView: View {
    @Bindable var vm: AppViewModel
    
    var body: some View {
        ZStack {
            LinearGradient(colors: [.purple.opacity(0.2), .pink.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            FloatingEmojisView(emoji: "⚽️")
            
            VStack {
                Text("¡Bienvenida a tu app segura! 💖")
                    .font(.largeTitle).fontWeight(.heavy).foregroundColor(Color(red: 0.5, green: 0.2, blue: 0.7)).fontDesign(.rounded).padding(.top, 40)
                
                VStack(spacing: 20) {
                    
                    Image(systemName: "shield.righthalf.filled")
                        .resizable().scaledToFit().frame(width: 60, height: 60).foregroundColor(.pink).padding(.bottom, 10)
                    
                    Text("Match Segura es un mapa colaborativo con funcionalidades clave para tu seguridad:")
                        .font(.title3).fontWeight(.semibold).foregroundColor(.primary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    
                    HStack {
                        Spacer()
                        VStack(alignment: .leading, spacing: 10) {
                            Text("• Reportes de incidentes en tiempo real").fixedSize(horizontal: false, vertical: true)
                            Text("• Botón de pánico (ubicación a contactos de confianza y autoridades)").fixedSize(horizontal: false, vertical: true)
                            Text("• Sistema de acompañamiento entre aficionadas").fixedSize(horizontal: false, vertical: true)
                            Text("• Reportes anónimos de acoso, robo o violencia").fixedSize(horizontal: false, vertical: true)
                            Text("• Traducción rápida y directorio de ayuda").fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.body).padding(.horizontal, 10).foregroundColor(.secondary)
                        Spacer()
                    }
                    
                    Spacer()
                    
                    Text("¡Cuidémonos todas!")
                        .font(.headline).fontWeight(.bold).foregroundColor(.purple)
                    
                    Button(action: {
                        vm.showOnboarding = false
                        vm.showStadiumSelector = true
                    }, label: {
                        Text("Navegar Protegida 🌐")
                            .font(.headline).fontDesign(.rounded).foregroundColor(.white).frame(maxWidth: .infinity).padding()
                            .background(Color.pink.opacity(0.9)).cornerRadius(15).shadow(color: .pink.opacity(0.6), radius: 6)
                    })
                }
                .padding(30).frame(maxWidth: .infinity).background(.regularMaterial).cornerRadius(25).padding(.horizontal, 25).padding(.vertical, 20)
                
                Spacer()
            }
        }
    }
}

// MARK: - 🏟️ Selector de Estadio
struct StadiumSelectorView: View {
    @Bindable var vm: AppViewModel
    @Bindable var locationManager: LocationManager
    
    var body: some View {
        ZStack {
            LinearGradient(colors: [.purple.opacity(0.2), .pink.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            FloatingEmojisView(emoji: "🏟️")
            
            VStack {
                Spacer()

                VStack {
                    Text("Selecciona tu Estadio 📍")
                        .font(.system(size: 32, weight: .heavy, design: .rounded)).multilineTextAlignment(.center).foregroundColor(Color(red: 0.5, green: 0.2, blue: 0.7)).padding(.top, 40)
                    
                    Text("El mapa se centrará en tu ubicación seleccionada para ver reportes cercanos.")
                        .font(.subheadline).foregroundColor(.gray).multilineTextAlignment(.center).padding(.horizontal, 40)

                    VStack(spacing: 15) {
                        ForEach(vm.stadiums, id: \.name) { stadium in
                            Button(action: {
                                locationManager.centerMap(on: stadium.coordinate)
                                vm.selectedStadiumLocation = stadium.coordinate // Guardar ubicación para el marcador
                                vm.selectedStadiumName = stadium.name // Guardar nombre
                                vm.showStadiumSelector = false
                            }, label: {
                                HStack {
                                    Image(systemName: "map.fill")
                                    Text("\(stadium.name) (\(stadium.city))")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                }
                                .font(.headline).fontDesign(.rounded).padding().frame(maxWidth: .infinity)
                                .background(Color.white.opacity(0.8)).cornerRadius(12).foregroundColor(Color(red: 0.5, green: 0.2, blue: 0.7)).shadow(color: .purple.opacity(0.2), radius: 4)
                            })
                        }
                    }
                    .padding(30).frame(maxWidth: .infinity).background(.regularMaterial).cornerRadius(25).padding(.horizontal, 25).padding(.vertical, 20)
                }
                
                Spacer()
            }
        }
    }
}

// MARK: - 🌐 Vista de Traducción (Versión sin persistencia)
struct TranslatorView: View {
    @Bindable var vm: AppViewModel
    @State private var inputText: String = ""
    @State private var sourceLanguage: String = "Spanish"
    @State private var targetLanguage: String = "English"
    
    let languages = ["Spanish", "English", "French", "German", "Portuguese"]
    
    // --- DATOS DE EJEMPLO DE TRADUCCIÓN (HISTORIAL) ---
    private let sampleHistory: [(original: String, translated: String)] = [
        (original: "Necesito ayuda, hay un incidente cerca de la puerta 5.", translated: "I need help, there is an incident near gate 5."),
        (original: "Por favor, quédate conmigo. Estoy segura.", translated: "Please stay with me. I am safe."),
        (original: "No puedo encontrar mi camino de salida.", translated: "I can't find my way out.")
    ]
    
    var body: some View {
        ZStack {
            PastelSheet {
                VStack(spacing: 20) {
                    Text("🌐 Traducción Rápida")
                        .font(.title).bold().foregroundColor(.purple)
                    
                    // Selector de Idiomas
                    HStack {
                        Picker("De", selection: $sourceLanguage) { ForEach(languages, id: \.self) { Text($0) } }.pickerStyle(.menu)
                        Image(systemName: "arrow.right.circle.fill").foregroundColor(.pink)
                        Picker("A", selection: $targetLanguage) { ForEach(languages, id: \.self) { Text($0) } }.pickerStyle(.menu)
                        
                        Button(action: {
                            let temp = sourceLanguage
                            sourceLanguage = targetLanguage
                            targetLanguage = temp
                        }) {
                            Image(systemName: "arrow.up.arrow.down").foregroundColor(.purple)
                        }
                    }.padding(.horizontal)
                    
                    // Área de Introducción de Texto
                    TextEditor(text: $inputText).frame(height: 100).border(Color.gray.opacity(0.3), width: 1).cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.pink, lineWidth: 1)).padding(.horizontal)
                    
                    Button(action: {
                        guard !inputText.isEmpty else { return }
                        Task {
                            await vm.translate(message: inputText, from: sourceLanguage, to: targetLanguage)
                        }
                    }, label: {
                        if vm.isTranslating {
                            ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white)).frame(maxWidth: .infinity)
                        } else {
                            Text("Traducir a \(targetLanguage) ✨")
                                .font(.headline).fontDesign(.rounded).foregroundColor(.white).frame(maxWidth: .infinity)
                        }
                    })
                    .padding().background(Color.pink.opacity(0.9)).cornerRadius(15).shadow(color: .pink.opacity(0.6), radius: 6)
                    .disabled(vm.isTranslating || inputText.isEmpty)
                    
                    // Resultado de la Traducción (Última frase)
                    Text("Última Traducción:")
                        .font(.title2).bold().foregroundColor(.purple)
                    
                    if let translated = vm.latestTranslation, let original = vm.latestOriginal {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(translated).font(.headline).foregroundColor(.primary)
                            Text("(\(original))").font(.caption).foregroundColor(.secondary)
                        }
                        .padding(8).background(Color.white.opacity(0.9)).cornerRadius(8).shadow(radius: 1)
                    } else {
                         Text("Introduce y traduce una frase.")
                            .foregroundColor(.gray)
                    }

                    // Historial de Traducciones de Ejemplo
                    Text("Ejemplos de Frases de Seguridad:")
                        .font(.title2).bold().foregroundColor(.purple)
                        .padding(.top, 10)
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(sampleHistory, id: \.original) { item in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.translated).font(.headline).foregroundColor(.primary)
                                    Text("(\(item.original))").font(.caption).foregroundColor(.secondary)
                                }
                                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.white.opacity(0.9)).cornerRadius(8).shadow(radius: 1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    Spacer()
                }
            }
        }
    }
}


// MARK: - 🚨 Vista de Alerta de Pánico
struct PanicAlertView: View {
    @Bindable var vm: AppViewModel
    var location: CLLocationCoordinate2D
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.shield.fill")
                .resizable().frame(width: 80, height: 80).foregroundColor(.red)
            
            Text("🚨 ¡ALERTA ENVIADA!")
                .font(.largeTitle).fontWeight(.heavy).foregroundColor(.red)
            
            Text("Tu ubicación y mensaje de auxilio han sido enviados exitosamente:")
                .font(.headline).multilineTextAlignment(.center)
            
            VStack(alignment: .leading, spacing: 5) {
                Text("• Contactos de Confianza")
                Text("• Autoridades de Seguridad")
                Text("• **Ubicación:** \(String(format: "Lat: %.4f, Lon: %.4f", location.latitude, location.longitude))")
            }
            .font(.subheadline).foregroundColor(.gray)
            
            Text("La ayuda está en camino. Por favor, mantente segura.")
                .font(.callout).italic().foregroundColor(.purple)
        }
        .padding(40)
        .background(.regularMaterial)
        .cornerRadius(25)
        .shadow(color: .red.opacity(0.4), radius: 15)
        .transition(.scale.combined(with: .opacity)) // Animación suave
    }
}


// MARK: - 🌸 ContentView (El contenedor principal del flujo)
struct ContentView: View {
    @State private var vm = AppViewModel()
    @State private var locationManager = LocationManager()
    @State private var newMessage = "Necesito ayuda, estoy en riesgo cerca del Estadio Azteca."
    
    var body: some View {
        ZStack {
            if vm.showOnboarding {
                WelcomeOnboardingView(vm: vm)
            } else if vm.showStadiumSelector {
                StadiumSelectorView(vm: vm, locationManager: locationManager)
            }
            else {
                // Mapa y herramientas
                MapView(vm: vm, locationManager: locationManager, newMessage: $newMessage)
                
                // Overlay de la Alerta de Pánico
                if vm.showAlertSent {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    PanicAlertView(vm: vm, location: locationManager.region.center)
                        .zIndex(10) // Asegura que esté por encima de todo
                }
            }
        }
        .sheet(isPresented: $vm.showingTranslator) {
            TranslatorView(vm: vm)
        }
    }
}

// Extraemos la lógica del mapa a una vista separada para limpieza
struct MapView: View {
    @Bindable var vm: AppViewModel
    @Bindable var locationManager: LocationManager
    @Binding var newMessage: String
    
    // Propiedad calculada para obtener la lista combinada y tipada para el mapa
    private var mapItems: [MapItem] {
        var items: [MapItem] = []
        
        // 1. Agregar Incidentes y Compañeras
        items.append(contentsOf: vm.incidents.map { MapItem.incident($0) })
        items.append(contentsOf: vm.nearbyCompanions.map { MapItem.companion($0) })
        
        // 2. Agregar el Marcador Fijo del Estadio (si está seleccionado)
        if let coord = vm.selectedStadiumLocation, let name = vm.selectedStadiumName {
            items.append(MapItem.stadium(coord, name))
        }
        
        return items
    }
    
    var body: some View {
        return NavigationStack {
            ZStack {
                LinearGradient(colors: [.purple.opacity(0.2), .pink.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
                
                // --- Mapa con anotaciones basadas en MapItem ---
                Map(coordinateRegion: $locationManager.region,
                    showsUserLocation: true,
                    annotationItems: mapItems) { item in
                    
                    // Manejar la anotación según el tipo (USO DE MAPANNOTATION SÓLIDO)
                    MapAnnotation(coordinate: item.coordinate) {
                        switch item {
                        case .incident(let incident):
                            // Marcador Rosa para Incidentes (Custom Icon/Color)
                            Image(systemName: "exclamationmark.triangle.fill")
                                .resizable().frame(width: 25, height: 25)
                                .foregroundColor(.pink)
                                .background(Circle().fill(.white).opacity(0.8))
                                .shadow(radius: 2)

                        case .companion(let companion):
                            // Marcador de Balón de Fútbol para Compañeras
                            VStack(spacing: 0) {
                                Text("⚽️") // Marcador de Balón
                                    .font(.system(size: 25))
                                Text(companion.name.prefix(4) + ".") // Nombre corto
                                    .font(.caption2)
                                    .foregroundColor(.primary)
                            }
                        
                        case .stadium(_, let name):
                            // Marcador Fijo del Estadio
                            VStack(spacing: 4) {
                                Text("🏟️") // Emoji de Estadio
                                    .font(.system(size: 40))
                                Text(name)
                                    .font(.caption).bold()
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.white.opacity(0.8)).cornerRadius(6)
                            }
                            .shadow(radius: 3)
                        }
                    }
                }
                .ignoresSafeArea()
                
                // Botón de Regreso al Selector de Estadio
                VStack {
                    HStack {
                        Button(action: {
                            vm.showStadiumSelector = true
                            locationManager.startTrackingUser()
                        }, label: {
                            Image(systemName: "arrow.left.circle.fill")
                                .resizable().frame(width: 40, height: 40).foregroundColor(.pink).padding(.leading, 15).shadow(radius: 5)
                        })
                        Spacer()
                    }
                    .padding(.top, 10)
                    Spacer()
                }

                
                VStack {
                    Spacer()
                    
                    // 🚨 Botón de Pánico
                    Button(action: {
                        vm.sendPanicAlert(location: locationManager.region.center)
                    }, label: {
                        Text("🚨 ¡Ayuda Inmediata!")
                            .font(.headline).fontDesign(.rounded).padding().frame(maxWidth: .infinity)
                            .background(Color.red.opacity(0.9)).foregroundColor(.white).clipShape(Capsule()).shadow(radius: 5)
                    })
                    .padding(.horizontal)
                    
                    // 🌸 Barra inferior
                    VStack(spacing: 10) {
                        HStack {
                            // SINTAXIS EXPLÍCITA EN TODOS LOS BOTONES
                            Button(action: { vm.showingReport = true }, label: { Text("📍 Reportar") })
                            Spacer()
                            Button(action: { vm.showingCompanion = true }, label: { Text("💞 Acompañamiento") })
                            Spacer()
                            Button(action: { vm.showingTranslator = true }, label: { Text("🌐 Traducir") })
                            Spacer()
                            Button(action: { vm.showingHelp = true }, label: { Text("🏥 Ayuda") })
                        }
                        .font(.headline).fontDesign(.rounded).padding().background(Color.white.opacity(0.6)).clipShape(RoundedRectangle(cornerRadius: 18)).shadow(radius: 4)
                    }
                }
                .padding(.bottom, 20)
            }
            .navigationBarHidden(true)
            .fontDesign(.rounded)
            .sheet(isPresented: $vm.showingReport) {
                PastelSheet { ReportFormView(vm: vm, location: locationManager.region.center) }
            }
            .sheet(isPresented: $vm.showingCompanion) {
                PastelSheet { CompanionView(vm: vm) } // Pasa el ViewModel aquí
            }
            .sheet(isPresented: $vm.showingHelp) {
                PastelSheet { HelpView() }
            }
        }
    }
}


// MARK: - 🎀 Fondo Pastel Reutilizable
struct PastelSheet<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    
    var body: some View {
        ZStack {
            LinearGradient(colors: [
                Color(red: 0.94, green: 0.90, blue: 0.98),
                Color(red: 0.92, green: 0.88, blue: 0.97)
            ], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            
            content.fontDesign(.rounded).padding()
        }
    }
}

// MARK: - 📝 Report Form
struct ReportFormView: View {
    @Bindable var vm: AppViewModel
    var location: CLLocationCoordinate2D
    @State private var desc = ""
    
    // Función para obtener la etiqueta de tiempo relativa
    func timeAgo(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                
                // --- 1. SECCIÓN DE NUEVO REPORTE ---
                VStack(spacing: 15) {
                    Text("📍 Nuevo Reporte")
                        .font(.title).bold().foregroundColor(.purple)
                    
                    TextEditor(text: $desc).frame(height: 100).border(Color.gray.opacity(0.3), width: 1).cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.pink, lineWidth: 1))
                        .padding(.horizontal)
                    
                    Button("Enviar Anónimo 💌") {
                        vm.addIncident(type: "Incidente", description: desc, location: location, anonymous: true)
                        desc = "" // Limpiar el campo
                    }.buttonStyle(.borderedProminent).tint(.pink).shadow(radius: 4)
                }
                
                Divider()
                
                // --- 2. SECCIÓN DE MIS REPORTES (HISTORIAL) ---
                VStack(alignment: .leading, spacing: 15) {
                    Text("Mis Reportes (\(vm.incidents.count))")
                        .font(.title2).bold().foregroundColor(.purple)
                    
                    ForEach(vm.incidents.prefix(5)) { incident in // Mostramos solo los primeros 5
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(incident.type)
                                    .font(.headline)
                                    .foregroundColor(.pink)
                                Spacer()
                                Text(timeAgo(from: incident.timestamp))
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            Text(incident.description)
                                .font(.body)
                                .foregroundColor(.primary)
                            
                            HStack {
                                Text(incident.anonymous ? "Anónimo 👤" : "Público 📢")
                                    .font(.caption2)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(incident.anonymous ? Color.gray.opacity(0.1) : Color.purple.opacity(0.1))
                                    .cornerRadius(6)
                                
                                Spacer()
                                Text("Lat: \(String(format: "%.4f", incident.coordinate.latitude))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(12)
                        .background(Color.white.opacity(0.8))
                        .cornerRadius(12)
                        .shadow(radius: 2)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
    }
}

// MARK: - 🤝 Companion View (Panel de Compañeras Cercanas)
struct CompanionView: View {
    @Bindable var vm: AppViewModel
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("💞 Compañeras Cercanas")
                    .font(.title).bold().foregroundColor(.purple)
                
                Text("Conéctate con usuarias para acompañamiento seguro en tu zona.")
                    .multilineTextAlignment(.center).padding(.horizontal)
                
                // Botón para simular la búsqueda (lo que gatillaría la aparición en el mapa)
                Button("👭 Buscar ahora (3 encontradas)") {
                    // Acción: Simular recarga de lista o actualización de estado
                    print("Buscando compañeras seguras cerca del estadio...")
                }
                .buttonStyle(.borderedProminent).tint(.pink).shadow(radius: 4)
                
                Divider()
                
                // Lista de Compañeras
                VStack(alignment: .leading, spacing: 15) {
                    ForEach(vm.nearbyCompanions) { companion in
                        HStack(alignment: .top) {
                            Image(systemName: "figure.walk.circle.fill")
                                .resizable().frame(width: 30, height: 30).foregroundColor(.purple)
                            
                            VStack(alignment: .leading) {
                                Text(companion.name)
                                    .font(.headline).foregroundColor(.primary)
                                Text(companion.status)
                                    .font(.subheadline).foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing) {
                                Text(companion.distance)
                                    .font(.caption).fontWeight(.bold).foregroundColor(.pink)
                                
                                Button("Conectar 💬") {
                                    print("Mensaje enviado a \(companion.name)")
                                }
                                .font(.caption).padding(5).background(Color.pink.opacity(0.1)).cornerRadius(8)
                            }
                        }
                        .padding(12)
                        .background(Color.white.opacity(0.8)).cornerRadius(12).shadow(radius: 2)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
    }
}

// MARK: - ☎️ Help View
struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Group {
                    Text("🚨 Emergencias").font(.title2).bold().foregroundColor(.purple)
                    Text("📞 911 - Emergencias Generales")
                    Text("📞 089 - Denuncia Anónima")
                }
                Divider()
                
                Group {
                    Text("👩🏻‍🦱 Líneas Especializadas").font(.title2).bold().foregroundColor(.purple)
                    Text("📞 *765 - Línea Mujeres (24/7)")
                    Text("📞 55 5533 5533 - Consejo Ciudadano")
                }
                Divider()
                
                Group {
                    Text("💊 Asistencia y Salud").font(.title2).bold().foregroundColor(.purple)
                    Text("📞 55 4891 1166 - Asistencia Turística")
                    Text("📞 56 58 11 11 - LOCATEL")
                    Text("📞 53 95 11 11 - Cruz Roja")
                }
                Divider()
                
                Group {
                    Text("⚖️ Recursos de Justicia").font(.title2).bold().foregroundColor(.purple)
                    Text("📞 55 5346 8000 - Fiscalía Delitos Sexuales")
                    Text("📍 CJM Tlalpan, CDMX - 55 5200 9280")
                }
                Divider()
                
                Group {
                    Text("🏥 Hospitales Cercanos").font(.title2).bold().foregroundColor(.purple)
                    Text("🏥 Hospital Shriners México - 55 5424 7850")
                    Text("🏥 Hospital Tlalpan - 55 5594 1220")
                }
            }
            .font(.body).fontDesign(.rounded).padding()
        }
        .navigationTitle("💖 Líneas de Ayuda")
    }
}
