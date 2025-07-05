import SwiftUI
internal import Combine

// MARK: - App's Main Entry Point
// The app now starts with a TabView that holds all the main sections.

struct MainTabView: View {
    var body: some View {
        TabView {
            // Tab 1: The original dashboard
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "square.grid.2x2.fill")
                }
            
            // Tab 2: The new Journaling Guide feature
            JournalingGuideView()
                .tabItem {
                    Label("Sleep", systemImage: "bed.double.fill")
                }
            
            // Tab 3: Placeholder for Nutrition
            NutritionView()
                .tabItem {
                    Label("Nutrition", systemImage: "fork.knife")
                }
            
            // Tab 4: Placeholder for Fitness
            FitnessView()
                .tabItem {
                    Label("Fitness", systemImage: "figure.run")
                }
        }
        .accentColor(.blue) // Sets the color for the active tab icon
    }
}


// MARK: - Groq API Models & Secrets (Unchanged)

struct GroqRequest: Codable {
    let messages: [GroqMessage]
    let model: String
    let temperature: Double = 0.7
    let max_tokens: Int = 200
}
struct GroqMessage: Codable { let role: String; let content: String }
struct GroqResponse: Codable { let choices: [GroqChoice] }
struct GroqChoice: Codable { let message: ResponseMessage }
struct ResponseMessage: Codable { let content: String }

struct Secrets {
    static var groqApiKey: String? {
        guard let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path) as? [String: AnyObject] else {
            print("Error: Secrets.plist not found.")
            return nil
        }
        return dict["GROQ_API_KEY"] as? String
    }
}


// MARK: - Section 1: Dashboard View & ViewModel (Previously ApexView)

class DashboardViewModel: ObservableObject {
    @Published var sleepHours: Double = 7.5
    @Published var mealSummary: String = ""
    @Published var workoutSummary: String = ""
    @Published var healthScore: Int = 0
    @Published var morningBriefing: String = "Log your daily data and tap 'Generate Briefing' to get your personalized health insights."
    @Published var isLoading: Bool = false
    @Published var streakCount: Int = 0
    
    private let streakCountKey = "streakCount"
    private let lastBriefingDateKey = "lastBriefingDateKey"
    
    init() {
        loadStreak()
    }
    
    // ... (All functions like generateBriefing, loadStreak, etc. are unchanged)
    @MainActor
    func generateBriefing() async {
        isLoading = true
        guard let apiKey = Secrets.groqApiKey else {
            morningBriefing = "Error: GROQ_API_KEY not found in Secrets.plist."
            isLoading = false
            return
        }
        calculateHealthScore()
        let prompt = createPrompt()
        guard let url = URL(string: "https://api.groq.com/openai/v1/chat/completions") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let requestBody = GroqRequest(messages: [GroqMessage(role: "system", content: "You are Apex, a helpful health assistant. Analyze user logs for a 'Morning Briefing'. Be concise, positive, and connect the inputs."), GroqMessage(role: "user", content: prompt)], model: "llama3-8b-8192")
        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
            let (data, _) = try await URLSession.shared.data(for: request)
            let decodedResponse = try JSONDecoder().decode(GroqResponse.self, from: data)
            if let responseContent = decodedResponse.choices.first?.message.content {
                morningBriefing = responseContent.trimmingCharacters(in: .whitespacesAndNewlines)
                updateStreak()
            } else { morningBriefing = "Empty AI response." }
        } catch { morningBriefing = "Error: \(error.localizedDescription)" }
        isLoading = false
    }
    private func loadStreak() {
        let storedStreak = UserDefaults.standard.integer(forKey: streakCountKey)
        guard let lastDate = UserDefaults.standard.object(forKey: lastBriefingDateKey) as? Date else { self.streakCount = 0; return }
        if !Calendar.current.isDateInYesterday(lastDate) && !Calendar.current.isDateInToday(lastDate) {
            self.streakCount = 0
            UserDefaults.standard.set(0, forKey: streakCountKey)
        } else { self.streakCount = storedStreak }
    }
    private func updateStreak() {
        let today = Date()
        guard let lastDate = UserDefaults.standard.object(forKey: lastBriefingDateKey) as? Date else {
            streakCount = 1; saveStreak(count: 1, date: today); return
        }
        if Calendar.current.isDate(today, inSameDayAs: lastDate) { return }
        if Calendar.current.isDateInYesterday(lastDate) { streakCount += 1 } else { streakCount = 1 }
        saveStreak(count: streakCount, date: today)
    }
    private func saveStreak(count: Int, date: Date) {
        UserDefaults.standard.set(count, forKey: streakCountKey)
        UserDefaults.standard.set(date, forKey: lastBriefingDateKey)
    }
    private func calculateHealthScore() {
        var score = 0; let sleepScore = min(40, (self.sleepHours / 8.0) * 40); score += Int(sleepScore)
        if !self.mealSummary.trimmingCharacters(in: .whitespaces).isEmpty { score += 30 }
        if !self.workoutSummary.trimmingCharacters(in: .whitespaces).isEmpty { score += 30 }
        self.healthScore = min(100, score)
    }
    private func createPrompt() -> String {
        let nutritionLog = mealSummary.isEmpty ? "No food logged." : mealSummary
        let fitnessLog = workoutSummary.isEmpty ? "No workout logged." : workoutSummary
        return "Sleep: \(String(format: "%.1f", sleepHours)) hours\nNutrition: \(nutritionLog)\nFitness: \(fitnessLog)"
    }
}

struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()
    
    var body: some View {
        // Each tab gets its own NavigationView
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    HStack {
                        Spacer()
                        Image(systemName: "flame.fill")
                        Text("\(viewModel.streakCount)")
                        Spacer()
                    }
                    .font(.subheadline).fontWeight(.bold).foregroundColor(.orange).padding(.top, 4)
                    
                    BriefingCardView(score: viewModel.healthScore, briefing: viewModel.morningBriefing, isLoading: viewModel.isLoading)
                    
                    VStack(spacing: 20) {
                        LoggingModuleView(title: "Sleep", systemImageName: "bed.double.fill") {
                            VStack {
                                Text("\(String(format: "%.1f", viewModel.sleepHours)) hours").font(.headline)
                                Slider(value: $viewModel.sleepHours, in: 0...12, step: 0.5)
                            }
                        }
                        LoggingModuleView(title: "Nutrition", systemImageName: "fork.knife") {
                            TextField("e.g., Oatmeal, Chicken Salad", text: $viewModel.mealSummary, axis: .vertical).textFieldStyle(.roundedBorder)
                        }
                        LoggingModuleView(title: "Fitness", systemImageName: "figure.run") {
                            TextField("e.g., 3-mile run", text: $viewModel.workoutSummary, axis: .vertical).textFieldStyle(.roundedBorder)
                        }
                    }
                    Button(action: { Task { await viewModel.generateBriefing() } }) {
                        Text(viewModel.isLoading ? "Analyzing..." : "Generate Briefing").font(.headline).foregroundColor(.white).frame(maxWidth: .infinity).padding().background(Color.blue).cornerRadius(12)
                    }.disabled(viewModel.isLoading)
                }.padding()
            }
            .navigationTitle("Apex Dashboard")
            .background(Color(.systemGroupedBackground).edgesIgnoringSafeArea(.all))
        }
    }
}


// MARK: - Section 2: NEW Journaling Guide View & ViewModel

class JournalingViewModel: ObservableObject {
    @Published var userProblem: String = ""
    @Published var generatedQuestions: String = "Describe a problem or challenge you're facing to receive guided journaling questions.\n\nThis can help clear your mind before sleep."
    @Published var isLoading: Bool = false
    
    @MainActor
    func generateQuestions() async {
        guard !userProblem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            generatedQuestions = "Please enter a problem or topic to get started."
            return
        }
        
        isLoading = true
        guard let apiKey = Secrets.groqApiKey else {
            generatedQuestions = "Error: GROQ_API_KEY not found."
            isLoading = false
            return
        }
        
        guard let url = URL(string: "https://api.groq.com/openai/v1/chat/completions") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody = GroqRequest(
            messages: [
                GroqMessage(role: "system", content: "You are a journaling guide. The user is stuck on a problem. Your task is to provide a sequence of exactly three powerful, open-ended questions to help them clarify their thoughts and identify a potential next step. Do not answer the question for them. Just provide the three questions."),
                GroqMessage(role: "user", content: userProblem)
            ],
            model: "llama3-8b-8192"
        )
        
        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
            let (data, _) = try await URLSession.shared.data(for: request)
            let decodedResponse = try JSONDecoder().decode(GroqResponse.self, from: data)
            if let responseContent = decodedResponse.choices.first?.message.content {
                generatedQuestions = responseContent.trimmingCharacters(in: .whitespacesAndNewlines)
            } else { generatedQuestions = "The AI returned an empty response. Please try again." }
        } catch {
            generatedQuestions = "Error fetching questions: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
}

struct JournalingGuideView: View {
    @StateObject private var viewModel = JournalingViewModel()
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Input Section
                    VStack(alignment: .leading) {
                        Text("Describe your challenge")
                            .font(.headline)
                        TextEditor(text: $viewModel.userProblem)
                            .frame(height: 100)
                            .padding(4)
                            .background(Color(.secondarySystemGroupedBackground))
                            .cornerRadius(8)
                            .shadow(color: .black.opacity(0.1), radius: 1)
                    }
                    
                    // Action Button
                    Button(action: {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) // Dismiss keyboard
                        Task { await viewModel.generateQuestions() }
                    }) {
                        Label(viewModel.isLoading ? "Generating..." : "Get my Questions", systemImage: "sparkles")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.purple)
                            .cornerRadius(12)
                    }
                    .disabled(viewModel.isLoading)
                    
                    // AI Response Section
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Your Guided Questions")
                            .font(.headline)
                        if viewModel.isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else {
                            Text(viewModel.generatedQuestions)
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.1), radius: 5, y: 2)
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Journaling Guide")
            .background(Color(.systemGroupedBackground).edgesIgnoringSafeArea(.all))
        }
    }
}


// MARK: - Section 3 & 4: Placeholder Views

struct NutritionView: View {
    var body: some View {
        NavigationView {
            VStack {
                Image(systemName: "fork.knife.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.green)
                Text("Nutrition Hub")
                    .font(.largeTitle)
                    .padding()
                Text("Track meals, find recipes, and analyze your diet here in the future.")
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .foregroundColor(.secondary)
            }
            .navigationTitle("Nutrition")
        }
    }
}

struct FitnessView: View {
    var body: some View {
        NavigationView {
            VStack {
                Image(systemName: "figure.run.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.red)
                Text("Fitness Center")
                    .font(.largeTitle)
                    .padding()
                Text("Log workouts, follow plans, and monitor your progress here in the future.")
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .foregroundColor(.secondary)
            }
            .navigationTitle("Fitness")
        }
    }
}

// MARK: - Reusable UI Components (Unchanged)

#if true // Use a conditional to easily paste the unchanged views
struct BriefingCardView: View {
    let score: Int
    let briefing: String
    let isLoading: Bool
    
    var scoreColor: Color {
        switch score {
        case 80...100: return .green
        case 50..<80: return .orange
        default: return .red
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Today's Briefing")
                .font(.title2)
                .fontWeight(.bold)
            
            HStack(spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(scoreColor.opacity(0.3), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: CGFloat(score) / 100.0)
                        .stroke(scoreColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    
                    Text("\(score)")
                        .font(.title)
                        .fontWeight(.bold)
                }
                .frame(width: 80, height: 80)
                
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(briefing)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 5, y: 2)
    }
}


struct LoggingModuleView<Content: View>: View {
    let title: String
    let systemImageName: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Image(systemName: systemImageName)
                    .foregroundColor(.accentColor)
                Text(title)
                    .font(.headline)
            }
            .padding(.bottom, 5)
            
            content
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
    }
}
#endif

// MARK: - Preview
struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
    }
}
