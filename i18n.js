.pragma library

var currentLang = "en";

var translations = {
    "en": {
        "title": "Hypr Input Switcher",
        "subtitle": "Smart input method switcher & rule manager for Hyprland",
        "tab_rules": "📜 Rules",
        "tab_input_methods": "⌨️ Input Methods",
        "installed": "Installed",
        "not_installed": "Not Installed",
        "running": "Running",
        "not_running": "Not Running",
        "start_service": "▶ Start Service",
        "config_ready": "📄 Config Ready ({0} rules)",
        "config_missing": "⚠️ Config Missing",
        "default_im": "Default Input Method:",
        "keep_current": "Keep Current (keep)",
        "keep_version_hint": "(requires CLI >= 0.4.0)",
        "add_rule": "➕ Add Rule",
        "col_index": "#",
        "col_class": "App Class",
        "col_title": "Window Title (Regex)",
        "col_target_im": "Target Input Method",
        "col_actions": "Actions",
        "regex_badge": "REGEX",
        "all_windows": "All (*)",
        "no_rules_hint": "No rules configured. Click 'Add Rule' above to get started.",
        "im_table_title": "Configured input method engines for rule matching",
        "add_im": "➕ Add Input Method",
        "col_im_key": "Key",
        "col_im_name": "Display Name",
        "col_im_engine": "Engine / Schema",
        "edit": "✎ Edit",
        "delete": "🗑 Delete",
        "reload": "🔄 Reload",
        "save_config": "💾 Save Config",
        "saving": "Saving...",
        "save_success": "✓ Configuration saved and applied",
        "save_failed": "✗ Save failed: ",
        "config_synced": "Configuration synced",
        "default_template_loaded": "Default template loaded",
        "rule_dialog_edit": "Edit Rule #{0}",
        "rule_dialog_add": "Add New Rule",
        "rule_class_label": "Window Class (Supports regex, e.g. firefox, code, kitty)",
        "rule_class_placeholder": "e.g. firefox, google-chrome, code...",
        "screen_pick": "🎯 Pick Window",
        "screen_picking_hint": "Click on any target window on your screen...",
        "screen_picked": "Picked window: {0}",
        "screen_pick_cancel": "Window pick cancelled",
        "screen_pick_not_found": "No window found at clicked location",
        "rule_title_label": "Window Title (Optional regex, leave empty to match all)",
        "rule_title_placeholder": "e.g. GitHub, YouTube",
        "rule_target_im_label": "Target Input Method",
        "rule_keep_version_hint": "⚠️ 'keep' rule requires CLI >= 0.4.0 (current: v{0})",
        "cancel": "Cancel",
        "confirm_save": "Confirm Save",
        "class_required": "App Class cannot be empty",
        "im_dialog_edit": "Edit Input Method",
        "im_dialog_add": "Add Input Method",
        "im_key_label": "Key Identifier (e.g. english, chinese, japanese, korean)",
        "im_key_placeholder": "e.g. chinese, english, rime_custom...",
        "im_name_label": "Display Name (e.g. English, 中文, 日本語)",
        "im_name_placeholder": "e.g. 🇨🇳 中文, 🇺🇸 English, 🇯🇵 日本語...",
        "im_engine_label": "Engine (e.g. rime, keyboard-us, mozc)",
        "im_engine_placeholder": "e.g. rime, keyboard-us, mozc...",
        "im_rime_schema_label": "Rime Schema (e.g. rime_frost, jaroomaji, luna_pinyin)",
        "im_rime_schema_placeholder": "e.g. rime_frost, jaroomaji...",
        "im_key_engine_required": "Key and Engine cannot be empty"
    },
    "zh": {
        "title": "Hypr Input Switcher",
        "subtitle": "Hyprland 智能输入法切换与规则配置中心",
        "tab_rules": "📜 规则列表",
        "tab_input_methods": "⌨️ 输入法管理",
        "installed": "已安装",
        "not_installed": "未安装",
        "running": "服务运行中",
        "not_running": "服务未在运行",
        "start_service": "▶ 启动服务",
        "config_ready": "📄 配置文件就绪 ({0} 条规则)",
        "config_missing": "⚠️ 配置文件未生成",
        "default_im": "默认输入法:",
        "keep_current": "保持当前 (keep)",
        "keep_version_hint": "(需 CLI >= 0.4.0)",
        "add_rule": "➕ 添加规则",
        "col_index": "#",
        "col_class": "应用 Class",
        "col_title": "窗口标题 Title (Regex)",
        "col_target_im": "目标输入法",
        "col_actions": "操作",
        "regex_badge": "REGEX",
        "all_windows": "全部 (*)",
        "no_rules_hint": "暂无规则，点击上方「添加规则」开始配置",
        "im_table_title": "已配置的输入法方案（供规则关联匹配）",
        "add_im": "➕ 添加输入法",
        "col_im_key": "标识 (Key)",
        "col_im_name": "显示名称 (Display Name)",
        "col_im_engine": "引擎 / 方案 (Engine)",
        "edit": "✎ 编辑",
        "delete": "🗑 删除",
        "reload": "🔄 重新载入",
        "save_config": "💾 保存配置",
        "saving": "正在保存...",
        "save_success": "✓ 配置已保存并实时生效",
        "save_failed": "✗ 保存失败: ",
        "config_synced": "配置已同步",
        "default_template_loaded": "已载入默认模板",
        "rule_dialog_edit": "编辑规则 #{0}",
        "rule_dialog_add": "添加新规则",
        "rule_class_label": "窗口 Class (支持正则，如 firefox, code, kitty)",
        "rule_class_placeholder": "例如: firefox, google-chrome, code...",
        "screen_pick": "🎯 屏幕点击拾取",
        "screen_picking_hint": "请在屏幕上点击目标窗口...",
        "screen_picked": "已拾取窗口: {0}",
        "screen_pick_cancel": "已取消拾取",
        "screen_pick_not_found": "未在点击位置找到窗口",
        "rule_title_label": "窗口标题 Title (可选，留空则匹配全部窗口)",
        "rule_title_placeholder": "例如: GitHub, YouTube (支持正则)",
        "rule_target_im_label": "目标输入法",
        "rule_keep_version_hint": "⚠️ \"保持 (keep)\" 规则需要 CLI >= 0.4.0 (当前: v{0})",
        "cancel": "取消",
        "confirm_save": "确定保存",
        "class_required": "应用 Class 不能为空",
        "im_dialog_edit": "编辑输入法",
        "im_dialog_add": "添加输入法",
        "im_key_label": "输入法标识 Key (如 english, chinese, japanese, korean)",
        "im_key_placeholder": "例如: chinese, english, rime_custom...",
        "im_name_label": "显示名称 Display Name (如 中文, 🇺🇸 English)",
        "im_name_placeholder": "例如: 🇨🇳 中文, 🇺🇸 English, 🇰🇷 한국어...",
        "im_engine_label": "输入法引擎 Engine (如 rime, keyboard-us, hangul)",
        "im_engine_placeholder": "例如: rime, keyboard-us, mozc...",
        "im_rime_schema_label": "Rime 方案名称 Schema (如 rime_frost, jaroomaji, luna_pinyin)",
        "im_rime_schema_placeholder": "例如: rime_frost, jaroomaji...",
        "im_key_engine_required": "输入法 Key 和引擎名称不能为空"
    }
};

function init(lang) {
    if (lang && lang.toLowerCase().indexOf("zh") !== -1) {
        currentLang = "zh";
    } else {
        currentLang = "en";
    }
}

function setLanguage(lang) {
    if (lang === "zh" || lang === "en") {
        currentLang = lang;
    }
}

function t(key, arg0) {
    var dict = translations[currentLang] || translations["en"];
    var str = dict[key] || (translations["en"] && translations["en"][key]) || key;
    if (arg0 !== undefined) {
        str = str.replace("{0}", arg0);
    }
    return str;
}
