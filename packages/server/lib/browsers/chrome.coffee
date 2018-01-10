_         = require("lodash")
os        = require("os")
fs        = require("fs-extra")
Promise   = require("bluebird")
extension = require("@packages/extension")
debug     = require("debug")("cypress:server:browsers")
plugins   = require("../plugins")
appData   = require("../util/app_data")
utils     = require("./utils")

fs = Promise.promisifyAll(fs)

LOAD_EXTENSION = "--load-extension="

pathToExtension = extension.getPathToExtension()
pathToTheme     = extension.getPathToTheme()

defaultArgs = [
  "--test-type"
  "--ignore-certificate-errors"
  "--start-maximized"
  "--silent-debugger-extension-api"
  "--no-default-browser-check"
  "--no-first-run"
  "--noerrdialogs"
  "--enable-fixed-layout"
  "--disable-popup-blocking"
  "--disable-password-generation"
  "--disable-save-password-bubble"
  "--disable-single-click-autofill"
  "--disable-prompt-on-repos"
  "--disable-background-timer-throttling"
  "--disable-renderer-backgrounding"
  "--disable-renderer-throttling"
  "--disable-restore-session-state"
  "--disable-translate"
  "--disable-new-profile-management"
  "--disable-new-avatar-menu"
  "--allow-insecure-localhost"
  "--reduce-security-for-testing"
  "--enable-automation"
  "--disable-infobars"

  ## needed for https://github.com/cypress-io/cypress/issues/573
  ## list of flags here: https://cs.chromium.org/chromium/src/third_party/WebKit/Source/platform/runtime_enabled_features.json5
  "--disable-blink-features=BlockCredentialedSubresources"

  ## the following come frome chromedriver
  ## https://code.google.com/p/chromium/codesearch#chromium/src/chrome/test/chromedriver/chrome_launcher.cc&sq=package:chromium&l=70
  "--metrics-recording-only"
  "--disable-prompt-on-repost"
  "--disable-hang-monitor"
  "--disable-sync"
  "--disable-background-networking"
  "--disable-web-resources"
  "--safebrowsing-disable-auto-update"
  "--safebrowsing-disable-download-protection"
  "--disable-client-side-phishing-detection"
  "--disable-component-update"
  "--disable-default-apps"
]

_normalizeArgExtensions = (dest, args) ->
  loadExtension = _.find args, (arg) ->
    arg.includes(LOAD_EXTENSION)

  if loadExtension
    args = _.without(args, loadExtension)

    ## form into array, enabling users to pass multiple extensions
    userExtensions = loadExtension.replace(LOAD_EXTENSION, "").split(",")

  extensions = [].concat(userExtensions, dest, pathToTheme)

  args.push(LOAD_EXTENSION + _.compact(extensions).join(","))

  args

module.exports = {
  _normalizeArgExtensions

  _writeExtension: (proxyUrl, socketIoRoute) ->
    ## get the string bytes for the final extension file
    extension.setHostAndPath(proxyUrl, socketIoRoute)
    .then (str) ->
      extensionDest = appData.path("extensions", "chrome")
      extensionBg   = appData.path("extensions", "chrome", "background.js")

      ## copy the extension src to the extension dist
      utils.copyExtension(pathToExtension, extensionDest)
      .then ->
        ## and overwrite background.js with the final string bytes
        fs.writeFileAsync(extensionBg, str)
      .return(extensionDest)

  _getArgs: (options = {}) ->
    args = [].concat(defaultArgs)

    if os.platform() is "linux"
      args.push("--disable-gpu")
      args.push("--no-sandbox")

    if ua = options.userAgent
      args.push("--user-agent=#{ua}")

    if ps = options.proxyServer
      args.push("--proxy-server=#{ps}")

    if options.chromeWebSecurity is false
      args.push("--disable-web-security")
      args.push("--allow-running-insecure-content")

    args

  open: (browserName, url, options = {}, automation) ->
    args = @_getArgs(options)

    Promise
    .try ->
      ## bail if we're not registered to this event
      return if not plugins.has("before:browser:launch")

      plugins.execute("before:browser:launch", options.browser, args)
      .then (newArgs) ->
        debug("got user args for 'before:browser:launch'", newArgs)

        ## reset args if we got 'em
        if newArgs
          args = newArgs
    .then =>
      Promise.all([
        ## ensure that we have a chrome profile dir
        utils.ensureProfile(browserName)

        @_writeExtension(options.proxyUrl, options.socketIoRoute)
      ])
    .spread (dir, dest) ->
      ## normalize the --load-extensions argument by
      ## massaging what the user passed into our own
      args = _normalizeArgExtensions(dest, args)

      ## this overrides any previous user-data-dir args
      ## by being the last one
      args.push("--user-data-dir=#{dir}")

      debug("launch in chrome: %s, %s", url, args)

      utils.launch(browserName, url, args)
}