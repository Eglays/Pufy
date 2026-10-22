import SwiftUI

struct HistoryView: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var showDeleteConfirmation = false
    
    // Date formatter for display
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.currentLocale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Color(red: 0.05, green: 0.05, blue: 0.06)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    
                    // Top Actions Panel
                    HStack {
                        Button(action: {
                            viewModel.startNewSession()
                        }) {
                            HStack {
                                Image(systemName: "plus.bubble.fill")
                                Text("Yeni Sohbet Başlat")
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                LinearGradient(
                                    colors: [Color(white: 0.22), Color(white: 0.15)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(12)
                            .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
                        }
                        
                        Spacer()
                        
                        // Clear All Button
                        if !viewModel.sessions.isEmpty {
                            Button(action: {
                                showDeleteConfirmation = true
                            }) {
                                HStack {
                                    Image(systemName: "trash")
                                    Text("Temizle")
                                }
                                .font(.subheadline)
                                .foregroundColor(.red.opacity(0.8))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.red.opacity(0.08))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.red.opacity(0.2), lineWidth: 1)
                                )
                            }
                        }
                    }
                    .padding()
                    
                    // Session List
                    if viewModel.sessions.isEmpty {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "message.and.waveform")
                                .font(.system(size: 64))
                                .foregroundColor(.gray.opacity(0.3))
                            Text("Henüz sohbet geçmişi yok.")
                                .font(.headline)
                                .foregroundColor(.gray)
                            Text("Yeni bir sohbet başlatarak yapay zeka ile konuşmaya başlayabilirsiniz.")
                                .font(.caption)
                                .foregroundColor(.gray.opacity(0.8))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                        Spacer()
                    } else {
                        List {
                            ForEach(viewModel.sessions) { session in
                                Button(action: {
                                    viewModel.selectSession(session)
                                }) {
                                    HStack(spacing: 16) {
                                        // Left Indicator
                                        let isCurrent = viewModel.currentSession?.id == session.id
                                        ZStack {
                                            Circle()
                                                .fill(isCurrent ? Color(white: 0.25) : Color.white.opacity(0.05))
                                                .frame(width: 44, height: 44)
                                            
                                            Image(systemName: isCurrent ? "bubble.left.and.bubble.right.fill" : "bubble.left")
                                                .font(.system(size: 18))
                                                .foregroundColor(isCurrent ? .white : .gray)
                                        }
                                        
                                        // Session Details
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(session.title)
                                                .font(.headline)
                                                .foregroundColor(.white)
                                                .lineLimit(1)
                                            
                                            HStack {
                                                Text("\(session.messages.count) mesaj")
                                                    .font(.caption)
                                                    .foregroundColor(.gray)
                                                
                                                Text("•")
                                                    .font(.caption)
                                                    .foregroundColor(.gray.opacity(0.5))
                                                
                                                Text(dateFormatter.string(from: session.createdAt))
                                                    .font(.caption)
                                                    .foregroundColor(.gray.opacity(0.8))
                                            }
                                        }
                                        
                                        Spacer()
                                        
                                        // Active arrow
                                        if isCurrent {
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundColor(.white)
                                        }
                                    }
                                    .padding(.vertical, 8)
                                }
                                .listRowBackground(Color.white.opacity(viewModel.currentSession?.id == session.id ? 0.05 : 0.01))
                                .listRowSeparatorTint(Color.white.opacity(0.05))
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        viewModel.deleteSession(session)
                                    } label: {
                                        Label("Sil", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .listStyle(PlainListStyle())
                        .background(Color.clear)
                    }
                }
            }
            .navigationTitle("Geçmiş Sohbetler")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Geçmiş")
                        .font(.headline)
                        .foregroundColor(.white)
                }
            }
            .alert(isPresented: $showDeleteConfirmation) {
                Alert(
                    title: Text("Geçmişi Temizle"),
                    message: Text("Tüm sohbet geçmişiniz kalıcı olarak silinecektir. Bu işlem geri alınamaz."),
                    primaryButton: .destructive(Text("Her Şeyi Sil")) {
                        viewModel.clearAllSessions()
                    },
                    secondaryButton: .cancel(Text("Vazgeç"))
                )
            }
        }
    }
}
