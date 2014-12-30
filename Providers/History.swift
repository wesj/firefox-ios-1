// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import Alamofire

private protocol Model {
    typealias T
    subscript(key: String) -> T { get }
}

// TODO: Move this to DataAccess once we have a better data abstraction (i.e. protocol)
//       around it
/* This provides basic access to History records stored in core data */
private class HistoryCoreDataModel {
    typealias T = Site

    subscript(key: String) -> T {
        get {
            return Site.MR_findFirstOrCreateByAttribute("url", withValue: key)
        }

        set(newValue) {
            MagicalRecord.saveWithBlockAndWait({ context in
                var site = Site.MR_findFirstOrCreateByAttribute("url", withValue: key, inContext: context)
                site.title = newValue.title
                site.lastVisit = newValue.lastVisit
                site.numVisits = newValue.numVisits
            })

        }
    }
}

// A private queue for history actions. This is used to ensure that actions happen serially on a background thread.
private let queue = dispatch_queue_create("HistoryQueue", DISPATCH_QUEUE_SERIAL)

public class History {
    private let model = HistoryCoreDataModel()

    func addVisit(url: String, title: String, callback: (Site) -> Void) {
        // Do an async dispatch to ensure this behaves like an async api
        dispatch_async(queue, { _ in
            // Get any current data from the model. If none exists, get a new blank entry
            var s = self.model[url]

            // Now update the model data
            s.title = title
            s.lastVisit = NSDate()
            s.numVisits++

            // Resave the updated data into the model
            self.model[url] = s;
            dispatch_async(dispatch_get_main_queue(), { () in
                callback(s)
            })
        })
    }

    func getAll() -> [Site] {
        return Site.MR_findAllSortedBy("lastVisit", ascending: false) as [Site]
    }
}
