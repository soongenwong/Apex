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


// MARK: - ViewModel with Real AI Logic
class DashboardViewModel: ObservableObject {
    @Published var sleepHours: Double = 7.5
    @Published var mealSummary: String = ""
    @Published var workoutSummary: String = ""
    
    @Published var healthScore: Int = 0
    @Published var morningBriefing: String = "Log your daily data and tap 'Generate Briefing' to get your personalized health insights."
    @Published var isLoading: Bool = false
    
    // This is the core AI function, now making a real network call.
    // It's marked as `async` to perform network operations.
    @MainActor // Ensures UI updates happen on the main thread
    func generateBriefing() async {
        // 1. Start loading state and guard for API Key
        isLoading = true
        guard let apiKey = Secrets.groqApiKey else {
            morningBriefing = "Error: Groq API Key not found in Secrets.plist. Please check your setup."
            isLoading = false
            return
        }
        
        // 2. Calculate the Health Score (can be done before the API call)
        calculateHealthScore()
        
        // 3. Construct the prompt for the AI
        let prompt = createPrompt()
        
        // 4. Set up the network request
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
        
        // 5. Perform the API call and handle the response
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let decodedResponse = try JSONDecoder().decode(GroqResponse.self, from: data)
            
            if let responseContent = decodedResponse.choices.first?.message.content {
                morningBriefing = responseContent.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                morningBriefing = "Received an empty response from the AI. Please try again."
            }
            
        } catch {
            morningBriefing = "Error fetching AI briefing: \(error.localizedDescription)"
        }
        
        // 6. End loading state
        isLoading = false
    }
    
    // Helper to calculate the score. This logic is unchanged.
    private func calculateHealthScore() {
        var score = 0
        let sleepScore = min(40, (self.sleepHours / 8.0) * 40)
        score += Int(sleepScore)
        if !self.mealSummary.trimmingCharacters(in: .whitespaces).isEmpty { score += 30 }
        if !self.workoutSummary.trimmingCharacters(in: .whitespaces).isEmpty { score += 30 }
        self.healthScore = min(100, score)
    }
    
    // Helper to build a clear prompt from user inputs.
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
// The only change here is in the Button's action.

struct ApexView: View {
    @StateObject private var viewModel = DashboardViewModel()
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    
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
                    
                    // --- ACTION BUTTON (CHANGED) ---
                    // The action now runs inside a `Task` to handle the `async` function.
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
