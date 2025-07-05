import SwiftUI
internal import Combine

// MARK: - App's Main Entry Point

struct MainTabView: View {
    var body: some View {
        TabView {
            // Tab 1: Dashboard
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "square.grid.2x2.fill")
                }
            
            // Tab 2: Journaling Guide
            JournalingGuideView()
                .tabItem {
                    Label("Journal", systemImage: "book.fill")
                }
            
            // Tab 3: Motivation Starter
            MotivationView()
                .tabItem {
                    Label("Motivation", systemImage: "flame.fill")
                }
            
            // Tab 4: NEW Energizer View
            EnergizerView()
                .tabItem {
                    Label("Fitness", systemImage: "figure.run")
                }
        }
        .accentColor(.blue) // Sets the color for the active tab icon
    }
}


// MARK: - Groq API Models & Secrets (Unchanged)
#if true
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
#endif

// MARK: - Section 1: Dashboard View & ViewModel (Unchanged)
#if true
class DashboardViewModel: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    
    @Published var sleepHours: Double = 7.5; @Published var mealSummary: String = ""; @Published var workoutSummary: String = ""; @Published var healthScore: Int = 0; @Published var morningBriefing: String = "Log your daily data and tap 'Generate Briefing' to get your personalized health insights."; @Published var isLoading: Bool = false; @Published var streakCount: Int = 0
    private let streakCountKey = "streakCount"; private let lastBriefingDateKey = "lastBriefingDateKey"
    init() { loadStreak() }
    @MainActor func generateBriefing() async { isLoading = true; guard let apiKey = Secrets.groqApiKey else { morningBriefing = "Error: GROQ_API_KEY not found."; isLoading = false; return }; calculateHealthScore(); let prompt = createPrompt(); guard let url = URL(string: "https://api.groq.com/openai/v1/chat/completions") else { return }; var request = URLRequest(url: url); request.httpMethod = "POST"; request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Content-Type"); let requestBody = GroqRequest(messages: [GroqMessage(role: "system", content: "You are Apex, a helpful health assistant. Analyze user logs for a 'Morning Briefing'. Be concise, positive, and connect the inputs."), GroqMessage(role: "user", content: prompt)], model: "llama3-8b-8192"); do { request.httpBody = try JSONEncoder().encode(requestBody); let (data, _) = try await URLSession.shared.data(for: request); let decodedResponse = try JSONDecoder().decode(GroqResponse.self, from: data); if let responseContent = decodedResponse.choices.first?.message.content { morningBriefing = responseContent.trimmingCharacters(in: .whitespacesAndNewlines); updateStreak() } else { morningBriefing = "Empty AI response." } } catch { morningBriefing = "Error: \(error.localizedDescription)" }; isLoading = false }
    private func loadStreak() { let storedStreak = UserDefaults.standard.integer(forKey: streakCountKey); guard let lastDate = UserDefaults.standard.object(forKey: lastBriefingDateKey) as? Date else { self.streakCount = 0; return }; if !Calendar.current.isDateInYesterday(lastDate) && !Calendar.current.isDateInToday(lastDate) { self.streakCount = 0; UserDefaults.standard.set(0, forKey: streakCountKey) } else { self.streakCount = storedStreak } }
    private func updateStreak() { let today = Date(); guard let lastDate = UserDefaults.standard.object(forKey: lastBriefingDateKey) as? Date else { streakCount = 1; saveStreak(count: 1, date: today); return }; if Calendar.current.isDate(today, inSameDayAs: lastDate) { return }; if Calendar.current.isDateInYesterday(lastDate) { streakCount += 1 } else { streakCount = 1 }; saveStreak(count: streakCount, date: today) }
    private func saveStreak(count: Int, date: Date) { UserDefaults.standard.set(count, forKey: streakCountKey); UserDefaults.standard.set(date, forKey: lastBriefingDateKey) }
    private func calculateHealthScore() { var score = 0; let sleepScore = min(40, (self.sleepHours / 8.0) * 40); score += Int(sleepScore); if !self.mealSummary.trimmingCharacters(in: .whitespaces).isEmpty { score += 30 }; if !self.workoutSummary.trimmingCharacters(in: .whitespaces).isEmpty { score += 30 }; self.healthScore = min(100, score) }
    private func createPrompt() -> String { let nutritionLog = mealSummary.isEmpty ? "No food logged." : mealSummary; let fitnessLog = workoutSummary.isEmpty ? "No workout logged." : workoutSummary; return "Sleep: \(String(format: "%.1f", sleepHours)) hours\nNutrition: \(nutritionLog)\nFitness: \(fitnessLog)" }
}
struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel(); var body: some View { NavigationView { ScrollView { VStack(alignment: .leading, spacing: 25) { HStack { Spacer(); Image(systemName: "flame.fill"); Text("\(viewModel.streakCount)"); Spacer() }.font(.subheadline).fontWeight(.bold).foregroundColor(.orange).padding(.top, 4); BriefingCardView(score: viewModel.healthScore, briefing: viewModel.morningBriefing, isLoading: viewModel.isLoading); VStack(spacing: 20) { LoggingModuleView(title: "Sleep", systemImageName: "bed.double.fill") { VStack { Text("\(String(format: "%.1f", viewModel.sleepHours)) hours").font(.headline); Slider(value: $viewModel.sleepHours, in: 0...12, step: 0.5) } }; LoggingModuleView(title: "Nutrition", systemImageName: "fork.knife") { TextField("e.g., Oatmeal, Chicken Salad", text: $viewModel.mealSummary, axis: .vertical).textFieldStyle(.roundedBorder) }; LoggingModuleView(title: "Fitness", systemImageName: "figure.run") { TextField("e.g., 3-mile run", text: $viewModel.workoutSummary, axis: .vertical).textFieldStyle(.roundedBorder) } }; Button(action: { Task { await viewModel.generateBriefing() } }) { Text(viewModel.isLoading ? "Analyzing..." : "Generate Briefing").font(.headline).foregroundColor(.white).frame(maxWidth: .infinity).padding().background(Color.blue).cornerRadius(12) }.disabled(viewModel.isLoading) }.padding() }.navigationTitle("Apex Dashboard").background(Color(.systemGroupedBackground).edgesIgnoringSafeArea(.all)) } }
}
#endif

// MARK: - Section 2: Journaling Guide View & ViewModel (Unchanged)
#if true
class JournalingViewModel: ObservableObject {
    @Published var userProblem: String = ""; @Published var generatedQuestions: String = "Describe a problem or challenge you're facing to receive guided journaling questions.\n\nThis can help clear your mind before sleep."; @Published var isLoading: Bool = false
    @MainActor func generateQuestions() async { guard !userProblem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { generatedQuestions = "Please enter a problem or topic to get started."; return }; isLoading = true; guard let apiKey = Secrets.groqApiKey else { generatedQuestions = "Error: GROQ_API_KEY not found."; isLoading = false; return }; guard let url = URL(string: "https://api.groq.com/openai/v1/chat/completions") else { return }; var request = URLRequest(url: url); request.httpMethod = "POST"; request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Content-Type"); let requestBody = GroqRequest(messages: [GroqMessage(role: "system", content: "You are a journaling guide. The user is stuck. Provide three powerful, open-ended questions to help them clarify their thoughts. Just provide the three questions."), GroqMessage(role: "user", content: userProblem)], model: "llama3-8b-8192"); do { request.httpBody = try JSONEncoder().encode(requestBody); let (data, _) = try await URLSession.shared.data(for: request); let decodedResponse = try JSONDecoder().decode(GroqResponse.self, from: data); if let responseContent = decodedResponse.choices.first?.message.content { generatedQuestions = responseContent.trimmingCharacters(in: .whitespacesAndNewlines) } else { generatedQuestions = "The AI returned an empty response." } } catch { generatedQuestions = "Error fetching questions: \(error.localizedDescription)" }; isLoading = false }
}
struct JournalingGuideView: View {
    @StateObject private var viewModel = JournalingViewModel(); var body: some View { NavigationView { ScrollView { VStack(spacing: 24) { VStack(alignment: .leading) { Text("Describe your challenge").font(.headline); TextEditor(text: $viewModel.userProblem).frame(height: 100).padding(4).background(Color(.secondarySystemGroupedBackground)).cornerRadius(8).shadow(color: .black.opacity(0.1), radius: 1) }; Button(action: { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil); Task { await viewModel.generateQuestions() } }) { Label(viewModel.isLoading ? "Generating..." : "Get my Questions", systemImage: "sparkles").font(.headline).foregroundColor(.white).frame(maxWidth: .infinity).padding().background(Color.purple).cornerRadius(12) }.disabled(viewModel.isLoading); VStack(alignment: .leading, spacing: 15) { Text("Your Guided Questions").font(.headline); if viewModel.isLoading { ProgressView().frame(maxWidth: .infinity).padding() } else { Text(viewModel.generatedQuestions).font(.body).frame(maxWidth: .infinity, alignment: .leading) } }.padding().background(Color(.secondarySystemGroupedBackground)).cornerRadius(16).shadow(color: .black.opacity(0.1), radius: 5, y: 2); Spacer() }.padding() }.navigationTitle("Journaling Guide").background(Color(.systemGroupedBackground).edgesIgnoringSafeArea(.all)) } }
}
#endif

// MARK: - Section 3: Motivation Starter View & ViewModel (Unchanged)
#if true
class MotivationViewModel: ObservableObject {
    @Published var taskDescription: String = ""; @Published var motivationPitch: String = "Feeling stuck? Tell me what you need to do, and I'll give you a push to get started for just 5 minutes."; @Published var isLoading: Bool = false
    @MainActor func generateMotivation() async { guard !taskDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { motivationPitch = "Please tell me what task you're avoiding first!"; return }; isLoading = true; guard let apiKey = Secrets.groqApiKey else { motivationPitch = "Error: GROQ_API_KEY not found."; isLoading = false; return }; guard let url = URL(string: "https://api.groq.com/openai/v1/chat/completions") else { return }; var request = URLRequest(url: url); request.httpMethod = "POST"; request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Content-Type"); let systemPrompt = "You are a personal hype-man. Your goal is to convince the user to work on a task for just five minutes. Frame it in a way that makes it sound appealing and extremely low-effort. Be encouraging, positive, and focus on how easy and quick the first step is. Keep it short and punchy."; let userPrompt = "The task I'm procrastinating on is: \(taskDescription)"; let requestBody = GroqRequest(messages: [GroqMessage(role: "system", content: systemPrompt), GroqMessage(role: "user", content: userPrompt)], model: "llama3-8b-8192"); do { request.httpBody = try JSONEncoder().encode(requestBody); let (data, _) = try await URLSession.shared.data(for: request); let decodedResponse = try JSONDecoder().decode(GroqResponse.self, from: data); if let responseContent = decodedResponse.choices.first?.message.content { motivationPitch = responseContent.trimmingCharacters(in: .whitespacesAndNewlines) } else { motivationPitch = "The AI seems to be speechless. Try again!" } } catch { motivationPitch = "Error getting motivation: \(error.localizedDescription)" }; isLoading = false }
}
struct MotivationView: View {
    @StateObject private var viewModel = MotivationViewModel(); var body: some View { NavigationView { ScrollView { VStack(spacing: 24) { VStack(alignment: .leading) { Text("What are you procrastinating on?").font(.headline); TextField("e.g., 'cleaning the kitchen'", text: $viewModel.taskDescription).textFieldStyle(.roundedBorder).padding(.top, 2) }; Button(action: { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil); Task { await viewModel.generateMotivation() } }) { Label(viewModel.isLoading ? "Hyping you up..." : "Give me a 5-Min Push", systemImage: "bolt.fill").font(.headline).foregroundColor(.white).frame(maxWidth: .infinity).padding().background(Color.orange).cornerRadius(12) }.disabled(viewModel.isLoading); VStack(alignment: .leading, spacing: 15) { Text("Your 5-Minute Kickstart").font(.headline); if viewModel.isLoading { ProgressView().frame(maxWidth: .infinity).padding() } else { Text(viewModel.motivationPitch).font(.body).frame(maxWidth: .infinity, alignment: .leading) } }.padding().background(Color(.secondarySystemGroupedBackground)).cornerRadius(16).shadow(color: .black.opacity(0.1), radius: 5, y: 2); Spacer() }.padding() }.navigationTitle("5-Minute Motivation").background(Color(.systemGroupedBackground).edgesIgnoringSafeArea(.all)) } }
}
#endif

// MARK: - Section 4: NEW Energizer View & ViewModel

class EnergizerViewModel: ObservableObject {
    @Published var energizingMoves: String = "Feeling sluggish from sitting too long? Tap the button for three simple movements you can do right at your desk."
    @Published var isLoading: Bool = false

    @MainActor
    func generateEnergizer() async {
        isLoading = true
        guard let apiKey = Secrets.groqApiKey else {
            energizingMoves = "Error: GROQ_API_KEY not found."
            isLoading = false
            return
        }

        guard let url = URL(string: "https://api.groq.com/openai/v1/chat/completions") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let systemPrompt = "You are a friendly and encouraging fitness coach. Your user has been sitting at their desk for hours and feels sluggish. They only have 5 minutes. Your task is to suggest exactly three simple, energizing stretches or movements they can do right in their chair or next to their desk to wake up their body. For each movement, give it a simple name and a one-sentence description. Use a numbered list for clarity."
        let userPrompt = "I've been sitting at my desk for hours and feel sluggish. I only have 5 minutes. Suggest three simple, energizing stretches or movements I can do right here."

        let requestBody = GroqRequest(
            messages: [
                GroqMessage(role: "system", content: systemPrompt),
                GroqMessage(role: "user", content: userPrompt)
            ],
            model: "llama3-8b-8192"
        )

        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
            let (data, _) = try await URLSession.shared.data(for: request)
            let decodedResponse = try JSONDecoder().decode(GroqResponse.self, from: data)
            if let responseContent = decodedResponse.choices.first?.message.content {
                energizingMoves = responseContent.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                energizingMoves = "The AI couldn't think of any moves right now. Maybe take a quick walk!"
            }
        } catch {
            energizingMoves = "Error getting exercises: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
}

struct EnergizerView: View {
    @StateObject private var viewModel = EnergizerViewModel()

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    
                    // Action Button
                    Button(action: {
                        Task { await viewModel.generateEnergizer() }
                    }) {
                        Label(viewModel.isLoading ? "Waking you up..." : "Get 5-Min Energizer", systemImage: "figure.walk.motion")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red)
                            .cornerRadius(12)
                    }
                    .disabled(viewModel.isLoading)
                    
                    // AI Response Section
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Your Desk-Bound Energizer")
                            .font(.headline)
                        if viewModel.isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding()
                        } else {
                            Text(viewModel.energizingMoves)
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
            .navigationTitle("Desk Energizer")
            .background(Color(.systemGroupedBackground).edgesIgnoringSafeArea(.all))
        }
    }
}


// MARK: - Reusable UI Components (Unchanged)
#if true
struct BriefingCardView: View {
    let score: Int; let briefing: String; let isLoading: Bool
    var scoreColor: Color { switch score { case 80...100: return .green; case 50..<80: return .orange; default: return .red } }
    var body: some View { VStack(alignment: .leading, spacing: 15) { Text("Today's Briefing").font(.title2).fontWeight(.bold); HStack(spacing: 20) { ZStack { Circle().stroke(scoreColor.opacity(0.3), lineWidth: 8); Circle().trim(from: 0, to: CGFloat(score) / 100.0).stroke(scoreColor, style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(-90)); Text("\(score)").font(.title).fontWeight(.bold) }.frame(width: 80, height: 80); if isLoading { ProgressView().frame(maxWidth: .infinity, alignment: .leading) } else { Text(briefing).font(.body).frame(maxWidth: .infinity, alignment: .leading) } } }.padding().background(Color(.secondarySystemGroupedBackground)).cornerRadius(16).shadow(color: .black.opacity(0.1), radius: 5, y: 2) }
}
struct LoggingModuleView<Content: View>: View {
    let title: String; let systemImageName: String; @ViewBuilder let content: Content
    var body: some View { VStack(alignment: .leading) { HStack { Image(systemName: systemImageName).foregroundColor(.accentColor); Text(title).font(.headline) }.padding(.bottom, 5); content }.padding().background(Color(.secondarySystemGroupedBackground)).cornerRadius(16).shadow(color: .black.opacity(0.05), radius: 3, y: 1) }
}
#endif

// MARK: - Preview
struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
    }
}

