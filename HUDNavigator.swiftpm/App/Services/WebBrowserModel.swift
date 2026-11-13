import SwiftUI
import WebKit
import Observation

/// ブラウザを載せる場所。WKWebView は 1 つだけなので、優先度の高い場所に載せ替える。
enum WebHost: Int, Comparable {
    /// ワーク画面（端末で直接さわれる）
    case workScreen = 0
    /// 端末の HUD 全画面
    case deviceHUD = 1
    /// グラス（さわれないので、端末のトラックパッドで操作する）
    case glasses = 2

    static func < (a: WebHost, b: WebHost) -> Bool { a.rawValue < b.rawValue }
}

/// HUD に出すブラウザ。グラスに映したページを、端末の画面（トラックパッド・キーボード）から操作できる。
@MainActor
@Observable
final class WebBrowserModel: NSObject {
    private(set) var title = ""
    private(set) var urlString = ""
    private(set) var isLoading = false
    private(set) var progress: Double = 0
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    private(set) var lastError: String?
    /// 今ページが載っている場所
    private(set) var activeHost: WebHost?
    /// カーソルの位置（ページの表示範囲に対する 0〜1）
    private(set) var cursor = CGPoint(x: 0.5, y: 0.4)
    /// 最後に押した所が文字を入力できる欄か
    private(set) var isTextFieldFocused = false
    private(set) var hasLoaded = false

    var darkMode = true { didSet { if darkMode != oldValue { applyDarkMode() } } }
    var desktopMode = false { didSet { if desktopMode != oldValue { applyContentMode(reload: true) } } }
    var zoom: Double = 1 { didSet { if zoom != oldValue { webView?.pageZoom = zoom } } }

    @ObservationIgnored private(set) var webView: WKWebView?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var hosts: [WebHost: Int] = [:]
    @ObservationIgnored var onNavigated: ((String) -> Void)?

    /// 暗い見た目にする CSS（グラスでは白い背景がまぶしく、黒は透明になるため）
    private static let darkCSS = "html{filter:invert(1) hue-rotate(180deg)!important;background:#fff!important}img,video,picture,canvas,svg image,iframe,[style*=\"background-image\"]{filter:invert(1) hue-rotate(180deg)!important}"
    /// ページの地の色を見て、明るいページだけ反転する（もともと暗いページはそのまま）
    private static let darkBody = #"""
    var id = '__hudnav_dark';
    var el = document.getElementById(id);
    if (el) { el.remove(); }
    if (!on) { return false; }
    function lum(c) {
        var m = /rgba?\(([^)]+)\)/.exec(c || '');
        if (!m) { return null; }
        var p = m[1].split(',').map(parseFloat);
        if (p.length > 3 && p[3] === 0) { return null; }
        return (0.299 * p[0] + 0.587 * p[1] + 0.114 * p[2]) / 255;
    }
    var l = null;
    if (document.body) { l = lum(getComputedStyle(document.body).backgroundColor); }
    if (l === null) { l = lum(getComputedStyle(document.documentElement).backgroundColor); }
    if (l === null) { l = 1; }
    if (l < 0.4) { return false; }
    el = document.createElement('style');
    el.id = id;
    el.textContent = css;
    (document.head || document.documentElement).appendChild(el);
    return true;
    """#

    // MARK: - 準備

    /// 必要になったときに 1 度だけ作る
    @discardableResult
    func prepare() -> WKWebView {
        if let webView { return webView }
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.defaultWebpagePreferences.preferredContentMode = desktopMode ? .desktop : .recommended
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 1280, height: 720), configuration: config)
        view.navigationDelegate = self
        view.uiDelegate = self
        view.allowsBackForwardNavigationGestures = true
        view.isOpaque = false
        view.backgroundColor = .black
        view.scrollView.backgroundColor = .black
        view.pageZoom = zoom
        observations = [
            view.observe(\.title) { [weak self] v, _ in Task { @MainActor in self?.title = v.title ?? "" } },
            view.observe(\.url) { [weak self] v, _ in Task { @MainActor in self?.urlString = v.url?.absoluteString ?? "" } },
            view.observe(\.isLoading) { [weak self] v, _ in Task { @MainActor in self?.isLoading = v.isLoading } },
            view.observe(\.estimatedProgress) { [weak self] v, _ in Task { @MainActor in self?.progress = v.estimatedProgress } },
            view.observe(\.canGoBack) { [weak self] v, _ in Task { @MainActor in self?.canGoBack = v.canGoBack } },
            view.observe(\.canGoForward) { [weak self] v, _ in Task { @MainActor in self?.canGoForward = v.canGoForward } },
        ]
        webView = view
        return view
    }

    // MARK: - 載せる場所

    /// 表示する場所が現れた・消えた（いちばん優先度の高い場所に載せる）
    func register(_ host: WebHost) {
        hosts[host, default: 0] += 1
        updateActiveHost()
    }

    func unregister(_ host: WebHost) {
        let n = (hosts[host] ?? 0) - 1
        hosts[host] = n > 0 ? n : nil
        updateActiveHost()
    }

    private func updateActiveHost() {
        let best = hosts.keys.max()
        if best != activeHost { activeHost = best }
    }

    // MARK: - 移動

    /// アドレスか検索語を開く
    func open(_ input: String) {
        guard let address = WebAddress.resolve(input), let url = URL(string: address) else {
            lastError = "開けないアドレスです。"
            return
        }
        lastError = nil
        hasLoaded = true
        prepare().load(URLRequest(url: url))
    }

    /// まだ何も開いていなければ、前回のページ（なければホーム）を開く
    func openIfNeeded(last: String?, home: String) {
        guard !hasLoaded else { return }
        open(last ?? home)
    }

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func reload() { webView?.reload() }
    func stopLoading() { webView?.stopLoading() }

    // MARK: - 端末からの操作（グラスに映しているとき）

    private func run(_ body: String, _ arguments: [String: Any] = [:], completion: ((Any?) -> Void)? = nil) {
        guard let webView else { return }
        webView.callAsyncJavaScript(body, arguments: arguments, in: nil, in: .page) { result in
            if case .success(let value) = result { completion?(value) } else { completion?(nil) }
        }
    }

    /// スクロール（画面の高さに対する割合。正＝下へ）
    func scroll(byScreens amount: Double) {
        run("window.scrollBy({top: window.innerHeight * amount, left: 0, behavior: smooth ? 'smooth' : 'auto'});", ["amount": amount, "smooth": abs(amount) >= 0.3])
    }

    func scroll(dx: Double, dy: Double) {
        run("window.scrollBy(dx, dy);", ["dx": dx, "dy": dy])
    }

    func scrollToTop() { run("window.scrollTo({top: 0, behavior: 'smooth'});") }

    func moveCursor(dx: Double, dy: Double) {
        cursor = CGPoint(x: (cursor.x + dx).clamped(to: 0...1), y: (cursor.y + dy).clamped(to: 0...1))
    }

    /// カーソルの位置を押す
    func click() {
        let script = """
        var x = nx * window.innerWidth, y = ny * window.innerHeight;
        var el = document.elementFromPoint(x, y);
        if (!el) { return 'none'; }
        var o = {bubbles: true, cancelable: true, view: window, clientX: x, clientY: y};
        ['pointerdown', 'mousedown', 'pointerup', 'mouseup'].forEach(function (t) {
            try { el.dispatchEvent(new MouseEvent(t, o)); } catch (e) {}
        });
        if (typeof el.click === 'function') { el.click(); } else { el.dispatchEvent(new MouseEvent('click', o)); }
        var field = el.closest ? el.closest('input, textarea, [contenteditable=""], [contenteditable="true"]') : null;
        if (field) { field.focus(); return 'text'; }
        return 'other';
        """
        run(script, ["nx": Double(cursor.x), "ny": Double(cursor.y)]) { [weak self] value in
            let isText = (value as? String) == "text"
            Task { @MainActor in self?.isTextFieldFocused = isText }
        }
    }

    /// 入力欄に文字を入れる
    func insertText(_ text: String) {
        guard !text.isEmpty else { return }
        let script = """
        var el = document.activeElement;
        if (!el) { return false; }
        if (document.execCommand && document.execCommand('insertText', false, t)) { return true; }
        if ('value' in el) {
            var proto = el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
            var setter = Object.getOwnPropertyDescriptor(proto, 'value').set;
            setter.call(el, (el.value || '') + t);
            el.dispatchEvent(new Event('input', {bubbles: true}));
            return true;
        }
        return false;
        """
        run(script, ["t": text])
    }

    func deleteBackward() {
        run("""
        var el = document.activeElement;
        if (!el) { return; }
        if (document.execCommand && document.execCommand('delete', false, null)) { return; }
        if ('value' in el && el.value.length > 0) {
            var proto = el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
            Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, el.value.slice(0, -1));
            el.dispatchEvent(new Event('input', {bubbles: true}));
        }
        """)
    }

    /// Enter（検索・送信）
    func pressEnter() {
        run("""
        var el = document.activeElement || document.body;
        var o = {key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true, cancelable: true};
        var go = el.dispatchEvent(new KeyboardEvent('keydown', o));
        el.dispatchEvent(new KeyboardEvent('keypress', o));
        el.dispatchEvent(new KeyboardEvent('keyup', o));
        if (go && el.form) {
            if (typeof el.form.requestSubmit === 'function') { el.form.requestSubmit(); } else { el.form.submit(); }
        } else if (go && el.tagName === 'TEXTAREA') {
            document.execCommand('insertText', false, '\\n');
        }
        """)
    }

    // MARK: - 見た目

    private func applyDarkMode() {
        run(Self.darkBody, ["on": darkMode, "css": Self.darkCSS])
    }

    /// パソコン用・スマホ用の切り替えは、ページを開くたびに指定する（下の decidePolicyFor）。切り替えたら読み込み直す
    private func applyContentMode(reload: Bool) {
        if reload, hasLoaded { webView?.reload() }
    }

    fileprivate func pageStarted() {
        isTextFieldFocused = false
        if darkMode { applyDarkMode() }
    }

    fileprivate func pageFinished() {
        if darkMode { applyDarkMode() }
        if !urlString.isEmpty { onNavigated?(urlString) }
    }

    fileprivate func pageFailed(_ error: Error) {
        let ns = error as NSError
        // 読み込みの中断（別のページへ移動）はエラーとして出さない
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
        lastError = ns.localizedDescription
    }
}

extension WebBrowserModel: WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        pageStarted()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageFinished()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        pageFailed(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        pageFailed(error)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, preferences: WKWebpagePreferences) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
        preferences.preferredContentMode = desktopMode ? .desktop : .recommended
        return (.allow, preferences)
    }

    /// 新しいウインドウで開くリンクは、同じ画面で開く
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }
}

/// WKWebView を載せる入れ物。自分の番（isActive）のときだけページを受け取る。
struct WebHostView: UIViewRepresentable {
    let browser: WebBrowserModel
    let host: WebHost
    let isActive: Bool
    var allowsTouch: Bool

    final class Container: UIView {
        weak var hosted: WKWebView?

        func attach(_ webView: WKWebView) {
            guard webView.superview !== self else { return }
            webView.removeFromSuperview()
            webView.frame = bounds
            webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(webView)
            hosted = webView
        }

        func detach() {
            if let hosted, hosted.superview === self { hosted.removeFromSuperview() }
            hosted = nil
        }
    }

    func makeUIView(context: Context) -> Container {
        let view = Container()
        view.backgroundColor = .black
        view.clipsToBounds = true
        return view
    }

    func updateUIView(_ view: Container, context: Context) {
        view.isUserInteractionEnabled = allowsTouch
        if isActive {
            view.attach(browser.prepare())
        } else {
            view.detach()
        }
    }

    static func dismantleUIView(_ view: Container, coordinator: ()) {
        view.detach()
    }
}
