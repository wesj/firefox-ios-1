/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow!

    func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject: AnyObject]?) -> Bool {
        self.window = UIWindow(frame: UIScreen.mainScreen().bounds)
        self.window.backgroundColor = UIColor.whiteColor()

        var accountManager: AccountManager!
        let account: Account = MockAccount()

        accountManager = AccountManager(
            loginCallback: { account in
                // Show the tab controller once the user logs in.
                //self.showTabBarViewController(account)
            },
            logoutCallback: { account in
                // Show the login controller once the user logs out.
                //self.showLoginViewController(accountManager)
        })

        self.showTabBarViewController(account)


        self.window.makeKeyAndVisible()
        return true
    }

    func showTabBarViewController(account: Account) {
        let tabBarViewController = TabBarViewController(nibName: "TabBarViewController", bundle: nil)
        tabBarViewController.account = account
        self.window.rootViewController = tabBarViewController
    }

    func showLoginViewController(accountManager: AccountManager) {
        let loginViewController = LoginViewController()
        loginViewController.accountManager = accountManager
        self.window.rootViewController = loginViewController
    }
}
