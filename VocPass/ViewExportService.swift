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

// MARK: - Brand

enum BrandColors {
    static let blue = Color(red: 0.176, green: 0.431, blue: 0.682) // #2D6EAE
    static let navy = Color(red: 0.071, green: 0.086, blue: 0.224)  // #121639
}

// MARK: - IG Story Dimensions

enum IGStoryExport {
    static let size = CGSize(width: 1080, height: 1920)
    static let padding: CGFloat = 56
    static let cardRadius: CGFloat = 16
}

// MARK: - Footer

struct IGStoryFooter: View {
    let iconImage: UIImage?

    @ViewBuilder
    private var iconView: some View {
        if let img = iconImage {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(BrandColors.blue)
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 48, height: 48)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 14) {
                iconView

                VStack(alignment: .leading, spacing: 0) {
                    Text("VocPass")
                        .font(.system(size: 24, weight: .bold, design: .default))
                        .foregroundStyle(.primary)
                    Text("你的隨身校園幫手")
                        .font(.system(size: 14, weight: .regular, design: .default))
                        .foregroundStyle(Color(.systemGray))
                }
            }
            Spacer()
        }
        .padding(.horizontal, IGStoryExport.padding)
        .padding(.vertical, 28)
        .background(
            Color(.systemBackground)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(height: 0.5)
                }
        )
    }
}

// MARK: - Container

struct IGStoryContainer<Content: View>: View {
    let content: Content
    let iconImage: UIImage?

    init(iconImage: UIImage? = nil, @ViewBuilder content: () -> Content) {
        self.iconImage = iconImage
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

            IGStoryFooter(iconImage: iconImage)
        }
        .frame(width: IGStoryExport.size.width, height: IGStoryExport.size.height)
        .background(Color(.systemBackground))
    }
}

// MARK: - Shared Components

struct ExportHeader: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 64, weight: .black, design: .default))
                .foregroundStyle(.primary)
                .tracking(-1)
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.system(size: 26, weight: .regular, design: .default))
                    .foregroundStyle(Color(.systemGray))
            }
        }
        .padding(.horizontal, IGStoryExport.padding)
        .padding(.top, 100)
        .padding(.bottom, 16)
    }
}

struct ExportSectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold, design: .default))
            .foregroundStyle(Color(.systemGray))
            .textCase(.uppercase)
            .tracking(2)
            .padding(.top, 12)
    }
}

struct ExportCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: IGStoryExport.cardRadius, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
    }
}

// MARK: - Cross-platform Image

#if canImport(UIKit)
typealias ExportImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias ExportImage = NSImage
#endif

// MARK: - Icon Preloader

@MainActor
final class ExportIconLoader {
    static let shared = ExportIconLoader()
    private static let iconURL = URL(string: "https://cdn.vocpass.com/icon.png")!

    private(set) var loadedImage: UIImage?

    func preload() async {
        guard loadedImage == nil else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: Self.iconURL)
            loadedImage = UIImage(data: data)
        } catch {}
    }
}

// MARK: - View → Image

extension View {
    @MainActor
    func renderToImage(size: CGSize, scale: CGFloat = 1.0) -> ExportImage? {
        let renderer = ImageRenderer(
            content: self
                .frame(width: size.width, height: size.height)
                .environment(\.colorScheme, .light)
        )
        renderer.scale = scale
        #if canImport(UIKit)
        return renderer.uiImage
        #elseif canImport(AppKit)
        return renderer.nsImage
        #endif
    }
}

// MARK: - Share Sheet

#if canImport(UIKit)
struct ShareSheet: UIViewControllerRepresentable {
    let image: UIImage

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

// MARK: - Helpers

func exportScoreColor(_ score: String) -> Color {
    guard let v = Double(score) else { return .primary }
    let p = Double(CacheService.shared.passingScore)
    switch v {
    case 90...100: return .green
    case 80..<90: return BrandColors.blue
    case p..<80: return .primary
    default: return .red
    }
}

func exportCleanedHTML(_ text: String) -> String {
    text
        .replacingOccurrences(of: "<br/>", with: "\n")
        .replacingOccurrences(of: "<br />", with: "\n")
        .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        .replacingOccurrences(of: "&nbsp;", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
