//
//  W2MSyncScrollView.swift
//  VocPass
//
//  兩欄同步垂直捲動：左欄固定（時間軸），右欄可水平+垂直捲動
//

import SwiftUI
import UIKit

/// 把兩個 UIScrollView 的垂直 offset 同步
class W2MScrollSyncCoordinator: NSObject, UIScrollViewDelegate {
    weak var left: UIScrollView?
    weak var right: UIScrollView?
    private var isSyncing = false

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !isSyncing else { return }
        isSyncing = true
        if scrollView === right {
            left?.contentOffset.y = scrollView.contentOffset.y
        } else {
            right?.contentOffset.y = scrollView.contentOffset.y
        }
        isSyncing = false
    }
}

/// 左欄固定寬度、只垂直捲動；右欄垂直+水平捲動，兩欄垂直同步
struct W2MSyncScrollView<LeftContent: View, RightContent: View>: UIViewControllerRepresentable {
    let leftWidth: CGFloat
    let contentHeight: CGFloat
    let enableHScroll: Bool
    @Binding var scrollDisabled: Bool
    let leftContent: () -> LeftContent
    let rightContent: () -> RightContent

    func makeCoordinator() -> W2MScrollSyncCoordinator { W2MScrollSyncCoordinator() }

    func makeUIViewController(context: Context) -> W2MSyncVC<LeftContent, RightContent> {
        let vc = W2MSyncVC(
            leftWidth: leftWidth,
            contentHeight: contentHeight,
            enableHScroll: enableHScroll,
            leftContent: leftContent,
            rightContent: rightContent,
            coordinator: context.coordinator
        )
        return vc
    }

    func updateUIViewController(_ vc: W2MSyncVC<LeftContent, RightContent>, context: Context) {
        vc.rightScrollView.isScrollEnabled = !scrollDisabled
        vc.leftScrollView.isScrollEnabled = !scrollDisabled
    }
}

class W2MSyncVC<LeftContent: View, RightContent: View>: UIViewController {
    let leftWidth: CGFloat
    let contentHeight: CGFloat
    let enableHScroll: Bool
    let leftContentBuilder: () -> LeftContent
    let rightContentBuilder: () -> RightContent
    let coordinator: W2MScrollSyncCoordinator

    let leftScrollView = UIScrollView()
    let rightScrollView = UIScrollView()

    init(leftWidth: CGFloat, contentHeight: CGFloat, enableHScroll: Bool,
         leftContent: @escaping () -> LeftContent,
         rightContent: @escaping () -> RightContent,
         coordinator: W2MScrollSyncCoordinator) {
        self.leftWidth = leftWidth
        self.contentHeight = contentHeight
        self.enableHScroll = enableHScroll
        self.leftContentBuilder = leftContent
        self.rightContentBuilder = rightContent
        self.coordinator = coordinator
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {}

    override func viewDidLoad() {
        super.viewDidLoad()

        // 左側 ScrollView（只垂直）
        leftScrollView.showsVerticalScrollIndicator = false
        leftScrollView.showsHorizontalScrollIndicator = false
        leftScrollView.alwaysBounceVertical = true
        leftScrollView.delaysContentTouches = false
        leftScrollView.canCancelContentTouches = false
        leftScrollView.delegate = coordinator

        // 右側 ScrollView（垂直 + 水平）
        rightScrollView.showsVerticalScrollIndicator = true
        rightScrollView.showsHorizontalScrollIndicator = enableHScroll
        rightScrollView.alwaysBounceVertical = true
        rightScrollView.alwaysBounceHorizontal = enableHScroll
        rightScrollView.delaysContentTouches = false
        rightScrollView.canCancelContentTouches = false
        rightScrollView.delegate = coordinator

        coordinator.left = leftScrollView
        coordinator.right = rightScrollView

        // 左側內容
        let leftHost = UIHostingController(rootView: leftContentBuilder())
        leftHost.view.backgroundColor = .clear
        addChild(leftHost)
        leftScrollView.addSubview(leftHost.view)
        leftHost.didMove(toParent: self)
        leftHost.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            leftHost.view.topAnchor.constraint(equalTo: leftScrollView.contentLayoutGuide.topAnchor),
            leftHost.view.leadingAnchor.constraint(equalTo: leftScrollView.contentLayoutGuide.leadingAnchor),
            leftHost.view.widthAnchor.constraint(equalToConstant: leftWidth),
            leftHost.view.heightAnchor.constraint(equalToConstant: contentHeight),
        ])

        // 右側內容
        let rightHost = UIHostingController(rootView: rightContentBuilder())
        rightHost.view.backgroundColor = .clear
        addChild(rightHost)
        rightScrollView.addSubview(rightHost.view)
        rightHost.didMove(toParent: self)
        rightHost.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            rightHost.view.topAnchor.constraint(equalTo: rightScrollView.contentLayoutGuide.topAnchor),
            rightHost.view.leadingAnchor.constraint(equalTo: rightScrollView.contentLayoutGuide.leadingAnchor),
            rightHost.view.bottomAnchor.constraint(equalTo: rightScrollView.contentLayoutGuide.bottomAnchor),
            rightHost.view.trailingAnchor.constraint(equalTo: rightScrollView.contentLayoutGuide.trailingAnchor),
        ])

        view.addSubview(leftScrollView)
        view.addSubview(rightScrollView)
        leftScrollView.translatesAutoresizingMaskIntoConstraints = false
        rightScrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            leftScrollView.topAnchor.constraint(equalTo: view.topAnchor),
            leftScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            leftScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            leftScrollView.widthAnchor.constraint(equalToConstant: leftWidth),

            rightScrollView.topAnchor.constraint(equalTo: view.topAnchor),
            rightScrollView.leadingAnchor.constraint(equalTo: leftScrollView.trailingAnchor),
            rightScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            rightScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}
