/****************************************************************************
**
** Copyright (C) 2014 Jolla Ltd.
** Contact: Raine Makelainen <raine.makelainen@jolla.com>
**
****************************************************************************/

import QtQuick 2.1
import Sailfish.Silica 1.0
import Sailfish.Browser 1.0
import Qt5Mozilla 1.0
import org.nemomobile.connectivity 1.0
import "WebViewTabCache.js" as TabCache
import "WebPopupHandler.js" as PopupHandler
import "WebPromptHandler.js" as PromptHandler

WebContainer {
    id: webContainer

    // This cannot be bindings in multiple mozview case. Will change in
    // later commits.
    property bool active
    // This property should cover all possible popus
    property alias popupActive: webPopups.active

    property bool loading
    property int loadProgress
    property Item contentItem
    property TabModel tabModel
    property alias currentTab: tab
    readonly property bool fullscreenMode: (contentItem && contentItem.chromeGestureEnabled && !contentItem.chrome) || webContainer.inputPanelVisible || !webContainer.foreground
    property alias canGoBack: tab.canGoBack
    property alias canGoForward: tab.canGoForward

    readonly property alias url: tab.url
    readonly property alias title: tab.title
    property string favicon

    // Groupped properties
    property alias popups: webPopups
    property alias prompts: webPrompts

    // Move to C++
    readonly property bool _readyToLoad: contentItem &&
                                         contentItem.viewReady &&
                                         tabModel.loaded
    property color _decoratorColor: Theme.highlightDimmerColor

    function goBack() {
        tab.backForwardNavigation = true
        tab.goBack()
    }

    function goForward() {
        // This backForwardNavigation is internal of WebView
        tab.backForwardNavigation = true
        tab.goForward()
    }

    function stop() {
        if (contentItem) {
            contentItem.stop()
        }
    }

    function load(url, title, force) {
        if (url.substring(0, 6) !== "about:" && url.substring(0, 5) !== "file:"
            && !connectionHelper.haveNetworkConnectivity()
            && !contentItem._deferredLoad) {

            contentItem._deferredReload = false
            contentItem._deferredLoad = {
                "url": url,
                "title": title
            }
            connectionHelper.attemptToConnectNetwork()
            return
        }

        // This guarantees at that least one webview exists.
        if (tabModel.count == 0) {
            tabModel.addTab(url, title)
        } else {
            // Bookmarks and history items pass url and title as arguments.
            if (title) {
                tab.title = title
            } else {
                tab.title = ""
            }

            // Always enable chrome when load is called.
            contentItem.chrome = true

            if ((url !== "" && contentItem.url != url) || force) {
                tab.url = url
                resourceController.firstFrameRendered = false
                contentItem.load(url)
            }
        }
    }

    function reload() {
        if (!contentItem) {
            return
        }

        var url = tab.url

        if (url.substring(0, 6) !== "about:" && url.substring(0, 5) !== "file:"
            && !contentItem._deferredReload
            && !connectionHelper.haveNetworkConnectivity()) {

            contentItem._deferredReload = true
            contentItem._deferredLoad = null
            connectionHelper.attemptToConnectNetwork()
            return
        }

        contentItem.reload()
    }

    function sendAsyncMessage(name, data) {
        if (!contentItem) {
            return
        }

        contentItem.sendAsyncMessage(name, data)
    }

    function captureScreen() {
        if (!contentItem) {
            return
        }

        if (active && resourceController.firstFrameRendered) {
            var size = Screen.width
            if (browserPage.isLandscape && !webContainer.fullscreenMode) {
                size -= toolbarRow.height
            }

            tab.captureScreen(contentItem.url, 0, 0, size, size, browserPage.rotation)
        }
    }

    width: parent.width
    height: browserPage.orientation === Orientation.Portrait ? Screen.height : Screen.width

    // TODO: Rename pageActive to active and remove there the beginning
    pageActive: active
    webView: contentItem

    foreground: Qt.application.active
    inputPanelHeight: window.pageStack.panelSize
    inputPanelOpenHeight: window.pageStack.imSize
    toolbarHeight: toolBarContainer.height

    onTabModelChanged: PopupHandler.tabModel = tabModel

    on_ReadyToLoadChanged: {
        if (_readyToLoad) {
            if (!WebUtils.firstUseDone) {
                return
            }

            if (WebUtils.initialPage !== "") {
                webContainer.load(WebUtils.initialPage)
            } else if (tabModel.count > 0) {
                // First tab is actived when tabs are loaded to the tabs model.
                webContainer.load(tab.url, tab.title)
            } else {
                webContainer.load(WebUtils.homePage, "")
            }
        }
    }

    Rectangle {
        id: background
        anchors.fill: parent
        color: contentItem && contentItem.bgcolor ? contentItem.bgcolor : "white"
    }

    Tab {
        id: tab

        // Used with back and forward navigation.
        // All of these actions load data asynchronously from the DB, and the changes
        // are reflected in the Tab element.
        property bool backForwardNavigation: false

        onUrlChanged: {
            if (tab.valid && backForwardNavigation && url != "about:blank") {
                // Both url and title are updated before url changed is emitted.
                load(url, title)
            }
        }
    }

    Component {
        id: webViewComponent
        QmlMozView {
            id: webView

            property Item container
            property Item tab
            readonly property bool loaded: loadProgress === 100
            property bool userHasDraggedWhileLoading
            property bool viewReady

            property bool _deferredReload
            property var _deferredLoad: null

            visible: WebUtils.firstUseDone
            enabled: container.active
            // There needs to be enough content for enabling chrome gesture
            chromeGestureThreshold: container.toolbarHeight
            chromeGestureEnabled: contentHeight > container.height + chromeGestureThreshold

            signal selectionRangeUpdated(variant data)
            signal selectionCopied(variant data)
            signal contextMenuRequested(variant data)

            focus: true
            width: container.parent.width
            state: ""

            onLoadProgressChanged: {
                if (loadProgress > container.loadProgress) {
                    container.loadProgress = loadProgress
                }
            }

            onTitleChanged: tab.title = title
            onUrlChanged: {
                if (url == "about:blank") return

                if (!PopupHandler.isRejectedGeolocationUrl(url)) {
                    PopupHandler.rejectedGeolocationUrl = ""
                }

                if (!PopupHandler.isAcceptedGeolocationUrl(url)) {
                    PopupHandler.acceptedGeolocationUrl = ""
                }

                // TODO: This if-else-block needs to be checked carefully.
                if (tab.backForwardNavigation) {
                    tab.updateTab(tab.url, tab.title)
                    tab.backForwardNavigation = false
                } else {
                    // TODO: Could we add linkClicked to QmlMozView to help this?
                    tab.navigateTo(webView.url)
                }
            }

            onBgcolorChanged: {
                // Update only webView
                if (container.contentItem === webView) {
                    var bgLightness = WebUtils.getLightness(bgcolor)
                    var dimmerLightness = WebUtils.getLightness(Theme.highlightDimmerColor)
                    var highBgLightness = WebUtils.getLightness(Theme.highlightBackgroundColor)

                    if (Math.abs(bgLightness - dimmerLightness) > Math.abs(bgLightness - highBgLightness)) {
                        container._decoratorColor = Theme.highlightDimmerColor
                    } else {
                        container._decoratorColor =  Theme.highlightBackgroundColor
                    }

                    sendAsyncMessage("Browser:SelectionColorUpdate",
                                     {
                                         "color": Theme.secondaryHighlightColor
                                     })
                }
            }

            onViewInitialized: {
                addMessageListener("chrome:linkadded")
                addMessageListener("embed:alert")
                addMessageListener("embed:confirm")
                addMessageListener("embed:prompt")
                addMessageListener("embed:auth")
                addMessageListener("embed:login")
                addMessageListener("embed:permissions")
                addMessageListener("Content:ContextMenu")
                addMessageListener("Content:SelectionRange");
                addMessageListener("Content:SelectionCopied");
                addMessageListener("embed:selectasync")
                addMessageListener("embed:filepicker")

                loadFrameScript("chrome://embedlite/content/SelectAsyncHelper.js")
                loadFrameScript("chrome://embedlite/content/embedhelper.js")

                viewReady = true
            }

            onDraggingChanged: {
                if (dragging && loading) {
                    userHasDraggedWhileLoading = true
                }
            }

            onLoadedChanged: {
                if (loaded) {
                    // This looks redundant after udpate3 TabModel changes.
                    if (url != "about:blank" && url) {
                        // This is always up-to-date in both link clicked and back/forward navigation
                        // captureScreen does not work here as we might have changed to TabPage.
                        // Tab icon clicked takes care of the rest.
                        tab.updateTab(tab.url, tab.title)
                    }

                    if (!userHasDraggedWhileLoading) {
                        container.resetHeight(false)
                    }
                }
            }

            onLoadingChanged: {
                container.loading = loading
                if (loading) {
                    userHasDraggedWhileLoading = false
                    container.favicon = ""
                    webView.chrome = true
                    container.resetHeight(false)
                }
            }
            onRecvAsyncMessage: {
                switch (message) {
                case "chrome:linkadded": {
                    if (data.rel === "shortcut icon") {
                        container.favicon = data.href
                    }
                    break
                }
                case "embed:filepicker": {
                    PromptHandler.openFilePicker(data)
                    break
                }
                case "embed:selectasync": {
                    PopupHandler.openSelectDialog(data)
                    break;
                }
                case "embed:alert": {
                    PromptHandler.openAlert(data)
                    break
                }
                case "embed:confirm": {
                    PromptHandler.openConfirm(data)
                    break
                }
                case "embed:prompt": {
                    PromptHandler.openPrompt(data)
                    break
                }
                case "embed:auth": {
                    PopupHandler.openAuthDialog(data)
                    break
                }
                case "embed:permissions": {
                    PopupHandler.openLocationDialog(data)
                    break
                }
                case "embed:login": {
                    PopupHandler.openPasswordManagerDialog(data)
                    break
                }
                case "Content:ContextMenu": {
                    PopupHandler.openContextMenu(data)
                    break
                }
                case "Content:SelectionRange": {
                    webView.selectionRangeUpdated(data)
                    break
                }
                }
            }
            onRecvSyncMessage: {
                // sender expects that this handler will update `response` argument
                switch (message) {
                case "Content:SelectionCopied": {
                    webView.selectionCopied(data)

                    if (data.succeeded) {
                        //% "Copied to clipboard"
                        notification.show(qsTrId("sailfish_browser-la-selection_copied"))
                    }
                    break
                }
                }
            }

            // We decided to disable "text selection" until we understand how it
            // should look like in Sailfish.
            // TextSelectionController {}
            states: State {
                name: "boundHeightControl"
                when: container.inputPanelVisible || !container.foreground
                PropertyChanges {
                    target: webView
                    height: container.parent.height
                }
            }
        }
    }

    Rectangle {
        id: verticalScrollDecorator

        width: 5
        height: contentItem.verticalScrollDecorator.height
        y: contentItem.verticalScrollDecorator.y
        z: 1
        anchors.right: contentItem.right
        color: _decoratorColor
        smooth: true
        radius: 2.5
        visible: contentItem.contentHeight > contentItem.height && !contentItem.pinching && !webPopups.active
        opacity: contentItem.moving ? 1.0 : 0.0

        Behavior on opacity { NumberAnimation { properties: "opacity"; duration: 400 } }
    }

    Rectangle {
        id: horizontalScrollDecorator

        // TODO: Add notify for horizontalScrollDecorator and verticalScrollDecorator
        width: contentItem.horizontalScrollDecorator.width
        height: 5
        x: contentItem.horizontalScrollDecorator.x
        y: webContainer.parent.height - (fullscreenMode ? 0 : webContainer.toolbarHeight) - height
        z: 1
        color: _decoratorColor
        smooth: true
        radius: 2.5
        visible: contentItem.contentWidth > contentItem.width && !contentItem.pinching && !webPopups.active
        opacity: contentItem.moving ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { properties: "opacity"; duration: 400 } }
    }

    Connections {
        target: tabModel

        // arguments of the signal handler: int tabId
        onActiveTabChanged: {
            if (!TabCache.initialized) {
                TabCache.init({"tab": tab, "container": webContainer},
                              webViewComponent, webContainer)
            }

            if (tabId > 0) {
                webContainer.contentItem = TabCache.getView(tabId)
            }

            // When all tabs are closed, we're in invalid state.
            if (tab.valid && webContainer._readyToLoad) {
                webContainer.load(tab.url, tab.title)
            }
            webContainer.currentTabChanged()
        }

        // arguments of the signal handler: int tabId
        onTabClosed: TabCache.releaseView(tabId)

        onAboutToAddTab: {
            // Only for capturing currently active tab before the new
            // gets added. Opening to a new tab from context menu
            // is a case where this is needed. We could stop loading
            // and capture screen before context menu adds the tab (by context menu).
            // However, I'd like to see loading handling happening inside this component.
            // Stopping loading is needed so that we faded status area is not visible
            // in the capture.
            if (contentItem && contentItem.loading) {
                contentItem.stop()
            }
            captureScreen()
        }
    }

    ConnectionHelper {
        id: connectionHelper

        onNetworkConnectivityEstablished: {
            var url
            var title

            // TODO: this should be deferred till view created.
            if (contentItem && contentItem._deferredLoad) {
                url = contentItem._deferredLoad["url"]
                title = contentItem._deferredLoad["title"]
                contentItem._deferredLoad = null

                webContainer.load(url, title, true)
            } else if (contentItem && contentItem._deferredReload) {
                contentItem._deferredReload = false
                contentItem.reload()
            }
        }

        onNetworkConnectivityUnavailable: {
            if (contentItem) {
                contentItem._deferredLoad = null
                contentItem._deferredReload = false
            }
        }
    }

    ResourceController {
        id: resourceController
        webView: contentItem
        background: webContainer.background

        onWebViewSuspended: connectionHelper.closeNetworkSession()
        onFirstFrameRenderedChanged: {
            if (firstFrameRendered) {
                captureScreen()
            }
        }
    }

    Timer {
        id: auxTimer

        interval: 1000
    }

    QtObject {
        id: webPopups

        property bool active

        // See Silica PR: https://bitbucket.org/jolla/ui-sailfish-silica/pull-request/616
        // url support is missing and these should be typed as urls.
        // We don't want to create component before it's needed.
        property string authenticationComponentUrl
        property string passwordManagerComponentUrl
        property string contextMenuComponentUrl
        property string selectComponentUrl
        property string locationComponentUrl
    }

    QtObject {
        id: webPrompts

        property string alertComponentUrl
        property string confirmComponentUrl
        property string queryComponentUrl
        property string uploadFilePickerComponentUrl
    }

    Component.onDestruction: connectionHelper.closeNetworkSession()
    Component.onCompleted: {
        PopupHandler.auxTimer = auxTimer
        PopupHandler.pageStack = pageStack
        PopupHandler.popups = webPopups
        PopupHandler.componentParent = browserPage
        PopupHandler.resourceController = resourceController
        PopupHandler.WebUtils = WebUtils
        PopupHandler.tabModel = tabModel

        PromptHandler.pageStack = pageStack
        PromptHandler.prompts = webPrompts
    }
}
