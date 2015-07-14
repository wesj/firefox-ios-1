/* This Source Code Form is subject to the terms of the Mozilla Public
* License, v. 2.0. If a copy of the MPL was not distributed with this
* file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import WebKit
import Storage
import Shared

class FaviconManager : BrowserHelper {
    let profile: Profile!
    weak var browser: Browser?

    init(browser: Browser, profile: Profile) {
        self.profile = profile
        self.browser = browser

        if let path = NSBundle.mainBundle().pathForResource("Favicons", ofType: "js") {
            if let source = NSString(contentsOfFile: path, encoding: NSUTF8StringEncoding, error: nil) as? String {
                var userScript = WKUserScript(source: source, injectionTime: WKUserScriptInjectionTime.AtDocumentEnd, forMainFrameOnly: true)
                browser.webView!.configuration.userContentController.addUserScript(userScript)
            }
        }
    }

    class func name() -> String {
        return "FaviconsManager"
    }

    func scriptMessageHandlerName() -> String? {
        return "faviconsMessageHandler"
    }

    private func downloadIcon(icon: Favicon) -> Deferred<Result<Favicon>> {
        let deferred = Deferred<Result<Favicon>>()
        let manager = SDWebImageManager.sharedManager()
        manager.downloadImageWithURL(icon.url.asURL!, options: SDWebImageOptions.LowPriority, progress: nil) { (img, err, cacheType, Success, url) -> Void in
            if let img = img {
                let fav = Favicon(url: url.absoluteString!,
                                  type: icon.type)
                fav.width = Int(img.size.width)
                fav.height = Int(img.size.height)
                deferred.fill(Result(success: fav))
            } else {
                // deferred.fill(Result(failure: ErrorType()))
            }
        }
        return deferred
    }

    func userContentController(userContentController: WKUserContentController, didReceiveScriptMessage message: WKScriptMessage) {
        self.browser?.favicons.removeAll(keepCapacity: false)

        if let url = browser?.webView!.URL?.absoluteString {
            let site = Site(url: url, title: "")
            profile.favicons.getFaviconsForSite(site) >>== { storedIcons in
                if let icons = message.body as? [String: Int] {
                    for icon in icons {
                        if let iconUrl = NSURL(string: icon.0) {
                            let icon = Favicon(iconUrl, type: IconType(rawValue: icon.1)!)
                            self.browser?.favicons.append(icon)
                            if let index = find(storedIcons, icon) {
                                storedIcons.removeAtIndex(index)
                                return Deferred(Result(icon))
                            } else {
                                return downloadIcon(icon)
                            }
                        }
                    }
                }

                profile.favicons.removeIcons(storedIcons)
            }
        }
    }
}