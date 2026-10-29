pragma Singleton

import QtQuick
import Quickshell
import "i18n.js" as I18n

// The plugin's single language source, shared by every surface: the bar widget,
// the control panel, and the Overlay.
//
// i18n.js holds the strings but cannot hold the choice. It is a plain library,
// so nothing in QML can observe a change in it: a surface that read it directly
// would have to be re-evaluated by some unrelated property change, and any
// surface that re-asserted the `LANG` default would silently undo a choice made
// elsewhere. A QML singleton is the one object the surfaces genuinely share, so
// the choice lives here and each surface binds to `code` instead of deriving a
// language of its own. `LANG` stays the default for anyone who never picks one.
QtObject {
    readonly property string envLanguage: {
        var envLang = Quickshell.env("LANG") || "";
        return envLang.toLowerCase().indexOf("zh") !== -1 ? "zh" : "en";
    }

    property string code: Language.envLanguage

    function toggle() {
        Language.code = (Language.code === "zh" ? "en" : "zh");
    }

    // i18n.js is what actually resolves a key to a string, so keep it in step.
    onCodeChanged: I18n.setLanguage(Language.code)
    Component.onCompleted: I18n.setLanguage(Language.code)
}
