/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import Shared

protocol Identifiable {
    var id: Int? { get set }
}

public enum IconType: Int {
    case Icon = 0
    case AppleIcon = 1
    case AppleIconPrecomposed = 2
    case Guess = 3
    case Local = 4
}

public class Favicon: Identifiable, Equatable {
    var id: Int? = nil
    var img: UIImage? = nil

    public let url: String
    public var width: Int?
    public var height: Int?
    public let type: IconType

    var _date: NSDate? = nil
    public var date: NSDate { return _date ?? NSDate() }

    public init(url: String, type: IconType) {
        self.url = url
        self.type = type
    }
}

public func ==(left: Favicon, right: Favicon) -> Bool {
    return left.url == right.url
}

// TODO: Site shouldn't have all of these optional decorators. Include those in the
// cursor results, perhaps as a tuple.
public class Site : Identifiable {
    var id: Int? = nil
    var guid: String? = nil

    public let url: String
    public let title: String
     // Sites may have multiple favicons. We'll return the largest.
    public var icon: Favicon?
    public var latestVisit: Visit?

    public init(url: String, title: String) {
        self.url = url
        self.title = title
    }
}
