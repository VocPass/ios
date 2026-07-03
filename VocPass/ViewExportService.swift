//
//  ViewExportService.swift
//  YKVS
//
//  Created by Hans on 2026/7/3.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - IG Story Dimensions

enum IGStoryExport {
    /// Render size for Instagram Story (9:16 aspect ratio)
    static let size = CGSize(width: 1080, height: 1920)
    static let contentPadding: CGFloat = 48
}

// MARK: - IG Story Footer

struct IGStoryFooter: View {
    @Environment(\.colorScheme) var colorScheme

    private var gradientColors: [Color] {
        [
            Color(red: 0.176, green: 0.431, blue: 0.682),
            Color(red: 0.071, green: 0.086, blue: 0.224)
        ]
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left side: VocPass branding
            HStack(spacing: 20) {
                // App icon representation
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(LinearGradient(
                                colors: gradientColors,
                                startPoint: .top,
                                endPoint: .bottom
                            ))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("VocPass")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("你的隨身校園幫手")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, IGStoryExport.contentPadding)
        .padding(.vertical, 36)
        .background(Color(.systemBackground))
    }
}

// MARK: - IG Story Export Container

struct IGStoryContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main content area — fills available space
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

            // Footer divider + brand
            Divider()
            IGStoryFooter()
        }
        .frame(width: IGStoryExport.size.width, height: IGStoryExport.size.height)
        .background(Color(.systemBackground))
    }
}

// MARK: - Cross-platform Image type

#if canImport(UIKit)
typealias ExportImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias ExportImage = NSImage
#endif

// MARK: - View Rendering Extension

extension View {
    /// Renders this SwiftUI view to an image at the specified size.
    @MainActor
    func renderToImage(size: CGSize, scale: CGFloat = 1.0) -> ExportImage? {
        let renderer = ImageRenderer(
            content: self
                .frame(width: size.width, height: size.height)
                .environment(\.colorScheme, .light) // IG stories are always light mode
        )
        renderer.scale = scale
        #if canImport(UIKit)
        return renderer.uiImage
        #elseif canImport(AppKit)
        return renderer.nsImage
        #endif
    }
}

// MARK: - Share Sheet using UIActivityViewController

#if canImport(UIKit)
struct ShareSheet: UIViewControllerRepresentable {
    let image: UIImage

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: [image],
            applicationActivities: nil
        )
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
