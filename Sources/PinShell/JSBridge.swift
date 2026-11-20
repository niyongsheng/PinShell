import AppKit
import WebKit
import PinShellCore

/// HTML ↔ 原生桥：
/// - documentStart 注入 window.pinshell；
/// - 通过 WKScriptMessageHandler 接收页面指令；
/// - 页面 emit 的事件转发给 ControlServer（CLI listen）。
final class JSBridge: NSObject, WKScriptMessageHandler {
    weak var controller: OverlayWindowController?

    private static let maxMessageBytes = 64 * 1024

    static let injectionScript = #"""
    (function () {
      if (window.pinshell) { return; }
      function post(payload) {
        try { window.webkit.messageHandlers.pinshell.postMessage(payload); } catch (e) {}
      }
      var pinshell = {
        version: '1',
        setSize: function (width, height) {
          post({ action: 'setSize', width: Number(width), height: Number(height) });
        },
        setPosition: function (x, y) {
          if (typeof x === 'string') {
            post({ action: 'setPosition', anchor: x });
          } else {
            post({ action: 'setPosition', x: Number(x), y: Number(y) });
          }
        },
        setPassthrough: function (enabled) {
          post({ action: 'setPassthrough', enabled: !!enabled });
        },
        setOpacity: function (value) {
          post({ action: 'setOpacity', value: Number(value) });
        },
        setRadius: function (value) {
          post({ action: 'setRadius', value: Number(value) });
        },
        emit: function (name, data) {
          post({ action: 'emit', name: String(name), data: data });
        },
        log: function () {
          post({ action: 'log', message: Array.prototype.map.call(arguments, String).join(' ') });
        },
        on: function (name, callback) {
          window.addEventListener('pinshell:event', function (event) {
            var detail = event.detail || {};
            if (detail.name === name && typeof callback === 'function') {
              callback(detail.data);
            }
          });
        }
      };
      var fetchSeq = 0;
      var fetchPending = {};
      pinshell.fetch = function (url, options) {
        return new Promise(function (resolve, reject) {
          if (typeof url !== 'string' || !/^https:\/\//i.test(url)) {
            reject(new Error('pinshell.fetch: only https URLs are supported'));
            return;
          }
          var id = String(++fetchSeq);
          fetchPending[id] = { resolve: resolve, reject: reject };
          post({ action: 'fetch', id: id, url: url,
                 headers: (options && options.headers) || {} });
        });
      };
      window.__pinshellFetchResult = function (id, ok, body, error) {
        var pending = fetchPending[id];
        if (!pending) { return; }
        delete fetchPending[id];
        if (ok) { pending.resolve(body); }
        else { pending.reject(new Error(error || 'fetch failed')); }
      };
      window.pinshell = pinshell;
    })();
    """#

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }

        // 防止页面发送超大 payload 占满内存/通道
        if let data = try? JSONSerialization.data(withJSONObject: body),
           data.count > Self.maxMessageBytes {
            controller?.broadcast(.error("bridge message exceeds \(Self.maxMessageBytes) bytes"))
            return
        }

        let payload = JSONValue(any: body)
        switch action {
        case "setSize":
            guard let width = payload["width"]?.doubleValue,
                  let height = payload["height"]?.doubleValue else { return }
            controller?.setWindowSize(width: width, height: height)

        case "setPosition":
            if let anchor = payload["anchor"]?.stringValue,
               let position = WindowPosition.parse(anchor) {
                controller?.setWindowPosition(position)
            } else if let x = payload["x"]?.doubleValue,
                      let y = payload["y"]?.doubleValue {
                controller?.setWindowPosition(.absolute(x: x, y: y))
            }

        case "setPassthrough":
            if let enabled = payload["enabled"]?.boolValue {
                controller?.setPassthrough(enabled)
            }

        case "setOpacity":
            if let value = payload["value"]?.doubleValue {
                controller?.setWindowOpacity(value)
            }

        case "setRadius":
            if let value = payload["value"]?.doubleValue, value >= 0 {
                controller?.setWindowRadius(value)
            }

        case "emit":
            guard let name = payload["name"]?.stringValue, !name.isEmpty else { return }
            controller?.broadcast(.emit(name: String(name.prefix(256)),
                                        data: payload["data"] ?? .null))

        case "log":
            let text = payload["message"]?.stringValue ?? ""
            NSLog("PinShell JS: %@", text)
            controller?.broadcast(.log(String(text.prefix(4096))))

        case "fetch":
            guard let id = payload["id"]?.stringValue,
                  let rawURL = payload["url"]?.stringValue,
                  let url = URL(string: rawURL),
                  url.scheme?.lowercased() == "https",
                  url.host != nil else {
                if let id = payload["id"]?.stringValue {
                    controller?.resolveFetch(id: id, ok: false, body: "",
                                             error: "pinshell.fetch: invalid https URL")
                }
                return
            }
            var headers: [String: String] = [:]
            if let values = payload["headers"]?.objectValue {
                for (key, value) in values.prefix(20) {
                    if key.count <= 128, let string = value.stringValue, string.count <= 2048 {
                        headers[key] = string
                    }
                }
            }
            controller?.performFetch(id: id, url: url, headers: headers)

        default:
            NSLog("PinShell JS: unknown bridge action %@", action)
        }
    }
}
