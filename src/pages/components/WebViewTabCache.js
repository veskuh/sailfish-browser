/****************************************************************************
**
** Copyright (C) 2014 Jolla Ltd.
** Contact: Raine Makelainen <raine.makelainen@jolla.com>
**
****************************************************************************/
.pragma library
.import "WebPopupHandler.js" as PopupHandler
.import "WebPromptHandler.js" as PromptHandler

var initialized = false

// Private
var _webViewComponent
var _arguments
var _parent
var _promptHandler
var _popupHandler

var _activeWebView
var _tabs = []
var _activeTabs = {}

function init(args, component, container) {
    _arguments = args
    _webViewComponent = component
    _parent = container
    initialized = true
    _tabs.push(_webViewComponent.createObject(_parent, _arguments))
}

function getView(tabId) {
    if (!_webViewComponent) {
        return
    }

    var webView = _activeTabs[tabId]
    if (!webView && _tabs.length > 0) {
        webView = _tabs.shift()
        _activeTabs[tabId] = webView
    } else if (!webView){
        webView = _webViewComponent.createObject(_parent, _arguments)
        _activeTabs[tabId] = webView
    }
    _updateActiveView(webView)
    return webView;
}

function releaseView(tabId) {
    var viewToRelease = _activeTabs[tabId]
    if (viewToRelease) {
        // TODO: about:blank load is not nice. We should actually reset view (clean history etc)
        viewToRelease.load("about:blank")
        _tabs.push(_activeTabs[tabId])
        delete _activeTabs[tabId]
        // TODO: There should be connection to loaded signal and suspend over here.
        // Didn't get that working yet. One option is that releaseView would just
        // delete view from _activaTabs and destroy() it.
        // viewToRelease.suspendView()
    }
}

function _updateActiveView(webView) {
    if (_activeWebView) {
        _activeWebView.visible = false
        if (_activeWebView.loading) {
            _activeWebView.stop()
        }
        _activeWebView.suspendView()
    }
    _activeWebView = webView
    _activeWebView.resumeView()
    _activeWebView.visible = true
    PopupHandler.activeWebView = _activeWebView
    PromptHandler.activeWebView = _activeWebView
}
