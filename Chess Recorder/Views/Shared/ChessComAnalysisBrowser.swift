//
//  ChessComAnalysisBrowser.swift
//  Chess Recorder
//

import SwiftUI
import WebKit

#if canImport(UIKit)
import UIKit

/// Chess.com’s native app and often its mobile web UI ignore `?pgn=` for loading moves.
/// This browser loads the analysis page, keeps the PGN on the pasteboard, and retries a
/// small script that fills the PGN field and taps Load.
struct ChessComAnalysisBrowser: View {
    let url: URL
    let pgn: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ChessComAnalysisWebView(url: url, pgn: pgn)
                .ignoresSafeArea()
                .navigationTitle("Chess.com")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .onAppear {
            UIPasteboard.general.string = pgn
        }
    }
}

private struct ChessComAnalysisWebView: UIViewRepresentable {
    let url: URL
    let pgn: String

    func makeCoordinator() -> Coordinator {
        Coordinator(pgn: pgn)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Desktop layout uses the full analysis board; mobile is a cramped single column.
        config.defaultWebpagePreferences.preferredContentMode = .desktop
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.webView = webView
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let pgn: String
        weak var webView: WKWebView?
        private var injectionWorkItem: DispatchWorkItem?

        init(pgn: String) {
            self.pgn = pgn
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            schedulePGNInjection(on: webView)
        }

        private func schedulePGNInjection(on webView: WKWebView) {
            injectionWorkItem?.cancel()
            // SPA needs time to hydrate before the Load control exists.
            let delays: [TimeInterval] = [0.8, 1.6, 2.8, 4.5]
            for delay in delays {
                let work = DispatchWorkItem { [weak self, weak webView] in
                    guard let self, let webView else { return }
                    self.injectPGN(into: webView)
                }
                injectionWorkItem = work
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            }
        }

        private func injectPGN(into webView: WKWebView) {
            let escaped = Self.jsonString(pgn)
            let script = """
            (function() {
              var pgn = \(escaped);
              if (!pgn) return 'empty';

              function setNativeValue(el, value) {
                var proto = el instanceof HTMLTextAreaElement
                  ? window.HTMLTextAreaElement.prototype
                  : window.HTMLInputElement.prototype;
                var setter = Object.getOwnPropertyDescriptor(proto, 'value').set;
                setter.call(el, value);
                el.dispatchEvent(new Event('input', { bubbles: true }));
                el.dispatchEvent(new Event('change', { bubbles: true }));
              }

              var fields = Array.from(document.querySelectorAll('textarea, input[type="text"]'));
              var filled = 0;
              fields.forEach(function(el) {
                var hint = ((el.placeholder || '') + ' ' + (el.getAttribute('aria-label') || '') + ' ' + (el.className || '')).toLowerCase();
                if (hint.indexOf('pgn') !== -1 || hint.indexOf('fen') !== -1 || fields.length <= 3) {
                  setNativeValue(el, pgn);
                  filled++;
                }
              });

              var buttons = Array.from(document.querySelectorAll('button'));
              var loadBtn = buttons.find(function(b) {
                var label = (b.textContent || '').replace(/\\s+/g, ' ').trim();
                return /^Load$/i.test(label) || /^Add Game/i.test(label);
              });
              if (loadBtn) {
                loadBtn.click();
                return 'loaded:' + filled;
              }
              return 'filled:' + filled;
            })();
            """
            webView.evaluateJavaScript(script, completionHandler: nil)
        }

        private static func jsonString(_ value: String) -> String {
            // JSONSerialization requires an array/dictionary top level — wrap then strip.
            guard let data = try? JSONSerialization.data(withJSONObject: [value], options: []),
                  let encoded = String(data: data, encoding: .utf8),
                  encoded.count >= 2 else {
                return "''"
            }
            // `["…"]` → `"…"`
            return String(encoded.dropFirst().dropLast())
        }
    }
}
#endif
