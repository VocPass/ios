//
//  CaptchaIndicatorView.swift
//  BSH
//
//  Created by Hans on 2026/3/4.
//

import SwiftUI

struct CaptchaIndicatorView: View {
    let isRecognizing: Bool
    let lastRecognizedText: String?
    
    var body: some View {
        VStack(spacing: 8) {
            if isRecognizing {
                HStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(0.8)
                    
                    Text("正在識別驗證碼...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(.systemBackground))
                .cornerRadius(20)
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            } else if let recognizedText = lastRecognizedText {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                    
                    Text("已識別: \(recognizedText)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(.systemBackground))
                .cornerRadius(20)
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isRecognizing)
        .animation(.easeInOut(duration: 0.3), value: lastRecognizedText)
    }
}

#Preview {
    VStack(spacing: 20) {
        CaptchaIndicatorView(isRecognizing: true, lastRecognizedText: nil)
        
        CaptchaIndicatorView(isRecognizing: false, lastRecognizedText: "A7B9C")
        
        CaptchaIndicatorView(isRecognizing: false, lastRecognizedText: nil)
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}