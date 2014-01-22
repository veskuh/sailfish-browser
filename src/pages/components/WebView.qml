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

WebContainer {
    id: webContainer

    // This cannot be bindings in multiple mozview case. Will change in
    // later commits.
    property bool active
    // This property should cover all possible popus
    property alias popupActive: webView._ctxMenuActive

    property alias loading: webView.loading
    property int loadProgress
    property alias contentItem: webView
    property TabModel tabModel
    property alias currentTab: tab
    readonly property bool fullscreenMode: (webView.chromeGestureEnabled && !webView.chrome) || webContainer.inputPanelVisible || !webContainer.foreground
    property alias canGoBack: tab.canGoBack
    property alias canGoForward: tab.canGoForward

    readonly property alias url: tab.url
    readonly property alias title: tab.title
    property string favicon

    // Groupped properties
    property alias popups: webPopus
    property alias prompts: webPrompts

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
        webView.stop()
    }

    function load(url, title, force) {
        if (url.substring(0, 6) !== "about:" && url.substring(0, 5) !== "file:"
            && !connectionHelper.haveNetworkConnectivity()
            && !webView._deferredLoad) {

            webView._deferredReload = false
            webView._deferredLoad = {
                "url": url,
                "title": title
            }
            connectionHelper.attemptToConnectNetwork()
            return
        }

        if (tabModel.count == 0) {
            tab.newTabRequested = true
            tabModel.addTab(url, title)
        }

        // Bookmarks and history items pass url and title as arguments.
        if (title) {
            tab.title = title
        } else {
            tab.title = ""
        }

        // Always enable chrome when load is called.
        webView.chrome = true

        if ((url !== "" && webView.url != url) || force) {
            tab.url = url
            resourceController.firstFrameRendered = false
            webView.load(url)
        }
    }

    function reload() {
        var url = tab.url

        if (url.substring(0, 6) !== "about:" && url.substring(0, 5) !== "file:"
            && !webView._deferredReload
            && !connectionHelper.haveNetworkConnectivity()) {

            webView._deferredReload = true
            webView._deferredLoad = null
            connectionHelper.attemptToConnectNetwork()
            return
        }

        webView.reload()
    }

    function suspend() {
        webView.suspendView()
    }

    function resume() {
        webView.resumeView()
    }

    function sendAsyncMessage(name, data) {
        webView.sendAsyncMessage(name, data)
    }

    function captureScreen() {
        if (active && resourceController.firstFrameRendered) {
            var size = Screen.width
            if (browserPage.isLandscape && !webContainer.fullscreenMode) {
                size -= toolbarRow.height
            }

            tab.captureScreen(webView.url, 0, 0, size, size, browserPage.rotation)
        }
    }

    // Temporary functions / properties, remove once all functions have been moved
    property alias chrome: webView.chrome
    property alias resourceController: resourceController
    property alias connectionHelper: connectionHelper

    width: parent.width
    height: browserPage.orientation === Orientation.Portrait ? Screen.height : Screen.width

    pageActive: active
    webView: webView

    foreground: Qt.application.active
    inputPanelHeight: window.pageStack.panelSize
    inputPanelOpenHeight: window.pageStack.imSize
    toolbarHeight: toolBarContainer.height

    Rectangle {
        id: background
        anchors.fill: parent
        color: webView.bgcolor ? webView.bgcolor : "white"
    }

    Tab {
        id: tab

        // Used by newTab function
        property bool newTabRequested

        // Indicates whether the next url that is set to this Tab element will be loaded.
        // Used when new tabs are created, tabs are loaded, and with back and forward,
        // All of these actions load data asynchronously from the DB, and the changes
        // are reflected in the Tab element.
        property bool loadWhenTabChanges: false
        property bool backForwardNavigation: false

        onUrlChanged: {
            if (tab.valid && (loadWhenTabChanges || backForwardNavigation)) {
                // Both url and title are updated before url changed is emitted.
                load(url, title)
                // loadWhenTabChanges will be set to false when mozview says that url has changed
                // loadWhenTabChanges = false
            }
        }
    }

    QmlMozView {
        id: webView

        readonly property bool loaded: loadProgress === 100
        readonly property bool readyToLoad: viewReady && tabModel.loaded
        property bool userHasDraggedWhileLoading
        property bool viewReady

        property Item _contextMenu
        property bool _ctxMenuActive: _contextMenu != null && _contextMenu.active

        // As QML can't disconnect closure from a signal (but methods only)
        // let's keep auth data in this auxilary attribute whose sole purpose is to
        // pass arguments to openAuthDialog().
        property var _authData: null

        property bool _deferredReload
        property var _deferredLoad: null

        function openAuthDialog(input) {
            var data = input !== undefined ? input : webView._authData
            var winid = data.winid

            if (webView._authData !== null) {
                auxTimer.triggered.disconnect(webView.openAuthDialog)
                webView._authData = null
            }

            var dialog = pageStack.push(webPopus.authenticationComponentUrl,
                                        {
                                            "hostname": data.text,
                                            "realm": data.title,
                                            "username": data.defaultValue,
                                            "passwordOnly": data.passwordOnly
                                        })
            dialog.accepted.connect(function () {
                webView.sendAsyncMessage("authresponse",
                                         {
                                             "winid": winid,
                                             "accepted": true,
                                             "username": dialog.username,
                                             "password": dialog.password
                                         })
            })
            dialog.rejected.connect(function() {
                webView.sendAsyncMessage("authresponse",
                                         {"winid": winid, "accepted": false})
            })
        }

        function openContextMenu(linkHref, imageSrc, linkTitle, contentType) {
            var ctxMenuComp

            if (_contextMenu) {
                _contextMenu.linkHref = linkHref
                _contextMenu.linkTitle = linkTitle.trim()
                _contextMenu.imageSrc = imageSrc
                hideVirtualKeyboard()
                _contextMenu.show()
            } else {
                ctxMenuComp = Qt.createComponent(webPopus.contextMenuComponentUrl)
                if (ctxMenuComp.status !== Component.Error) {
                    _contextMenu = ctxMenuComp.createObject(browserPage,
                                                            {
                                                                "linkHref": linkHref,
                                                                "imageSrc": imageSrc,
                                                                "linkTitle": linkTitle.trim(),
                                                                "contentType": contentType,
                                                                "viewId": webView.uniqueID()
                                                            })
                    hideVirtualKeyboard()
                    _contextMenu.show()
                } else {
                    console.log("Can't load BrowserContextMenu.qml")
                }
            }
        }

        function hideVirtualKeyboard() {
            if (Qt.inputMethod.visible) {
                webContainer.parent.focus = true
            }
        }

        visible: WebUtils.firstUseDone

        enabled: parent.active
        // There needs to be enough content for enabling chrome gesture
        chromeGestureThreshold: toolBarContainer.height
        chromeGestureEnabled: contentHeight > webContainer.height + chromeGestureThreshold

        signal selectionRangeUpdated(variant data)
        signal selectionCopied(variant data)
        signal contextMenuRequested(variant data)

        focus: true
        width: browserPage.width
        state: ""

        onReadyToLoadChanged: {
            if (!WebUtils.firstUseDone) {
                return
            }

            if (WebUtils.initialPage !== "") {
                browserPage.load(WebUtils.initialPage)
            } else if (tabModel.count > 0) {
                // First tab is actived when tabs are loaded to the tabs model.
                webContainer.load(tab.url, tab.title)
            } else {
                webContainer.load(WebUtils.homePage, "")
            }
        }

        onLoadProgressChanged: {
            if (loadProgress > webContainer.loadProgress) {
                webContainer.loadProgress = loadProgress
            }
        }

        onTitleChanged: tab.title = title
        onUrlChanged: {
            if (!resourceController.isRejectedGeolocationUrl(url)) {
                resourceController.rejectedGeolocationUrl = ""
            }

            if (!resourceController.isAcceptedGeolocationUrl(url)) {
                resourceController.acceptedGeolocationUrl = ""
            }

            // TODO: This if-else-block needs to be checked carefully.
            if (tab.backForwardNavigation) {
                tab.updateTab(tab.url, tab.title)
                tab.backForwardNavigation = false
            } else if (!tab.newTabRequested) {
                // Tab has currently always good title.
                // TODO: Could we add linkClicked to QmlMozView to help this?
                tab.navigateTo(webView.url)
            } else {
                tab.url = url
            }

            tab.loadWhenTabChanges = false
            tab.newTabRequested = false
        }

        onBgcolorChanged: {
            var bgLightness = WebUtils.getLightness(bgcolor)
            var dimmerLightness = WebUtils.getLightness(Theme.highlightDimmerColor)
            var highBgLightness = WebUtils.getLightness(Theme.highlightBackgroundColor)

            if (Math.abs(bgLightness - dimmerLightness) > Math.abs(bgLightness - highBgLightness)) {
                verticalScrollDecorator.color = Theme.highlightDimmerColor
                horizontalScrollDecorator.color = Theme.highlightDimmerColor
            } else {
                verticalScrollDecorator.color = Theme.highlightBackgroundColor
                horizontalScrollDecorator.color = Theme.highlightBackgroundColor
            }

            sendAsyncMessage("Browser:SelectionColorUpdate",
                             {
                                 "color": Theme.secondaryHighlightColor
                             })
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
                    webContainer.resetHeight(false)
                }
            }
        }

        onLoadingChanged: {
            if (loading) {
                userHasDraggedWhileLoading = false
                webContainer.favicon = ""
                webView.chrome = true
                webContainer.resetHeight(false)
            }
        }
        onRecvAsyncMessage: {
            switch (message) {
            case "chrome:linkadded": {
                if (data.rel === "shortcut icon") {
                    webContainer.favicon = data.href
                }
                break
            }
            case "embed:selectasync": {
                var dialog

                dialog = pageStack.push(webPrompts.selectComponentUrl,
                                        {
                                            "options": data.options,
                                            "multiple": data.multiple,
                                            "webview": webView
                                        })
                break;
            }
            case "embed:alert": {
                var winid = data.winid
                var dialog = pageStack.push(webPrompts.alertComponentUrl,
                                            {"text": data.text})
                // TODO: also the Async message must be sent when window gets closed
                dialog.done.connect(function() {
                    sendAsyncMessage("alertresponse", {"winid": winid})
                })
                break
            }
            case "embed:confirm": {
                var winid = data.winid
                var dialog = pageStack.push(webPrompts.confirmComponentUrl,
                                            {"text": data.text})
                // TODO: also the Async message must be sent when window gets closed
                dialog.accepted.connect(function() {
                    sendAsyncMessage("confirmresponse",
                                     {"winid": winid, "accepted": true})
                })
                dialog.rejected.connect(function() {
                    sendAsyncMessage("confirmresponse",
                                     {"winid": winid, "accepted": false})
                })
                break
            }
            case "embed:prompt": {
                var winid = data.winid
                var dialog = pageStack.push(webPrompts.queryComponentUrl,
                                            {"text": data.text, "value": data.defaultValue})
                // TODO: also the Async message must be sent when window gets closed
                dialog.accepted.connect(function() {
                    sendAsyncMessage("promptresponse",
                                     {
                                         "winid": winid,
                                         "accepted": true,
                                         "promptvalue": dialog.value
                                     })
                })
                dialog.rejected.connect(function() {
                    sendAsyncMessage("promptresponse",
                                     {"winid": winid, "accepted": false})
                })
                break
            }
            case "embed:auth": {
                if (pageStack.busy) {
                    // User has just entered wrong credentials and webView wants
                    // user's input again immediately even thogh the accepted
                    // dialog is still deactivating.
                    webView._authData = data
                    // A better solution would be to connect to browserPage.statusChanged,
                    // but QML Page transitions keep corrupting even
                    // after browserPage.status === PageStatus.Active thus auxTimer.
                    auxTimer.triggered.connect(webView.openAuthDialog)
                    auxTimer.start()
                } else {
                    webView.openAuthDialog(data)
                }
                break
            }
            case "embed:permissions": {
                // Ask for location permission
                if (resourceController.isAcceptedGeolocationUrl(webView.url)) {
                    sendAsyncMessage("embedui:premissions", {
                                         allow: true,
                                         checkedDontAsk: false,
                                         id: data.id })
                } else if (resourceController.isRejectedGeolocationUrl(webView.url)) {
                    sendAsyncMessage("embedui:premissions", {
                                         allow: false,
                                         checkedDontAsk: false,
                                         id: data.id })
                } else {
                    var dialog = pageStack.push(webPopus.locationComponentUrl, {})
                    dialog.accepted.connect(function() {
                        sendAsyncMessage("embedui:premissions", {
                                             allow: true,
                                             checkedDontAsk: false,
                                             id: data.id })
                        resourceController.acceptedGeolocationUrl = WebUtils.displayableUrl(webView.url)
                        resourceController.rejectedGeolocationUrl = ""
                    })
                    dialog.rejected.connect(function() {
                        sendAsyncMessage("embedui:premissions", {
                                             allow: false,
                                             checkedDontAsk: false,
                                             id: data.id })
                        resourceController.rejectedGeolocationUrl = WebUtils.displayableUrl(webView.url)
                        resourceController.acceptedGeolocationUrl = ""
                    })
                }
                break
            }
            case "embed:login": {
                pageStack.push(popups.passwordManagerComponentUrl,
                               {
                                   "webView": webView,
                                   "requestId": data.id,
                                   "notificationType": data.name,
                                   "formData": data.formdata
                               })
                break
            }
            case "Content:ContextMenu": {
                webView.contextMenuRequested(data)
                if (data.types.indexOf("image") !== -1 || data.types.indexOf("link") !== -1) {
                    openContextMenu(data.linkURL, data.mediaURL, data.linkTitle, data.contentType)
                }
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

        Rectangle {
            id: verticalScrollDecorator

            width: 5
            height: webView.verticalScrollDecorator.height
            y: webView.verticalScrollDecorator.y
            anchors.right: parent ? parent.right: undefined
            color: Theme.highlightDimmerColor
            smooth: true
            radius: 2.5
            visible: webView.contentHeight > webView.height && !webView.pinching && !webView._ctxMenuActive
            opacity: webView.moving ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { properties: "opacity"; duration: 400 } }
        }

        Rectangle {
            id: horizontalScrollDecorator
            width: webView.horizontalScrollDecorator.width
            height: 5
            x: webView.horizontalScrollDecorator.x
            y: browserPage.height - (fullscreenMode ? 0 : toolBarContainer.height) - height
            color: Theme.highlightDimmerColor
            smooth: true
            radius: 2.5
            visible: webView.contentWidth > webView.width && !webView.pinching && !webView._ctxMenuActive
            opacity: webView.moving ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { properties: "opacity"; duration: 400 } }
        }

        states: State {
            name: "boundHeightControl"
            when: webContainer.inputPanelVisible || !webContainer.foreground
            PropertyChanges {
                target: webView
                height: browserPage.height
            }
        }
    }

    Connections {
        target: tabModel

        onActiveTabChanged: {
            if (webView.loading) {
                webView.stop()
            }

            // When all tabs are closed, we're in invalid state.
            if (tab.valid && webView.readyToLoad) {
                webContainer.load(tab.url, tab.title)
            }
            webContainer.currentTabChanged()
        }

        onAboutToAddTab: {
            // Only for capturing currently active tab before the new
            // gets added. Opening to a new tab from context menu
            // is a case where this is needed. We could stop loading
            // and capture screen before context menu adds the tab (by context menu).
            // However, I'd like to see loading handling happening inside this component.
            // Stopping loading is needed so that we faded status area is not visible
            // in the capture.
            if (webView.loading) {
                webView.stop()
            }
            captureScreen()
        }
    }

    ConnectionHelper {
        id: connectionHelper

        onNetworkConnectivityEstablished: {
            var url
            var title

            if (webView._deferredLoad) {
                url = webView._deferredLoad["url"]
                title = webView._deferredLoad["title"]
                webView._deferredLoad = null

                browserPage.load(url, title, true)
            } else if (webView._deferredReload) {
                webView._deferredReload = false
                webView.reload()
            }
        }

        onNetworkConnectivityUnavailable: {
            webView._deferredLoad = null
            webView._deferredReload = false
        }
    }

    ResourceController {
        id: resourceController
        webView: webContainer
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
        id: webPopus

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
    }

    Component.onDestruction: connectionHelper.closeNetworkSession()
}
