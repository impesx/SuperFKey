#Requires AutoHotkey v2.0
#SingleInstance Force
#MaxThreads 255  ; 增加最大线程数以提高响应性
Persistent  ; 确保脚本持续运行

; 记录最后一次按键时间
global lastKeyPressTime := 0

; 设置自动重启定时器（30分钟）
SetTimer AutoRestart, 1800000  ; 1800000毫秒 = 30分钟

; 自动重启函数
AutoRestart() {
    try {
        ; 检查距离最后一次按键是否超过3秒
        if (A_TickCount - lastKeyPressTime < 3000) {
            ; 如果在3秒内有按键，延迟5秒后重试
            SetTimer AutoRestart, -5000
            return
        }
        
        ; 保存设置
        SaveSettings()
        ; 直接重启，无需通知
        RestartApp()
    } catch as err {
        ; 如果自动重启失败，静默继续运行
        SetTimer AutoRestart, 1800000  ; 重新设置定时器
    }
}

; 设置托盘图标
iconPath := A_Temp "\my.ico"
if !FileExist(iconPath) {
    try {
        FileInstall "my.ico", iconPath, 1
    } catch as err {
        MsgBox "图标加载失败，将使用默认图标。", "警告"
        iconPath := "shell32.dll"
    }
}
try {
    TraySetIcon iconPath
} catch {
    TraySetIcon "shell32.dll", 138
}

; 初始化变量
global fKeyPressed := false  ; 记录f键是否被按下
global lastFKeyPressTime := 0  ; 记录f键按下的时间
global preventNormalKey := false  ; 防止普通键重复触发
global pendingF := false  ; 是否有待处理的f键输入
global fRepeatTimer := 0  ; f键重复定时器
global comboKeyPressed := ""  ; 记录当前按下的组合键
global comboKeyPhysicallyPressed := false  ; 记录组合键是否物理按下
global comboDetectionDelay := 100  ; 组合键检测延迟（毫秒）
global autoStartEnabled := false  ; 开机自启动状态

; 组合键配置
global comboKeyConfigs := Map(
    "j", Map("name", "退格键", "key", "{Backspace}", "enabled", true),
    "k", Map("name", "左箭头", "key", "{Left}", "enabled", true),
    "l", Map("name", "右箭头", "key", "{Right}", "enabled", true),
    "i", Map("name", "等号", "key", "=", "enabled", true),
    "h", Map("name", "Ctrl+退格键/Esc", "key", "^{Backspace}", "enabled", true, "altKey", "{Esc}", "mode", 2),  ; mode: 0=禁用, 1=Ctrl+Backspace, 2=Esc
    "SC027", Map("name", "删除键", "key", "{Delete}", "enabled", true),
    "m", Map("name", "回车", "key", "{Enter}", "enabled", true),
    "n", Map("name", "Ctrl+回车", "key", "^{Enter}", "enabled", true)
)

; 检查开机自启动状态
CheckAutoStartStatus() {
    shortcutPath := A_Startup "\SuperFKey.lnk"
    return FileExist(shortcutPath) ? true : false
}

; 设置开机自启动
SetAutoStart(enable := true) {
    shortcutPath := A_Startup "\SuperFKey.lnk"
    try {
        if (enable) {
            if !FileExist(shortcutPath) {
                FileCreateShortcut A_ScriptFullPath, shortcutPath
            }
        } else {
            if FileExist(shortcutPath) {
                FileDelete shortcutPath
            }
        }
        return true
    } catch as e {
        MsgBox Format("无法{}开机自启动：{}", enable ? "设置" : "关闭", e.Message), "错误"
        return false
    }
}

; 从配置文件读取设置
LoadSettings() {
    global comboDetectionDelay, comboKeyConfigs, autoStartEnabled
    try {
        if FileExist("SuperFKey.ini") {
            comboDetectionDelay := Integer(IniRead("SuperFKey.ini", "Settings", "ComboDelay", "100"))
            
            ; 读取每个组合键的启用状态
            for key, config in comboKeyConfigs {
                try {
                    if (key = "h") {
                        ; 特殊处理f+h的模式
                        config["mode"] := Integer(IniRead("SuperFKey.ini", "ComboKeys", key "_mode", "1"))
                        config["enabled"] := config["mode"] > 0
                    } else {
                        config["enabled"] := Integer(IniRead("SuperFKey.ini", "ComboKeys", key, "1")) = 1
                    }
                }
            }
        }
    }
    ; 检查实际的自启动状态
    autoStartEnabled := CheckAutoStartStatus()
}

; 保存设置到配置文件
SaveSettings() {
    global comboDetectionDelay, comboKeyConfigs
    try {
        IniWrite(comboDetectionDelay, "SuperFKey.ini", "Settings", "ComboDelay")
        
        ; 保存每个组合键的启用状态
        for key, config in comboKeyConfigs {
            if (key = "h") {
                ; 特殊处理f+h的模式
                IniWrite(config["mode"], "SuperFKey.ini", "ComboKeys", key "_mode")
            } else {
                IniWrite(config["enabled"] ? "1" : "0", "SuperFKey.ini", "ComboKeys", key)
            }
        }
    }
}

; 获取当前可用的组合键列表
GetActiveComboKeys() {
    activeComboKeys := Map()
    for key, config in comboKeyConfigs {
        if config["enabled"] {
            if (key = "h" && config["mode"] = 2) {
                activeComboKeys[key] := config["altKey"]
            } else {
                activeComboKeys[key] := config["key"]
            }
        }
    }
    return activeComboKeys
}

; 创建组合键列表（动态）
global comboKeys := GetActiveComboKeys()

; 创建特殊键映射
global specialKeys := Map(
    "Space", " ",
    "SC027", ";",
    ",", ",",
    ".", ".",
    "/", "/",
    "[", "[",
    "]", "]",
    "-", "-",
    "=", "=",
    "'", "'",
    "\", "\",
    "1", "1",
    "2", "2",
    "3", "3",
    "4", "4",
    "5", "5",
    "6", "6",
    "7", "7",
    "8", "8",
    "9", "9",
    "0", "0"
)

; 重启函数
RestartApp(*) {
    ; 保存当前设置
    SaveSettings()
    
    ; 重启脚本
    try {
        Run '"' A_AhkPath '" /restart "' A_ScriptFullPath '"'
        ExitApp
    } catch as err {
        MsgBox "重启失败：" err.Message, "错误"
    }
}

; f键处理
$f:: {
    global fKeyPressed, lastFKeyPressTime, pendingF, fRepeatTimer, comboKeyPressed, preventNormalKey, lastKeyPressTime
    Critical "On"
    try {
        ; 更新最后按键时间
        lastKeyPressTime := A_TickCount
        
        if (!fKeyPressed) {
            fKeyPressed := true
            lastFKeyPressTime := A_TickCount
            
            ; 检查是否有等待中的组合键
            if (comboKeyPressed != "") {
                ; 有等待的组合键，直接触发
                if comboKeys.Has(comboKeyPressed) {  ; 添加安全检查
                    SendInput comboKeys[comboKeyPressed]
                    preventNormalKey := true
                    pendingF := false
                    comboKeyPressed := ""  ; 清除记录的组合键
                }
                return
            }
            
            pendingF := true
            ; 设置定时器，延迟400ms后开始重复
            SetTimer(RepeatF, -400)
        }
    } catch as err {
        ; 出错时重置状态
        fKeyPressed := false
        preventNormalKey := false
        pendingF := false
        comboKeyPressed := ""
        SetTimer(RepeatF, 0)
    }
    return
}

$f up:: {
    global fKeyPressed, preventNormalKey, lastFKeyPressTime, pendingF, fRepeatTimer
    Critical "On"
    
    ; 取消重复定时器
    SetTimer(RepeatF, 0)
    
    if (pendingF && !preventNormalKey) {
        SendInput "f"
    }
    fKeyPressed := false
    preventNormalKey := false
    pendingF := false
    return
}

; f键重复函数
RepeatF() {
    global fKeyPressed, preventNormalKey, pendingF
    if (fKeyPressed && !preventNormalKey) {
        if (pendingF) {
            SendInput "f"
            pendingF := false
        }
        ; 设置33ms的重复间隔（约30Hz）
        SetTimer(SendF, 33)
    }
}

; 发送f的函数
SendF() {
    global fKeyPressed, preventNormalKey
    if (fKeyPressed && !preventNormalKey) {
        SendInput "f"
    } else {
        SetTimer(SendF, 0)  ; 停止重复
    }
}

; 清除组合键的函数
ClearComboKey() {
    global comboKeyPressed, specialKeys, comboKeyPhysicallyPressed
    if (comboKeyPressed != "") {
        ; 发送原始按键
        if (comboKeyPhysicallyPressed) {  ; 只有在键还在物理按着的时候才发送
            if (specialKeys.Has(comboKeyPressed)) {
                SendInput specialKeys[comboKeyPressed]
            } else {
                SendInput comboKeyPressed
            }
        }
        comboKeyPressed := ""  ; 清除记录的组合键
    }
}

; 按键处理函数
ProcessKey(key) {
    global fKeyPressed, preventNormalKey, pendingF, comboKeys, specialKeys, comboKeyPressed, comboKeyPhysicallyPressed, comboDetectionDelay, lastKeyPressTime
    Critical "On"
    
    ; 更新最后按键时间
    lastKeyPressTime := A_TickCount
    
    ; 如果当前有等待的组合键，且按下了另一个非f键
    if (comboKeyPressed != "" && key != "f") {
        ; 立即发送之前等待的键
        if (specialKeys.Has(comboKeyPressed)) {
            SendInput specialKeys[comboKeyPressed]
        } else {
            SendInput comboKeyPressed
        }
        ; 清除组合键状态
        SetTimer(ClearComboKey, 0)  ; 取消计时器
        comboKeyPressed := ""
        comboKeyPhysicallyPressed := false
    }
    
    ; 如果是可能的组合键
    if (comboKeys.Has(key)) {
        if (fKeyPressed) {
            ; f已经按下，直接触发组合键
            preventNormalKey := true
            pendingF := false
            SendInput comboKeys[key]
        } else {
            ; f还没按下，记录这个键并等待短暂时间
            comboKeyPressed := key
            comboKeyPhysicallyPressed := true
            SetTimer(ClearComboKey, -comboDetectionDelay)  ; 使用配置的延迟时间
        }
        return
    }
    
    ; 不是组合键的情况
    if (fKeyPressed) {
        if (pendingF) {
            SendInput "f"
            pendingF := false
        }
        ; 检查是否是特殊键
        if (specialKeys.Has(key)) {
            SendInput specialKeys[key]
        } else {
            SendInput key
        }
    } else {
        ; 检查是否是特殊键
        if (specialKeys.Has(key)) {
            SendInput specialKeys[key]
        } else {
            SendInput key
        }
    }
}

; 处理组合键的释放
ProcessKeyUp(key) {
    global comboKeyPressed, comboKeyPhysicallyPressed, specialKeys
    try {
        if (comboKeys.Has(key) && key == comboKeyPressed) {
            comboKeyPhysicallyPressed := false
            ; 如果释放时这个键仍然是等待状态，立即发送它
            if (comboKeyPressed != "") {
                if (specialKeys.Has(comboKeyPressed)) {
                    SendInput specialKeys[comboKeyPressed]
                } else {
                    SendInput comboKeyPressed
                }
                SetTimer(ClearComboKey, 0)  ; 取消计时器
                comboKeyPressed := ""
            }
        }
    } catch as err {
        ; 出错时重置状态
        comboKeyPressed := ""
        comboKeyPhysicallyPressed := false
    }
}

; 处理所有其他按键
#HotIf true  ; 应用于所有情况
$a:: ProcessKey("a")
$a up:: ProcessKeyUp("a")
$b:: ProcessKey("b")
$b up:: ProcessKeyUp("b")
$c:: ProcessKey("c")
$c up:: ProcessKeyUp("c")
$d:: ProcessKey("d")
$d up:: ProcessKeyUp("d")
$e:: ProcessKey("e")
$e up:: ProcessKeyUp("e")
$g:: ProcessKey("g")
$g up:: ProcessKeyUp("g")
$h:: ProcessKey("h")
$h up:: ProcessKeyUp("h")
$i:: ProcessKey("i")
$i up:: ProcessKeyUp("i")
$j:: ProcessKey("j")
$j up:: ProcessKeyUp("j")
$k:: ProcessKey("k")
$k up:: ProcessKeyUp("k")
$l:: ProcessKey("l")
$l up:: ProcessKeyUp("l")
$m:: ProcessKey("m")
$m up:: ProcessKeyUp("m")
$n:: ProcessKey("n")
$n up:: ProcessKeyUp("n")
$o:: ProcessKey("o")
$o up:: ProcessKeyUp("o")
$p:: ProcessKey("p")
$p up:: ProcessKeyUp("p")
$q:: ProcessKey("q")
$q up:: ProcessKeyUp("q")
$r:: ProcessKey("r")
$r up:: ProcessKeyUp("r")
$s:: ProcessKey("s")
$s up:: ProcessKeyUp("s")
$t:: ProcessKey("t")
$t up:: ProcessKeyUp("t")
$u:: ProcessKey("u")
$u up:: ProcessKeyUp("u")
$v:: ProcessKey("v")
$v up:: ProcessKeyUp("v")
$w:: ProcessKey("w")
$w up:: ProcessKeyUp("w")
$x:: ProcessKey("x")
$x up:: ProcessKeyUp("x")
$y:: ProcessKey("y")
$y up:: ProcessKeyUp("y")
$z:: ProcessKey("z")
$z up:: ProcessKeyUp("z")
$SC027:: ProcessKey("SC027")
$SC027 up:: ProcessKeyUp("SC027")
$Space:: ProcessKey("Space")
$Space up:: ProcessKeyUp("Space")
$,:: ProcessKey(",")
$, up:: ProcessKeyUp(",")
$.:: ProcessKey(".")
$. up:: ProcessKeyUp(".")
$/:: ProcessKey("/")
$/ up:: ProcessKeyUp("/")
$[:: ProcessKey("[")
$[ up:: ProcessKeyUp("[")
$]:: ProcessKey("]")
$] up:: ProcessKeyUp("]")
$-:: ProcessKey("-")
$- up:: ProcessKeyUp("-")
$=:: ProcessKey("=")
$= up:: ProcessKeyUp("=")
$':: ProcessKey("'")
$' up:: ProcessKeyUp("'")
$\:: ProcessKey("\")
$\ up:: ProcessKeyUp("\")
$1:: ProcessKey("1")
$1 up:: ProcessKeyUp("1")
$2:: ProcessKey("2")
$2 up:: ProcessKeyUp("2")
$3:: ProcessKey("3")
$3 up:: ProcessKeyUp("3")
$4:: ProcessKey("4")
$4 up:: ProcessKeyUp("4")
$5:: ProcessKey("5")
$5 up:: ProcessKeyUp("5")
$6:: ProcessKey("6")
$6 up:: ProcessKeyUp("6")
$7:: ProcessKey("7")
$7 up:: ProcessKeyUp("7")
$8:: ProcessKey("8")
$8 up:: ProcessKeyUp("8")
$9:: ProcessKey("9")
$9 up:: ProcessKeyUp("9")
$0:: ProcessKey("0")
$0 up:: ProcessKeyUp("0")

; 添加一个托盘图标提示
A_TrayMenu.Add "超级F键设置", ShowSettings
A_TrayMenu.Add "重启", RestartApp
A_TrayMenu.Add  ; 添加分隔线
A_TrayMenu.Add "退出", (*) => ExitApp()

; 显示帮助对话框
ShowHelp(*) {
    helpText := "超级F键 v1.0`n`n"
    helpText .= "基本功能：`n"
    helpText .= "按住F键并配合其他按键使用，或先按其他键再按F键。`n`n"
    helpText .= "组合键列表：`n"
    
    ; 显示所有组合键，禁用的显示为灰色
    ; 按照常用程度和功能相关性排序
    orderedKeys := ["j", "h", "SC027",  ; 删除类
                   "k", "l",             ; 方向类
                   "m", "n",             ; 回车类
                   "i"]                  ; 符号类
    
    for key in orderedKeys {
        config := comboKeyConfigs[key]
        keyName := StrReplace(key, "SC027", ";")
        
        if (key = "h") {
            ; 特殊处理f+h的显示
            switch config["mode"] {
                case 0:
                    helpText .= Format("f+{} = 未设置`n", keyName)
                case 1:
                    helpText .= Format("f+{} = Ctrl+退格键（删除单词）`n", keyName)
                case 2:
                    helpText .= Format("f+{} = Esc键`n", keyName)
            }
        } else if (config["enabled"]) {
            helpText .= Format("f+{} = {}`n", keyName, config["name"])
        } else {
            helpText .= Format("f+{} = {} [已禁用]`n", keyName, config["name"])
        }
    }
    
    helpText .= "`n使用提示：`n"
    helpText .= "1. 支持两种输入顺序，如f+j或j+f都可以`n"
    helpText .= "2. 单独按键时保持原有功能`n"
    helpText .= "3. 可在设置中调整组合键检测的灵敏度`n"
    helpText .= "4. 可在设置中开启或关闭特定组合键`n"
    helpText .= "5. f+h 键可设置为Ctrl+退格键或Esc键"
    
    MsgBox helpText, "帮助"
}

; 显示关于对话框
ShowAbout(*) {
    MsgBox "超级F键 v1.0`n`nPES作品。enjoy！", "关于"
}

ShowSettings(*) {
    global comboDetectionDelay, comboKeyConfigs, autoStartEnabled
    
    ; 创建设置对话框
    settingsGui := Gui("+AlwaysOnTop", "超级F键设置")
    
    ; 使用较大的字号
    settingsGui.SetFont("s10")
    
    ; 添加延迟设置
    settingsGui.Add("Text", "h20", "组合键检测延迟（毫秒）：")
    delayEdit := settingsGui.Add("Edit", "w60 h24", comboDetectionDelay)
    settingsGui.Add("Text", "h20", "（建议值：80-200）")
    
    ; 添加分隔线
    settingsGui.Add("Text", "xm y+5 w300 h2 0x10")
    
    ; 添加开机自启动选项
    autoStartCheckbox := settingsGui.Add("Checkbox", "xm y+5 h24", "开机时自动启动")
    autoStartCheckbox.Value := autoStartEnabled
    
    ; 添加分隔线
    settingsGui.Add("Text", "xm y+5 w300 h2 0x10")
    
    ; 添加组合键设置标题
    settingsGui.Add("Text", "xm y+5 h20", "启用的组合键功能：")
    
    ; 添加组合键复选框（除了f+h）
    checkboxes := Map()
    for key, config in comboKeyConfigs {
        if (key != "h") {
            checkbox := settingsGui.Add("Checkbox", "xm y+2 h24", 
                Format("f+{} = {}", StrReplace(key, "SC027", ";"), config["name"]))
            checkbox.Value := config["enabled"]
            checkboxes[key] := checkbox
        }
    }
    
    ; 添加分隔线
    settingsGui.Add("Text", "xm y+5 w300 h2 0x10")
    
    ; 添加f+h的设置
    settingsGui.Add("Text", "xm y+5 h20", "f+h 功能设置：")
    radioGroup := Map()
    radioGroup["none"] := settingsGui.Add("Radio", "xm y+2 h24", "禁用")
    radioGroup["ctrlbs"] := settingsGui.Add("Radio", "xm y+2 h24", "Ctrl+退格键（删除单词）")
    radioGroup["esc"] := settingsGui.Add("Radio", "xm y+2 h24", "Esc键")
    
    ; 设置当前选中状态
    switch comboKeyConfigs["h"]["mode"] {
        case 0: radioGroup["none"].Value := 1
        case 1: radioGroup["ctrlbs"].Value := 1
        case 2: radioGroup["esc"].Value := 1
    }
    
    ; 添加分隔线
    settingsGui.Add("Text", "xm y+5 w300 h2 0x10")
    
    ; 添加按钮行
    buttonRow := settingsGui.Add("Text", "xm y+5 w300 h24")  ; 容器用于对齐按钮
    okButton := settingsGui.Add("Button", "xm w60 h24", "确定")
    cancelButton := settingsGui.Add("Button", "x+10 w60 h24", "取消")
    helpButton := settingsGui.Add("Button", "x+10 w60 h24", "帮助")
    aboutButton := settingsGui.Add("Button", "x+10 w60 h24", "关于")
    
    ; 按钮事件处理
    okButton.OnEvent("Click", OkButtonClick)
    cancelButton.OnEvent("Click", CancelButtonClick)
    helpButton.OnEvent("Click", ShowHelp)
    aboutButton.OnEvent("Click", ShowAbout)
    
    ; 保存对话框相关变量到对象
    settingsGui.delayEdit := delayEdit
    settingsGui.checkboxes := checkboxes
    settingsGui.radioGroup := radioGroup
    settingsGui.autoStartCheckbox := autoStartCheckbox
    
    ; 显示对话框
    settingsGui.Show()
}

; 确定按钮事件处理
OkButtonClick(ctrl, *) {
    gui := ctrl.Gui
    ; 验证输入
    newDelay := Integer(gui.delayEdit.Value)
    if (newDelay >= 80 && newDelay <= 200) {
        global comboDetectionDelay := newDelay
        
        ; 更新组合键状态
        for key, checkbox in gui.checkboxes {
            comboKeyConfigs[key]["enabled"] := checkbox.Value
        }
        
        ; 更新f+h的模式
        if (gui.radioGroup["none"].Value) {
            comboKeyConfigs["h"]["mode"] := 0
            comboKeyConfigs["h"]["enabled"] := false
        } else if (gui.radioGroup["ctrlbs"].Value) {
            comboKeyConfigs["h"]["mode"] := 1
            comboKeyConfigs["h"]["enabled"] := true
        } else if (gui.radioGroup["esc"].Value) {
            comboKeyConfigs["h"]["mode"] := 2
            comboKeyConfigs["h"]["enabled"] := true
        }
        
        ; 更新活动的组合键列表
        global comboKeys := GetActiveComboKeys()
        
        ; 处理开机自启动设置
        newAutoStartState := gui.autoStartCheckbox.Value
        if (newAutoStartState != autoStartEnabled) {
            if SetAutoStart(newAutoStartState) {
                global autoStartEnabled := newAutoStartState
            }
        }
        
        SaveSettings()
        gui.Destroy()
    } else {
        MsgBox "请输入80到200之间的数值！", "错误", "48 T1"
    }
}

; 取消按钮事件处理
CancelButtonClick(ctrl, *) {
    ctrl.Gui.Destroy()
}

; 初始化设置
try {
    LoadSettings()
} catch as err {
    MsgBox "加载设置失败：" err.Message "`n将使用默认设置。", "警告"
} 