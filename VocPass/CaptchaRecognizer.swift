//
//  CaptchaRecognizer.swift
//  BSH
//
//  Created by Hans on 2026/3/4.
//

import Foundation
import UIKit
import Vision
import WebKit

class CaptchaRecognizer {
    static let shared = CaptchaRecognizer()
    
    private init() {}
    
    /// 從WebView中截取驗證碼圖片並進行OCR識別
    /// - Parameters:
    ///   - webView: WebView實例
    ///   - captchaSelector: 驗證碼圖片的CSS選擇器
    ///   - completion: 完成回調，返回識別結果
    func recognizeCaptchaFromWebView(
        _ webView: WKWebView,
        captchaSelector: String,
        completion: @escaping (String?) -> Void
    ) {
        getCaptchaImageRect(webView: webView, selector: captchaSelector) { [weak self] rect in
            guard let rect = rect else {
                print("❌ [CaptchaRecognizer] 無法獲取驗證碼圖片位置")
                completion(nil)
                return
            }
            
            webView.takeSnapshot(with: nil) { image, error in
                guard let image = image, error == nil else {
                    print("❌ [CaptchaRecognizer] 截圖失敗: \(error?.localizedDescription ?? "未知錯誤")")
                    completion(nil)
                    return
                }
                
                guard let captchaImage = self?.cropImage(image: image, rect: rect) else {
                    print("❌ [CaptchaRecognizer] 裁剪驗證碼圖片失敗")
                    completion(nil)
                    return
                }
                
                self?.recognizeText(from: captchaImage) { result in
                    print("🔍 [CaptchaRecognizer] OCR識別結果: \(result ?? "無結果")")
                    completion(result)
                }
            }
        }
    }
    
    private func getCaptchaImageRect(
        webView: WKWebView,
        selector: String,
        completion: @escaping (CGRect?) -> Void
    ) {
        let script = """
        (function() {
            try {
                var element = null;
                
                element = document.querySelector('.\(selector)');
                if (!element) {
                    element = document.querySelector('#\(selector)');
                }
                if (!element) {
                    element = document.querySelector('[name="\(selector)"]');
                }
                if (!element) {
                    element = document.querySelector('img[alt*="\(selector)"]');
                }
                if (!element) {
                    var images = document.querySelectorAll('img');
                    for (var i = 0; i < images.length; i++) {
                        var img = images[i];
                        var src = img.src.toLowerCase();
                        var alt = (img.alt || '').toLowerCase();
                        var className = (img.className || '').toLowerCase();
                        
                        if (src.includes('captcha') || src.includes('code') || src.includes('verify') ||
                            alt.includes('captcha') || alt.includes('code') || alt.includes('verify') ||
                            className.includes('captcha') || className.includes('code') || className.includes('verify')) {
                            element = img;
                            break;
                        }
                    }
                }
                
                if (!element) {
                    return { error: '找不到驗證碼圖片元素' };
                }
                
                var rect = element.getBoundingClientRect();
                return {
                    x: rect.left,
                    y: rect.top,
                    width: rect.width,
                    height: rect.height,
                    scrollX: window.scrollX,
                    scrollY: window.scrollY
                };
            } catch (e) {
                return { error: e.toString() };
            }
        })();
        """
        
        webView.evaluateJavaScript(script) { result, error in
            if let error = error {
                print("❌ [CaptchaRecognizer] JavaScript 執行失敗: \(error)")
                completion(nil)
                return
            }
            
            guard let resultDict = result as? [String: Any] else {
                print("❌ [CaptchaRecognizer] JavaScript 返回格式錯誤")
                completion(nil)
                return
            }
            
            if let errorMsg = resultDict["error"] as? String {
                print("❌ [CaptchaRecognizer] JavaScript 錯誤: \(errorMsg)")
                completion(nil)
                return
            }
            
            guard let x = resultDict["x"] as? CGFloat,
                  let y = resultDict["y"] as? CGFloat,
                  let width = resultDict["width"] as? CGFloat,
                  let height = resultDict["height"] as? CGFloat,
                  let scrollX = resultDict["scrollX"] as? CGFloat,
                  let scrollY = resultDict["scrollY"] as? CGFloat else {
                print("❌ [CaptchaRecognizer] 無法解析圖片位置資訊")
                completion(nil)
                return
            }
            
            let actualX = x + scrollX
            let actualY = y + scrollY
            let rect = CGRect(x: actualX, y: actualY, width: width, height: height)
            
            print("📐 [CaptchaRecognizer] 驗證碼圖片位置: \(rect)")
            completion(rect)
        }
    }
    
    private func cropImage(image: UIImage, rect: CGRect) -> UIImage? {
        let scale = image.scale
        let scaledRect = CGRect(
            x: rect.origin.x * scale,
            y: rect.origin.y * scale,
            width: rect.size.width * scale,
            height: rect.size.height * scale
        )
        
        guard let cgImage = image.cgImage?.cropping(to: scaledRect) else {
            return nil
        }
        
        return UIImage(cgImage: cgImage, scale: scale, orientation: image.imageOrientation)
    }
    
    private func recognizeText(from image: UIImage, completion: @escaping (String?) -> Void) {
        guard let cgImage = image.cgImage else {
            completion(nil)
            return
        }
        
        let request = VNRecognizeTextRequest { request, error in
            guard error == nil else {
                print("❌ [CaptchaRecognizer] OCR識別失敗: \(error!.localizedDescription)")
                completion(nil)
                return
            }
            
            let observations = request.results as? [VNRecognizedTextObservation] ?? []
            
            let recognizedStrings = observations.compactMap { observation in
                observation.topCandidates(1).first?.string
            }
            
            let filteredResults = recognizedStrings
                .map { self.cleanupRecognizedText($0) }
                .filter { !$0.isEmpty }
            
            if let bestResult = self.selectBestCaptchaResult(from: filteredResults) {
                completion(bestResult)
            } else {
                completion(nil)
            }
        }
        
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        
        if #available(iOS 16.0, *) {
            request.automaticallyDetectsLanguage = true
        } else {
            request.recognitionLanguages = ["en-US", "zh-Hans", "zh-Hant"]
        }
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                print("❌ [CaptchaRecognizer] Vision 處理失敗: \(error)")
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }
    
    private func cleanupRecognizedText(_ text: String) -> String {
        return text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\t", with: "")
    }
    
    private func selectBestCaptchaResult(from results: [String]) -> String? {
        guard !results.isEmpty else { return nil }
        
        let sortedResults = results.sorted { result1, result2 in
            let score1 = scoreCaptchaCandidate(result1)
            let score2 = scoreCaptchaCandidate(result2)
            return score1 > score2
        }
        
        let bestResult = sortedResults.first!
        print("🎯 [CaptchaRecognizer] 最佳驗證碼候選: \(bestResult) (從 \(results.count) 個結果中選出)")
        
        return bestResult
    }
    
    private func scoreCaptchaCandidate(_ candidate: String) -> Int {
        var score = 0
        
        if candidate.count >= 3 && candidate.count <= 8 {
            score += 10
        }
        
        let hasDigits = candidate.rangeOfCharacter(from: .decimalDigits) != nil
        let hasLetters = candidate.rangeOfCharacter(from: .letters) != nil
        
        if hasDigits && hasLetters {
            score += 15
        } else if hasDigits || hasLetters {
            score += 10
        }
        
        if candidate.count < 2 || candidate.count > 10 {
            score -= 20
        }
        
        let specialCharacters = CharacterSet.alphanumerics.inverted
        if candidate.rangeOfCharacter(from: specialCharacters) != nil {
            score -= 5
        }
        
        return score
    }
}