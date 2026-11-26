import QuickLayoutKit
import Testing
import UIKit

@MainActor
struct TabBarTests {
    @Test func tabPagesRetainsSelectedNavigationStackAcrossReordering() {
        let tabs = UITabBarController()
        let home = UIViewController()
        let inbox = UINavigationController(rootViewController: UIViewController())
        let detail = UIViewController()
        let inboxItem = UITabBarItem(tabBarSystemItem: .favorites, tag: 1)
        tabs.tabPages {
            home
            inbox.tabItem(inboxItem)
        }
        tabs.selectedViewController = inbox
        inbox.pushViewController(detail, animated: false)
        tabs.tabPages {
            inbox
            home
        }
        #expect(tabs.viewControllers == [inbox, home])
        #expect(inbox.tabBarItem === inboxItem)
        #expect(tabs.selectedViewController === inbox)
        #expect(inbox.topViewController === detail)
        tabs.tabPages { home }
        #expect(tabs.selectedViewController === home)
        tabs.tabPages {}
        #expect(tabs.viewControllers?.isEmpty != false)
    }

    @Test func standaloneItemsReplaceInDeclarationOrder() {
        let bar = UITabBar()
        let home = UITabBarItem(tabBarSystemItem: .favorites, tag: 1)
        let more = UITabBarItem(tabBarSystemItem: .more, tag: 2)
        for includeMore in [true, false] {
            bar.items {
                for item in [home] { item }
                if includeMore { more }
            }
            #expect(bar.items == (includeMore ? [home, more] : [home]))
        }
        bar.items {}
        #expect(bar.items?.isEmpty != false)
    }

    @available(iOS 18.0, *)
    @Test func nativeTabsKeepGroupChildrenAndSearchTab() {
        let tabs = UITabBarController()
        let inbox = UITab(title: "Inbox", image: nil, identifier: "inbox") { _ in UIViewController() }
        let library = UITabGroup(title: "Library", image: nil, identifier: "library",
                                 children: [inbox]) { _ in UIViewController() }
        let search = UISearchTab { _ in UIViewController() }
        tabs.tabs {
            library
            search
        }
        #expect(tabs.tabs == [library, search])
        #expect(library.children.first === inbox)
        tabs.selectedTab = search
        #expect(tabs.selectedTab === search)
    }
}
