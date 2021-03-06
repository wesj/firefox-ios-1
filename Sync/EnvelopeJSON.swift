/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared

public class EnvelopeJSON {
    private let json: JSON

    public init(_ jsonString: String) {
        self.json = JSON.parse(jsonString)
    }

    public init(_ json: JSON) {
        self.json = json
    }

    public func isValid() -> Bool {
        return !self.json.isError &&
            self.json["id"].isString &&
            //self["collection"].isString &&
            self.json["payload"].isString
    }

    public var id: String {
        return self.json["id"].asString!
    }

    public var collection: String {
        return self.json["collection"].asString ?? ""
    }

    public var payload: String {
        return self.json["payload"].asString!
    }

    public var sortindex: Int {
        return self.json["sortindex"].asInt ?? 0
    }

    public var modified: UInt64 {
        if (self.json["modified"].isInt) {
            return UInt64(self.json["modified"].asInt!) * 1000
        }

        if (self.json["modified"].isDouble) {
            return UInt64(1000 * (self.json["modified"].asDouble? ?? 0.0))
        }

        return 0
    }
}