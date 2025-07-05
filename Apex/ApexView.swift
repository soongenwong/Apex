import SwiftUI
internal import Combine
// No need to import Combine anymore, we'll use modern async/await

// MARK: - Groq API Data Models
// These structs match the JSON structure for the Groq API request and response.

struct GroqRequest: Codable {
    let messages: [GroqMessage]
    let model: String
    let temperature: Double = 0.7 // Controls randomness: 0.0 is deterministic, 1.0 is creative
    let max_tokens: Int = 200     // Limit the length of the response
}

struct GroqMessage: Codable {
    let role: String // "user" or "system"
    let content: String
}

struct GroqResponse: Codable {
    let choices: [GroqChoice]
}

struct GroqChoice: Codable {
    let message: ResponseMessage
}

struct ResponseMessage: Codable {
    let content: String
}

// MARK: - API Key Loader
// A helper to safely load the key from Secrets.plist

struct Secrets {
    static var groqApiKey: String? {
        guard let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path) as? [String: AnyObject] else {
            print("Error: Secrets.plist not found or could not be read.")
            return nil
        }
        return dict["GROQ_API_KEY"] as? String
    }
}


// MARK: - ViewModel with Real AI Logic & Streak Tracking
class DashboardViewModel: ObservableObject {
    // --- (Existing @Published properties are unchanged) ---
    @Published var sleepHours: Double = 7.5
    @Published var mealSummary: String = ""
    @Published var workoutSummary: String = ""
    @Published var healthScore: Int = 0
    @Published var morningBriefing: String = "Log your daily data and tap 'Generate Briefing' to get your personalized health insights."
    @Published var isLoading: Bool = false
    
    // --- NEW: Published property for the UI to display the streak ---
    @Published var streakCount: Int = 0
    
    // --- NEW: UserDefaults keys for persistence ---
    private let streakCountKey = "streakCount"
    private let lastBriefingDateKey = "lastBriefingDateKey"
    
    // --- NEW: Load the streak when the ViewModel is created ---
    init() {
        loadStreak()
    }
    
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
        
        guard let url = URL(string: "https://api.groq.com/openai/v1/chat/completions") else {
            morningBriefing = "Error: Invalid API URL."
            isLoading = false
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody = GroqRequest(
            messages: [
                GroqMessage(role: "system", content: "You are Apex, a helpful and encouraging health assistant. Your job is to analyze the user's sleep, nutrition, and fitness logs to create a holistic, connected 'Morning Briefing'. Be concise, positive, and insightful. Connect the different inputs together. For example, 'Your solid sleep likely gave you the energy for that strong workout.'"),
                GroqMessage(role: "user", content: prompt)
            ],
            model: "llama3-8b-8192"
        )
        
        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
        } catch {
            morningBriefing = "Error: Failed to encode request: \(error.localizedDescription)"
            isLoading = false
            return
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let decodedResponse = try JSONDecoder().decode(GroqResponse.self, from: data)
            
            if let responseContent = decodedResponse.choices.first?.message.content {
                morningBriefing = responseContent.trimmingCharacters(in: .whitespacesAndNewlines)
                // --- NEW: Update the streak only on a successful API call ---
                updateStreak()
            } else {
                morningBriefing = "Received an empty response from the AI. Please try again."
            }
            
        } catch {
            morningBriefing = "Error fetching AI briefing: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    // --- NEW: Logic to load the streak from UserDefaults ---
    private func loadStreak() {
        let storedStreak = UserDefaults.standard.integer(forKey: streakCountKey)
        guard let lastDate = UserDefaults.standard.object(forKey: lastBriefingDateKey) as? Date else {
            // If there's no date, there's no streak.
            self.streakCount = 0
            return
        }
        
        // Check if the last briefing was yesterday or today. If it was older, the streak is broken.
        if !Calendar.current.isDateInYesterday(lastDate) && !Calendar.current.isDateInToday(lastDate) {
            self.streakCount = 0
            UserDefaults.standard.set(0, forKey: streakCountKey) // Also reset in storage
        } else {
            self.streakCount = storedStreak
        }
    }
    
    // --- NEW: Logic to check and update the streak ---
    private func updateStreak() {
        let today = Date()
        let calendar = Calendar.current
        
        guard let lastDate = UserDefaults.standard.object(forKey: lastBriefingDateKey) as? Date else {
            // This is the very first briefing. Start the streak at 1.
            self.streakCount = 1
            saveStreak(count: 1, date: today)
            return
        }
        
        // If a briefing was already generated today, do nothing.
        if calendar.isDate(today, inSameDayAs: lastDate) {
            return
        }
        
        // If the last briefing was yesterday, increment the streak.
        if calendar.isDateInYesterday(lastDate) {
            streakCount += 1
        } else {
            // If more than a day has passed, reset the streak to 1.
            streakCount = 1
        }
        
        saveStreak(count: streakCount, date: today)
    }
    
    // --- NEW: Helper function to save to UserDefaults ---
    private func saveStreak(count: Int, date: Date) {
        UserDefaults.standard.set(count, forKey: streakCountKey)
        UserDefaults.standard.set(date, forKey: lastBriefingDateKey)
    }
    
    // --- (Existing helper functions are unchanged) ---
    private func calculateHealthScore() {
        var score = 0
        let sleepScore = min(40, (self.sleepHours / 8.0) * 40)
        score += Int(sleepScore)
        if !self.mealSummary.trimmingCharacters(in: .whitespaces).isEmpty { score += 30 }
        if !self.workoutSummary.trimmingCharacters(in: .whitespaces).isEmpty { score += 30 }
        self.healthScore = min(100, score)
    }
    
    private func createPrompt() -> String {
        let nutritionLog = mealSummary.isEmpty ? "No food logged." : mealSummary
        let fitnessLog = workoutSummary.isEmpty ? "No workout logged." : workoutSummary
        
        return """
        Here is my data for today:
        - Sleep: \(String(format: "%.1f", sleepHours)) hours
        - Nutrition: \(nutritionLog)
        - Fitness: \(fitnessLog)

        Please generate my morning briefing based on this.
        """
    }
}


// MARK: - Main View (ApexView)

struct ApexView: View {
    @StateObject private var viewModel = DashboardViewModel()
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    
                    // --- NEW: Streak Count Display ---
                    // Placed right below the navigation title area.
                    HStack {
                        Spacer()
                        Image(systemName: "flame.fill")
                        Text("\(viewModel.streakCount)")
                        Spacer()
                    }
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.orange)
                    .padding(4)
                    
                    // --- (The rest of the view is unchanged) ---
                    
                    BriefingCardView(
                        score: viewModel.healthScore,
                        briefing: viewModel.morningBriefing,
                        isLoading: viewModel.isLoading
                    )
                    
                    VStack(spacing: 20) {
                        LoggingModuleView(title: "Sleep", systemImageName: "bed.double.fill") {
                            VStack {
                                Text("\(String(format: "%.1f", viewModel.sleepHours)) hours")
                                    .font(.headline)
                                Slider(value: $viewModel.sleepHours, in: 0...12, step: 0.5)
                            }
                        }
                        
                        LoggingModuleView(title: "Nutrition", systemImageName: "fork.knife") {
                            TextField("e.g., Oatmeal, Chicken Salad, Salmon", text: $viewModel.mealSummary, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        LoggingModuleView(title: "Fitness", systemImageName: "figure.run") {
                            TextField("e.g., 3-mile run, 45 min weightlifting", text: $viewModel.workoutSummary, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    
                    Button(action: {
                        Task {
                            await viewModel.generateBriefing()
                        }
                    }) {
                        Text(viewModel.isLoading ? "Analyzing..." : "Generate Briefing")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                    .disabled(viewModel.isLoading)
                    
                }
                .padding()
            }
            .navigationTitle("Apex Dashboard")
            .background(Color(.systemGroupedBackground).edgesIgnoringSafeArea(.all))
        }
    }
}


// MARK: - Reusable UI Components (Unchanged)

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


// MARK: - Preview

struct ApexView_Previews: PreviewProvider {
    static var previews: some View {
        ApexView()
    }
}
