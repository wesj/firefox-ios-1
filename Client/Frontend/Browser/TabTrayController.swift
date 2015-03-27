/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import UIKit

private struct TabTrayControllerUX {
    static let CornerRadius = CGFloat(4.0)
    static let BackgroundColor = UIColor(red: 0.21, green: 0.23, blue: 0.25, alpha: 1)
    static let TextBoxHeight = CGFloat(32.0)
    static let CellHeight = TextBoxHeight * 8
    static let Margin = CGFloat(15)
    // This color has been manually adjusted to match background layer with iOS translucency effect.
    static let ToolbarBarTintColor = UIColor(red: 0.35, green: 0.37, blue: 0.39, alpha: 0)
    static let TabTitleTextColor = UIColor.blackColor()
    static let TabTitleTextFont = UIFont(name: "HelveticaNeue-Bold", size: 11)
}

// UIcollectionViewController doesn't let us specify a style for recycling views. We override the default style here.
private class CustomCell: UICollectionViewCell {
    let backgroundHolder: UIView
    let background: UIImageViewAligned
    let titleText: UILabel
    let title: UIView
    let innerStroke: InnerStrokedView
    let favicon: UIImageView

    // Changes depending on whether we're full-screen or not.
    var margin = CGFloat(0)

    override init(frame: CGRect) {

        self.backgroundHolder = UIView()
        self.backgroundHolder.layer.shadowColor = UIColor.blackColor().CGColor
        self.backgroundHolder.layer.shadowOffset = CGSizeMake(0, 2.0)
        self.backgroundHolder.layer.shadowOpacity = 0.95
        self.backgroundHolder.layer.shadowRadius = 1.0
        self.backgroundHolder.layer.cornerRadius = TabTrayControllerUX.CornerRadius
        self.backgroundHolder.clipsToBounds = true

        self.background = UIImageViewAligned()
        self.background.contentMode = UIViewContentMode.ScaleAspectFill
        self.background.clipsToBounds = true
        self.background.userInteractionEnabled = false
        self.background.alignLeft = true
        self.background.alignTop = true

        self.favicon = UIImageView(image: UIImage(named: "defaultFavicon")!)
        self.favicon.backgroundColor = UIColor.clearColor()

        self.title = UIView()
        self.title.backgroundColor = UIColor.whiteColor()

        self.titleText = UILabel()
        self.titleText.textColor = TabTrayControllerUX.TabTitleTextColor
        self.titleText.backgroundColor = UIColor.clearColor()
        self.titleText.textAlignment = NSTextAlignment.Left
        self.titleText.userInteractionEnabled = false
        self.titleText.numberOfLines = 1
        self.titleText.font = TabTrayControllerUX.TabTitleTextFont

        self.title.addSubview(self.titleText)
        self.title.addSubview(self.favicon)

        self.innerStroke = InnerStrokedView(frame: self.backgroundHolder.frame)
        self.innerStroke.layer.backgroundColor = UIColor.clearColor().CGColor

        super.init(frame: frame)

        backgroundHolder.addSubview(self.background)
        addSubview(backgroundHolder)
        backgroundHolder.addSubview(self.title)
        backgroundHolder.addSubview(innerStroke)

        backgroundColor = UIColor.clearColor()

        self.titleText.addObserver(self, forKeyPath: "contentSize", options: .New, context: nil)

    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.titleText.removeObserver(self, forKeyPath: "contentSize")
    }

    private override func observeValueForKeyPath(keyPath: String, ofObject object: AnyObject, change: [NSObject: AnyObject], context: UnsafeMutablePointer<Void>) {
        let tv = object as UILabel
        verticalCenter(tv)
    }

    private func verticalCenter(text: UILabel) {
        var top = (TabTrayControllerUX.TextBoxHeight - text.bounds.height) / 2.0
        top = top < 0.0 ? 0.0 : top
        text.frame.origin = CGPoint(x: text.frame.origin.x, y: top)
    }

    func showFullscreen(container: UIView, table: UICollectionView) {
        margin = 0
        container.insertSubview(self, atIndex: container.subviews.count)
        frame = CGRect(x: container.frame.origin.x,
            y: container.frame.origin.y + ToolbarHeight + StatusBarHeight,
            width: container.frame.width,
            height: container.frame.height - ToolbarHeight - ToolbarHeight - StatusBarHeight) // Don't let our cell overlap either of the toolbars
        title.alpha = 0
        setNeedsLayout()
    }

    func showAt(offsetY: Int, container: UIView, table: UICollectionView) {
        margin = TabTrayControllerUX.Margin
        container.insertSubview(self, atIndex: container.subviews.count)
        frame = CGRect(x: self.frame.origin.x,
            y: self.frame.origin.y,
            width: container.frame.width / 2 - TabTrayControllerUX.Margin * 1.5,
            height: TabTrayControllerUX.CellHeight)
        title.alpha = 1
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let w = frame.width
        let h = frame.height

        backgroundHolder.frame = CGRect(x: margin,
            y: margin,
            width: w,
            height: h)
        background.frame = CGRect(origin: CGPointMake(0, 0), size: backgroundHolder.frame.size)

        title.frame = CGRect(x: 0,
            y: 0,
            width: backgroundHolder.frame.width,
            height: TabTrayControllerUX.TextBoxHeight)

        favicon.frame = CGRect(x: 6, y: (TabTrayControllerUX.TextBoxHeight - 16)/2, width: 16, height: 16)

        let titleTextLeft = favicon.frame.origin.x + favicon.frame.width + 6
        titleText.frame = CGRect(x: titleTextLeft,
            y: 0,
            width: title.frame.width - titleTextLeft - margin,
            height: title.frame.height)

        innerStroke.frame = background.frame

        verticalCenter(titleText)
    }
}

class TabTrayController: UIViewController, UITabBarDelegate, UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    var tabManager: TabManager!
    private let CellIdentifier = "CellIdentifier"
    var collectionView: UICollectionView!
    var profile: Profile!
    var screenshotHelper: ScreenshotHelper!

    var toolbar: UIToolbar!

    override func viewDidLoad() {
        view.isAccessibilityElement = true
        view.accessibilityLabel = NSLocalizedString("Tabs Tray", comment: "Accessibility label for the Tabs Tray view.")

        toolbar = UIToolbar()
        toolbar.backgroundImageForToolbarPosition(.Top, barMetrics: UIBarMetrics.Compact)
        toolbar.frame.origin = CGPoint(x: TabTrayControllerUX.Margin, y: StatusBarHeight)

        toolbar.barTintColor = TabTrayControllerUX.ToolbarBarTintColor
        toolbar.tintColor = UIColor.whiteColor()

        toolbar.layer.shadowColor = UIColor.blackColor().CGColor
        toolbar.layer.shadowOffset = CGSize(width: 0, height: 1.0)
        toolbar.layer.shadowRadius = 2.0
        toolbar.layer.shadowOpacity = 0.25

        let settingsItem = UIBarButtonItem(title: "\u{2699}", style: .Plain, target: self, action: "SELdidClickSettingsItem")
        settingsItem.accessibilityLabel = NSLocalizedString("Settings", comment: "Accessibility label for the Settings button in the Tab Tray.")
        let signinItem = UIBarButtonItem(title: NSLocalizedString("Sign in", comment: "Button that leads to Sign in section of the Settings sheet."),
            style: .Plain, target: self, action: "SELdidClickDone")
        signinItem.enabled = false
        // TODO: Vertically center the add button.  Right now, it's too high in the containing bar.
        let addTabItem = UIBarButtonItem(barButtonSystemItem: .Add, target: self, action: "SELdidClickAddTab")
        let spacer = UIBarButtonItem(barButtonSystemItem: .FlexibleSpace, target: nil, action: nil)
        toolbar.setItems([settingsItem, spacer, signinItem, spacer, addTabItem], animated: true)

        let flowLayout = UICollectionViewFlowLayout()
        collectionView = UICollectionView(frame: view.frame, collectionViewLayout: flowLayout)
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.registerClass(CustomCell.self, forCellWithReuseIdentifier: CellIdentifier)
        collectionView.contentInset = UIEdgeInsets(top: StatusBarHeight + ToolbarHeight, left: 0, bottom: 0, right: 0)
        collectionView.backgroundColor = TabTrayControllerUX.BackgroundColor

        view.addSubview(collectionView)
        view.addSubview(toolbar)

        toolbar.snp_makeConstraints { make in
            make.top.equalTo(self.view)
            make.height.equalTo(StatusBarHeight + ToolbarHeight)
            make.left.right.equalTo(self.view)
            return
        }

        collectionView.snp_makeConstraints { make in
            make.top.equalTo(self.view)
            make.left.right.bottom.equalTo(self.view)
        }
    }

    func SELdidClickDone() {
        presentingViewController!.dismissViewControllerAnimated(true, completion: nil)
    }

    func SELdidClickSettingsItem() {
        let controller = SettingsNavigationController()
        controller.profile = profile
        presentViewController(controller, animated: true, completion: nil)
    }

    func SELdidClickAddTab() {
        tabManager?.addTab()
        presentingViewController!.dismissViewControllerAnimated(true, completion: nil)
    }

    func collectionView(collectionView: UICollectionView, didSelectItemAtIndexPath indexPath: NSIndexPath) {
        let tab = tabManager.getTab(indexPath.item)
        tabManager.selectTab(tab)

        dispatch_async(dispatch_get_main_queue()) { _ in
            self.presentingViewController!.dismissViewControllerAnimated(true, completion: nil)
        }
    }

    func collectionView(collectionView: UICollectionView, cellForItemAtIndexPath indexPath: NSIndexPath) -> UICollectionViewCell {
        let tab = tabManager.getTab(indexPath.item)
        let cell = collectionView.dequeueReusableCellWithReuseIdentifier(CellIdentifier, forIndexPath: indexPath) as CustomCell
        cell.titleText.text = tab.displayTitle
        let screenshotAspectRatio = cell.frame.width / TabTrayControllerUX.CellHeight
        cell.background.image = screenshotHelper.takeScreenshot(tab, aspectRatio: screenshotAspectRatio, quality: 1)
        return cell
    }

    func collectionView(collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return tabManager.count
    }

    func collectionView(collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAtIndex section: Int) -> CGFloat {
        return TabTrayControllerUX.Margin
    }

    func collectionView(collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAtIndexPath indexPath: NSIndexPath) -> CGSize {
        return CGSizeMake(collectionView.bounds.width / 2 - TabTrayControllerUX.Margin * 1.5, TabTrayControllerUX.CellHeight)
    }

    func collectionView(collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAtIndex section: Int) -> UIEdgeInsets {
        return UIEdgeInsetsMake(TabTrayControllerUX.Margin, TabTrayControllerUX.Margin, TabTrayControllerUX.Margin, TabTrayControllerUX.Margin)
    }

}

extension TabTrayController: Transitionable {
    private func getTransitionCell(options: TransitionOptions, browser: Browser?) -> CustomCell {
        var transitionCell: CustomCell
        if let cell = options.moving as? CustomCell {
            transitionCell = cell
        } else {
            transitionCell = CustomCell(frame: options.container!.frame)
//            transitionCell = collectionView.dequeueReusableCellWithReuseIdentifier("id", forIndexPath: NSIndexPath(index: tabManager.selectedIndex)) as CustomCell
            options.moving = transitionCell
        }

        if let browser = browser {
            transitionCell.background.image = screenshotHelper.takeScreenshot(browser, aspectRatio: 0, quality: 1)
        } else {
            transitionCell.background.image = nil
        }
        transitionCell.titleText.text = browser?.displayTitle

        return transitionCell
    }

    func transitionableWillHide(transitionable: Transitionable, options: TransitionOptions) {
        // Create a fake cell that is shown fullscreen
        if let container = options.container {
            let cell = getTransitionCell(options, browser: tabManager.selectedTab)
            // TODO: Smoothly animate the corner radius to 0.
            cell.backgroundHolder.layer.cornerRadius = TabTrayControllerUX.CornerRadius
            cell.showFullscreen(container, table: collectionView)
        }

        // Scroll the toolbar off the top
        toolbar.alpha = 0
//        toolbar.transform = CGAffineTransformMakeTranslation(0, -ToolbarHeight)

        collectionView.backgroundColor = UIColor.clearColor()
    }

    func transitionableWillShow(transitionable: Transitionable, options: TransitionOptions) {
        if let container = options.container {
            // Create a fake cell that is at the selected index
            let cell = getTransitionCell(options, browser: tabManager.selectedTab)
            cell.backgroundHolder.layer.cornerRadius = TabTrayControllerUX.CornerRadius
            cell.showAt(tabManager.selectedIndex, container: container, table: collectionView)
        }

        // Scroll the toolbar on from the top
        toolbar.alpha = 1
        toolbar.transform = CGAffineTransformIdentity

        collectionView.backgroundColor = TabTrayControllerUX.BackgroundColor
    }

    func transitionableWillComplete(transitionable: Transitionable, options: TransitionOptions) {
        if let cell = options.moving {
            cell.removeFromSuperview()
        }
    }
}

// A transparent view with a rectangular border with rounded corners, stroked
// with a semi-transparent white border.
private class InnerStrokedView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = UIColor.clearColor()
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func drawRect(rect: CGRect) {
        let strokeWidth = 1.0 as CGFloat
        let halfWidth = strokeWidth/2 as CGFloat

        let path = UIBezierPath(roundedRect: CGRect(x: halfWidth,
            y: halfWidth,
            width: rect.width - strokeWidth,
            height: rect.height - strokeWidth),
            cornerRadius: TabTrayControllerUX.CornerRadius)

        path.lineWidth = strokeWidth
        UIColor.whiteColor().colorWithAlphaComponent(0.2).setStroke()
        path.stroke()
    }
}
