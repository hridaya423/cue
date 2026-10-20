import AppKit
import ApplicationServices
import CueKit
import Foundation
import WebKit

func jsQuote(_ s: String) -> String {
    guard let d = try? JSONSerialization.data(withJSONObject: [s]),
          var q = String(data: d, encoding: .utf8), q.count > 2 else { return "\"\"" }
    q.removeFirst(); q.removeLast()
    return q
}

struct DayError: Error, CustomStringConvertible {
    var description: String
    init(_ s: String) { description = s }
}

func eprint(_ s: String) {
    FileHandle.standardError.write(Data((s + "\n").utf8))
}

/// One replay surface hosted in-process: a real window holding a real
/// WKWebView / NSTextView / NSTextField. Ordered in (so it vends an AX tree)
/// but invisible, dead to the mouse, and behind everything.
@MainActor
final class DaySurfaceHost {
    let spec: DaySurface
    let window: NSWindow
    private let pasteboard: NSPasteboard
    private(set) var webView: WKWebView?
    private var textView: NSTextView?
    private var textField: NSTextField?
    private var axID: String { "cueday:\(spec.id)" }

    init(spec: DaySurface, pagesDir: URL, pasteboard: NSPasteboard) {
        self.spec = spec
        self.pasteboard = pasteboard
        let w = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 1200, height: 900),
                         styleMask: [.borderless], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.title = spec.window
        // Surfaces share window titles (an inbox and its compose window): find ours by identifier.
        w.setAccessibilityIdentifier("cueday:\(spec.id):window")
        w.alphaValue = 0
        w.ignoresMouseEvents = true
        w.hasShadow = false
        window = w
        switch spec.kind {
        case "web":
            let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 900),
                               configuration: WKWebViewConfiguration())
            w.contentView = wv
            webView = wv
            let html = (try? String(contentsOf: pagesDir.appendingPathComponent(spec.page),
                                    encoding: .utf8)) ?? "<html><body></body></html>"
            // baseURL carries the impersonated host into AXURL → webHost.
            wv.loadHTMLString(html, baseURL: URL(string: "https://\(spec.host)/"))
            // Ask WebKit to vend the web content's accessibility tree —
            // the attribute AT clients use.
            wv.setAccessibilityElement(true)
            wv.setAccessibilityIdentifier(axID)
        case "native-field":
            let f = NSTextField(frame: NSRect(x: 20, y: 160, width: 480, height: 28))
            f.isEditable = true
            f.isBezeled = true
            f.setAccessibilityTitle(spec.field.label)
            f.setAccessibilityPlaceholderValue(spec.field.placeholder)
            f.setAccessibilityIdentifier(axID)
            w.contentView = f
            textField = f
        default:
            let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 520, height: 360))
            tv.isRichText = false
            tv.autoresizingMask = [.width, .height]
            tv.setAccessibilityTitle(spec.field.label)
            tv.setAccessibilityIdentifier(axID)
            w.contentView = tv
            textView = tv
        }
        w.orderBack(nil)
    }

    func waitReady() async {
        guard let webView else { return }
        for _ in 0..<200 {
            if let s = (try? await webView.evaluateJavaScript("document.readyState")) as? String,
               s == "complete" {
                enableWebAX()
                return
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// WebKit lazily enables the web-content AX tree when an AT sets these.
    private func enableWebAX() {
        let app = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        guard let wvEl = axFind(app, where: { axString($0, "AXIdentifier") == axID })
        else { return }
        for attr in ["AXManualAccessibility", "AXEnhancedUserInterface",
                     "AXEnhancedUserInterfaceEnabled", "AXWebAutomationSessionEnabled"] {
            AXUIElementSetAttributeValue(wvEl, attr as CFString, kCFBooleanTrue)
        }
    }

    /// Focus the target field and set its pre-paste content.
    func prepare(field fid: String, value: String) async throws {
        if let f = textField {
            window.makeFirstResponder(nil)
            f.stringValue = value
            window.makeFirstResponder(f)
            for _ in 0..<100 where f.currentEditor() == nil {
                try await Task.sleep(for: .milliseconds(20))
            }
            if let ed = f.currentEditor() as? NSTextView {
                ed.setSelectedRange(NSRange(location: (ed.string as NSString).length, length: 0))
            }
        } else if let tv = textView {
            tv.string = value
            window.makeFirstResponder(tv)
            tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
        } else if webView != nil {
            let r = try await jsField(fid, op: "set", arg: value)
            guard r["ok"] as? Bool == true else {
                throw DayError("web field \(fid): \(r["error"] ?? "missing")")
            }
        }
    }

    /// Insert text like a real paste: NSTextView/editor via readSelection on
    /// our private pasteboard, WKWebView via execCommand('insertText').
    /// Returns the field's new content.
    func insert(_ fid: String, _ text: String) async throws -> String {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        if let f = textField {
            guard let ed = f.currentEditor() as? NSTextView else {
                throw DayError("field editor missing")
            }
            ed.setSelectedRange(NSRange(location: (ed.string as NSString).length, length: 0))
            if !ed.readSelection(from: pasteboard) {
                ed.insertText(text, replacementRange: ed.selectedRange)
            }
            return ed.string
        }
        if let tv = textView {
            tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
            if !tv.readSelection(from: pasteboard) {
                tv.insertText(text, replacementRange: tv.selectedRange)
            }
            return tv.string
        }
        let r = try await jsField(fid, op: "insert", arg: text)
        return r["value"] as? String ?? ""
    }

    /// Persona ⌘Z: restore the field to what it held before the paste.
    func restore(_ fid: String, value: String) async throws {
        if let f = textField {
            if let ed = f.currentEditor() as? NSTextView {
                ed.string = value
                ed.setSelectedRange(NSRange(location: (ed.string as NSString).length, length: 0))
            }
            f.stringValue = value
        } else if let tv = textView {
            tv.string = value
        } else {
            _ = try await jsField(fid, op: "set", arg: value)
        }
    }

    /// The AX element standing for the focused field. Web: the web area's
    /// AX-focused element (real DOM focus), falling back to matching the
    /// field's live descriptor in the AX tree. Native: the control carrying
    /// our accessibility identifier.
    func element(forField fid: String) async -> AXUIElement? {
        let app = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        // Windows are the app's direct children; a recursive search would walk every page's tree.
        let scope = axChildren(app).first { axString($0, "AXIdentifier") == "\(axID):window" } ?? app
        if webView != nil {
            // The remote web-content element publishes its tree lazily —
            // poll briefly while it materializes.
            for _ in 0..<100 {
                if let area = axFind(scope, where: { axString($0, kAXRoleAttribute) == "AXWebArea" }) {
                    if let focused = axElement(area, kAXFocusedUIElementAttribute),
                       let role = axString(focused, kAXRoleAttribute), role != "AXWebArea" {
                        return focused
                    }
                    if let d = try? await jsField(fid, op: "read"), d["ok"] as? Bool == true {
                        let label = d["label"] as? String ?? ""
                        let ph = d["placeholder"] as? String ?? ""
                        let val = d["value"] as? String ?? ""
                        if let hit = axFind(area) { el in
                            let role = axString(el, kAXRoleAttribute) ?? ""
                            guard role != "AXStaticText", role != "AXWebArea" else { return false }
                            if !label.isEmpty,
                               axString(el, kAXTitleAttribute) == label
                                || axString(el, kAXDescriptionAttribute) == label { return true }
                            if !val.isEmpty, axString(el, kAXValueAttribute) == val { return true }
                            if !ph.isEmpty, axString(el, "AXPlaceholderValue") == ph { return true }
                            return false
                        } { return hit }
                    }
                }
                try? await Task.sleep(for: .milliseconds(30))
            }
            return nil
        }
        return axFind(scope) { axString($0, "AXIdentifier") == axID }
    }

    /// One JS entry point for field focus/set/insert/read. `fid` "main"
    /// resolves to the page's first editable element.
    private func jsField(_ fid: String, op: String, arg: String = "") async throws -> [String: Any] {
        guard let webView else { throw DayError("not a web surface") }
        let script = """
        (function(a){var el=null;
          if(a.f)el=document.getElementById(a.f)
            ||document.querySelector('[name="'+CSS.escape(a.f)+'"]')
            ||document.querySelector('[aria-label="'+CSS.escape(a.f)+'"]');
          if(!el)el=document.querySelector('textarea,[contenteditable=true],[contenteditable=""],input:not([type=hidden]):not([type=checkbox]):not([type=radio]):not([type=submit]):not([type=button])');
          if(!el)return{ok:false,error:'no field '+a.f};
          el.focus();
          var ed=el.isContentEditable===true;
          var get=function(){return ed?el.innerText:el.value};
          var set=function(v){if(ed){el.innerText=v}else{el.value=v}el.dispatchEvent(new Event('input',{bubbles:true}))};
          if(a.op==='set')set(a.v);
          else if(a.op==='insert'){
            var before=get();
            if(ed){var r=document.createRange();r.selectNodeContents(el);r.collapse(false);
              var s=getSelection();s.removeAllRanges();s.addRange(r)}
            else{try{el.setSelectionRange((el.value||'').length,(el.value||'').length)}catch(e){}}
            try{document.execCommand('insertText',false,a.v)}catch(e){}
            if(get()===before&&a.v!==''){
              if(ed){var t=document.createTextNode(a.v);el.appendChild(t)}
              else{var st=(el.selectionStart==null)?before.length:el.selectionStart;
                var en=(el.selectionEnd==null)?st:el.selectionEnd;
                el.value=before.slice(0,st)+a.v+before.slice(en)}
              el.dispatchEvent(new Event('input',{bubbles:true}))
            }}
          var lab=el.getAttribute('aria-label')||'';
          if(!lab&&el.labels&&el.labels.length)lab=el.labels[0].innerText;
          if(!lab&&el.getAttribute('aria-labelledby')){
            var l=document.getElementById(el.getAttribute('aria-labelledby'));lab=l?l.innerText:''}
          return{ok:true,tag:el.tagName.toLowerCase(),label:lab,
            placeholder:el.getAttribute('placeholder')||'',value:get(),
            focused:document.activeElement===el};
        })({f:\(jsQuote(fid)),op:\(jsQuote(op)),v:\(jsQuote(arg))})
        """
        let r = try await webView.evaluateJavaScript(script)
        return r as? [String: Any] ?? [:]
    }

    /// Debug dump of this surface's AX subtree (--dump-ax).
    func dumpAX() async {
        let app = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        if let webView {
            let state = (try? await webView.evaluateJavaScript(
                "document.readyState+'|'+document.documentElement.outerHTML.length")) as? String
            eprint("  webview state=\(state ?? "<js failed>")")
            for _ in 0..<100 {
                if axFind(app, where: { axString($0, kAXRoleAttribute) == "AXWebArea" }) != nil { break }
                try? await Task.sleep(for: .milliseconds(30))
            }
        }
        let kids = axChildren(app)
        eprint("trusted=\(AXIsProcessTrusted()) appChildren=\(kids.count) " +
               "winVisible=\(window.isVisible) winFrame=\(window.frame)")
        for k in kids {
            eprint("  app child: \(axString(k, kAXRoleAttribute) ?? "?") \(axString(k, kAXTitleAttribute) ?? "")")
        }
        let win = axFind(app) { el in
            axString(el, kAXRoleAttribute) == "AXWindow"
                && axString(el, kAXTitleAttribute) == spec.window
        }
        func walk(_ el: AXUIElement, _ d: Int) {
            guard d < 12 else { return }
            let role = axString(el, kAXRoleAttribute) ?? "?"
            let title = axString(el, kAXTitleAttribute) ?? ""
            let val = String((axString(el, kAXValueAttribute) ?? "").prefix(40))
            let ident = axString(el, "AXIdentifier") ?? ""
            eprint("\(String(repeating: "  ", count: d))\(role) t=\(title) v=\(val) id=\(ident)")
            for c in axChildren(el) { walk(c, d + 1) }
        }
        eprint("== \(spec.id) ==")
        if let win { walk(win, 0) } else { eprint("  (window not in AX tree)") }
    }
}
