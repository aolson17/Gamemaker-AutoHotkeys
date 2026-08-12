/* Made for GameMaker IDE v2024.14.4.222. */
#Requires AutoHotkey v2.0
#SingleInstance Force
#MaxThreadsPerHotkey 1

/*
 * Keep caret, mouse, and tooltip coordinates in the same coordinate system.
 */
CoordMode("Caret", "Screen")
CoordMode("Mouse", "Screen")
CoordMode("ToolTip", "Screen")
SetWinDelay(0)

global jsdocMode := false
global jsdocFieldIndex := 0
global jsdocFields := []
global jsdocCurrentLine := 0
global typePickerVisible := false
global typePickerGui := 0
global typePickerStatus := 0
global typePickerList := 0
global typePickerEditorWindow := 0
global typePickerMenu := "root"
global typePickerItems := []
global jsdocGuiNeedsPosition := true

/*
 * Trigger immediately when /// is typed.
 */
:*:///::
{
    CreateSmartJsdoc()
}

CreateSmartJsdoc()
{
    global jsdocMode, jsdocFieldIndex, jsdocFields, jsdocCurrentLine

    functionText := GetFollowingCode()

    if functionText = "" {
        SendText("///")

        TrayTip(
            "Could not copy the code following the current line.",
            "JSDoc"
        )
        return
    }

    /*
     * The function declaration must begin on the line immediately after ///.
     *
     * Recognizes:
     *
     * function Tile(_x, _y) {
     * function Tile(_x, _y) constructor {
     * function Tile(_x, _y) constructor{
     */
    if !RegExMatch(
        functionText,
        "is)^[ \t]*function\s+(\w+)\s*\((.*?)\)\s*(?:(constructor)\s*)?\{",
        &signature
    ) {
        SendText("///")

        TrayTip(
            "The following line is not a recognized function declaration.",
            "JSDoc"
        )
        return
    }

    functionName := signature[1]
    parameterNames := ParseParameterNames(signature[2])
    isConstructor := signature[3] != ""

    /* Constructor bodies may contain methods with their own returns. */
    hasReturnValue :=
        !isConstructor
        && FunctionReturnsValue(functionText)
    hasReturnLine := isConstructor || hasReturnValue

    template :=
        "/**`r`n"
        . " * DESCRIPTION_HERE`r`n"

    /*
     * These are the editable fields visited by Tab and Shift+Tab.
     * Parameter names are intentionally not included.
     */
    jsdocFields := [{
        token: "DESCRIPTION_HERE",
        line: 2,
        position: "end",
        label: "Function description",
        descriptionPrefix: "",
        visited: false
    }]

    for index, parameterName in parameterNames {
        typeField := "PARAM_TYPE_" index
        descriptionField := "PARAM_DESCRIPTION_" index

        template .=
            " * @param {" typeField "} "
            . parameterName
            . " " descriptionField
            . "`r`n"

        jsdocFields.Push({
            token: typeField,
            line: index + 2,
            position: "param-type",
            label: "Parameter " index " type",
            visited: false
        })
        jsdocFields.Push({
            token: descriptionField,
            line: index + 2,
            position: "end",
            label: "Parameter " index " description",
            visited: false
        })
    }

    if isConstructor {
        template .=
            " * @return {Struct." functionName "}`r`n"
    }
    else if hasReturnValue {
        template .=
            " * @returns {RETURN_TYPE} RETURN_DESCRIPTION`r`n"

        returnLine := parameterNames.Length + 3
        jsdocFields.Push({
            token: "RETURN_TYPE",
            line: returnLine,
            position: "return-type",
            label: "Return type",
            visited: false
        })
        jsdocFields.Push({
            token: "RETURN_DESCRIPTION",
            line: returnLine,
            position: "end",
            label: "Return description",
            visited: false
        })
    }

    template .= " */"

    if !PasteText(template)
        return

    jsdocMode := true
    jsdocFieldIndex := 1
    jsdocCurrentLine :=
        parameterNames.Length
        + (hasReturnLine ? 4 : 3)

    SelectJsdocField(jsdocFields[jsdocFieldIndex])

    UpdateJsdocIndicator()
}

ParseParameterNames(parameterText)
{
    parameters := []
    parameterText := Trim(parameterText)

    if parameterText = ""
        return parameters

    for rawParameter in StrSplit(parameterText, ",") {
        parameter := Trim(rawParameter)

        /*
         * Remove a default value:
         *
         * amount = 1
         *
         * becomes:
         *
         * amount
         */
        equalsPosition := InStr(parameter, "=")

        if equalsPosition
            parameter := Trim(SubStr(parameter, 1, equalsPosition - 1))

        /*
         * Remove a JavaScript rest-parameter prefix.
         */
        parameter := RegExReplace(parameter, "^\.\.\.", "")
        parameter := Trim(parameter)

        if parameter != ""
            parameters.Push(parameter)
    }

    return parameters
}

FunctionReturnsValue(functionText)
{
    body := ExtractFirstFunctionBody(functionText)

    if body = ""
        return false

    depth := 0
    quoteCharacter := ""
    inLineComment := false
    inBlockComment := false
    escaped := false
    bodyLength := StrLen(body)
    index := 1

    while index <= bodyLength {
        character := SubStr(body, index, 1)
        nextCharacter :=
            index < bodyLength
            ? SubStr(body, index + 1, 1)
            : ""

        if inLineComment {
            if character = "`r" || character = "`n"
                inLineComment := false

            index += 1
            continue
        }

        if inBlockComment {
            if character = "*" && nextCharacter = "/" {
                inBlockComment := false
                index += 2
            }
            else {
                index += 1
            }

            continue
        }

        if quoteCharacter != "" {
            if escaped {
                escaped := false
            }
            else if character = "\" {
                escaped := true
            }
            else if character = quoteCharacter {
                quoteCharacter := ""
            }

            index += 1
            continue
        }

        if character = "/" && nextCharacter = "/" {
            inLineComment := true
            index += 2
            continue
        }

        if character = "/" && nextCharacter = "*" {
            inBlockComment := true
            index += 2
            continue
        }

        if character = "'" || character = Chr(34) {
            quoteCharacter := character
            index += 1
            continue
        }

        if character = "{" {
            depth += 1
            index += 1
            continue
        }

        if character = "}" {
            depth := Max(0, depth - 1)
            index += 1
            continue
        }

        if depth = 0 && SubStr(body, index, 6) = "return" {
            previousCharacter :=
                index > 1
                ? SubStr(body, index - 1, 1)
                : ""
            followingCharacter :=
                index + 6 <= bodyLength
                ? SubStr(body, index + 6, 1)
                : ""

            previousIsIdentifier := RegExMatch(
                previousCharacter,
                "[A-Za-z0-9_]"
            )
            followingIsIdentifier := RegExMatch(
                followingCharacter,
                "[A-Za-z0-9_]"
            )

            if !previousIsIdentifier && !followingIsIdentifier {
                valueIndex := index + 6

                while valueIndex <= bodyLength {
                    valueCharacter := SubStr(body, valueIndex, 1)

                    if valueCharacter != " " && valueCharacter != "`t"
                        break

                    valueIndex += 1
                }

                if valueIndex <= bodyLength {
                    valueCharacter := SubStr(body, valueIndex, 1)
                    valueNextCharacter :=
                        valueIndex < bodyLength
                        ? SubStr(body, valueIndex + 1, 1)
                        : ""

                    if valueCharacter != ";"
                        && valueCharacter != "}"
                        && valueCharacter != "`r"
                        && valueCharacter != "`n"
                        && !(valueCharacter = "/"
                            && (valueNextCharacter = "/"
                                || valueNextCharacter = "*")) {
                        return true
                    }
                }
            }
        }

        index += 1
    }

    return false
}

ExtractFirstFunctionBody(functionText)
{
    openingBrace := InStr(functionText, "{")

    if !openingBrace
        return ""

    depth := 0
    bodyStart := openingBrace + 1
    remainingText := SubStr(functionText, openingBrace)

    Loop Parse, remainingText {
        character := A_LoopField

        if character = "{" {
            depth += 1
        }
        else if character = "}" {
            depth -= 1

            if depth = 0 {
                bodyLength :=
                    openingBrace
                    + A_Index
                    - bodyStart
                    - 1

                return SubStr(
                    functionText,
                    bodyStart,
                    bodyLength
                )
            }
        }
    }

    /*
     * Return the available text if no matching closing brace was found.
     */
    return SubStr(functionText, bodyStart)
}

GetFollowingCode()
{
    savedClipboard := ClipboardAll()
    A_Clipboard := ""
    selectionActive := false

    try {
        /*
         * Move from the current blank line to the beginning of the next line.
         */
        Send("{Home}")
        Send("{Down}")
        Send("{Home}")
        Sleep(30)

        /*
         * Select from the function declaration to the end of the file.
         */
        Send("^+{End}")
        selectionActive := true
        Sleep(30)

        Send("^c")
        Sleep(10)

        /* Remove the visible selection before waiting for the copy. */
        CollapseCodeSelection()
        selectionActive := false

        if !ClipWait(2)
            return ""

        functionText := A_Clipboard

        return functionText
    }
    finally {
        if selectionActive
            CollapseCodeSelection()

        A_Clipboard := savedClipboard
    }
}

CollapseCodeSelection()
{
    /*
     * Left collapses the selection at its beginning in VS Code and most
     * Windows editors.
     */
    Send("{Left}")
    Sleep(10)

    /*
     * Return from the function line to the original JSDoc line.
     */
    Send("{Up}")
    Send("{Home}")
    Sleep(10)
}

PasteText(text)
{
    savedClipboard := ClipboardAll()
    A_Clipboard := ""

    try {
        A_Clipboard := text

        if !ClipWait(1) {
            TrayTip(
                "Could not put the JSDoc template on the clipboard.",
                "JSDoc"
            )
            return false
        }

        /*
         * Paste the entire template at once. This prevents the editor from
         * inserting an additional * on each line.
         */
        Send("^v")
        Sleep(150)

        return true
    }
    finally {
        A_Clipboard := savedClipboard
    }
}

SelectJsdocField(field)
{
    global jsdocCurrentLine

    /*
     * Use Find only for the first description field. Besides selecting the
     * placeholder, GameMaker scrolls the matching line toward the center of
     * the editor. All later fields use direct row navigation.
     */
    if field.token = "DESCRIPTION_HERE" && !field.visited {
        Send("^f")
        Sleep(40)
        SendText(field.token)
        Sleep(40)
        Send("{Enter}")
        Sleep(30)
        Send("{Esc}")
        Sleep(30)

        jsdocCurrentLine := field.line
        return
    }

    /*
     * Navigate by the row calculated while constructing the template.
     * This avoids opening Find for every field.
     */
    Send("{Home 2}")

    lineDifference := field.line - jsdocCurrentLine

    if lineDifference < 0 {
        Send("{Up " Abs(lineDifference) "}")
    }
    else if lineDifference > 0 {
        Send("{Down " lineDifference "}")
    }

    Send("{Home 2}")

    if field.visited && SelectEditedJsdocField(
        field,
        IsTypeField(field)
    ) {
        jsdocCurrentLine := field.line

        if IsTypeField(field)
            ShowTypePicker()

        return
    }

    if field.position = "param-type" {
        /* Immediately after: space, *, space, @param, space, {. */
        Send("{Right 11}")
        if !field.visited
            Send("+{Right " StrLen(field.token) "}")
    }
    else if field.position = "return-type" {
        /* Immediately after: space, *, space, @returns, space, {. */
        Send("{Right 13}")
        if !field.visited
            Send("+{Right " StrLen(field.token) "}")
    }
    else {
        /* Descriptions are always the final token on their row. */
        Send("{End}")
        if !field.visited
            Send("+{Left " StrLen(field.token) "}")
    }

    jsdocCurrentLine := field.line

    if IsTypeField(field)
        ShowTypePicker()
}

IsTypeField(field)
{
    return field.position = "param-type"
        || field.position = "return-type"
}

SelectEditedJsdocField(field, forceSelection := false)
{
    savedClipboard := ClipboardAll()
    A_Clipboard := ""
    lineText := ""

    try {
        /* Copy only this JSDoc row, not the rest of the file. */
        Send("{Home 2}")
        Send("+{End}")
        Send("^c")

        if ClipWait(0.05)
            lineText := A_Clipboard

        /* Collapse the temporary whole-line selection at its beginning. */
        Send("{Left}")
    }
    finally {
        A_Clipboard := savedClipboard
    }

    if lineText = ""
        return false

    if field.position = "param-type" {
        pattern := "^(\s*\*\s*@param\s*\{)([^}]*)\}"
    }
    else if field.position = "return-type" {
        pattern := "^(\s*\*\s*@returns\s*\{)([^}]*)\}"
    }
    else if field.token = "DESCRIPTION_HERE" {
        if field.descriptionPrefix = "Struct. "
            pattern := "^(\s*\*\s?Struct\.\s+)(.*)$"
        else
            pattern := "^(\s*\*\s?)(.*)$"
    }
    else if InStr(field.token, "PARAM_DESCRIPTION_") = 1 {
        pattern := "^(\s*\*\s*@param\s*\{[^}]*\}\s+\S+\s+)(.*)$"
    }
    else {
        pattern := "^(\s*\*\s*@returns\s*\{[^}]*\}\s*)(.*)$"
    }

    if !RegExMatch(lineText, pattern, &fieldMatch)
        return false

    fieldOffset := StrLen(fieldMatch[1])
    fieldText := fieldMatch[2]
    fieldLength := StrLen(fieldText)

    Send("{Home 2}")

    if fieldOffset > 0
        Send("{Right " fieldOffset "}")

    if fieldLength > 0 {
        if forceSelection || fieldText = field.token
            Send("+{Right " fieldLength "}")
        else
            Send("{Right " fieldLength "}")
    }

    return true
}

EnsureTypePicker()
{
    global typePickerGui, typePickerStatus
    global typePickerList

    if IsObject(typePickerGui)
        return

    typePickerGui := Gui("+AlwaysOnTop +ToolWindow", "JSDoc")
    typePickerGui.MarginX := 10
    typePickerGui.MarginY := 10
    typePickerStatus := typePickerGui.Add(
        "Text",
        "w240",
        "JSDoc"
    )
    typePickerList := typePickerGui.Add(
        "ListView",
        "w240 r14 -Hdr -Multi Hidden",
        ["JSDoc type"]
    )

    typePickerList.ModifyCol(1, 215)
    typePickerList.OnEvent("Click", TypePickerClicked)
    typePickerGui.OnEvent("Close", TypePickerClosed)
    typePickerGui.OnEvent("Escape", TypePickerClosed)
}

GetTypePickerMenu(menuName)
{
    if menuName = "root" {
        return [
            {label: "Real", value: "Real", advance: true},
            {label: "String", value: "String", advance: true},
            {label: "Boolean", value: "Boolean", advance: true},
            {label: "Array<>", value: "Array<>", insideBrackets: true},
            {label: "Enum.", value: "Enum."},
            {label: "Struct.", value: "Struct."},
            {label: "Id.  >", submenu: "id"},
            {label: "Asset.  >", submenu: "asset"},
            {label: "Constant.  >", submenu: "constant"},
            {label: "Any", value: "Any", advance: true},
            {label: "Other", manual: true}
        ]
    }

    if menuName = "id" {
        return [
            {label: "← Back", submenu: "root"},
            {
                label: "Instance<>",
                value: "Id.Instance<>",
                insideBrackets: true
            },
            {label: "DsList", value: "Id.DsList", advance: true},
            {label: "DsMap", value: "Id.DsMap", advance: true},
            {label: "DsGrid", value: "Id.DsGrid", advance: true},
            {label: "DsQueue", value: "Id.DsQueue", advance: true},
            {
                label: "DsPriority",
                value: "Id.DsPriority",
                advance: true
            },
            {label: "Uniform", value: "Id.Uniform", advance: true}
        ]
    }

    if menuName = "asset" {
        return [
            {label: "← Back", submenu: "root"},
            {label: "Obj", value: "Asset.GMObj", advance: true},
            {
                label: "Sprite",
                value: "Asset.GMSprite",
                advance: true
            },
            {label: "Room", value: "Asset.GMRoom", advance: true},
            {
                label: "AudioGroup",
                value: "Asset.GMAudioGroup",
                advance: true
            },
            {label: "Font", value: "Asset.GMFont", advance: true},
            {label: "Path", value: "Asset.GMPath", advance: true},
            {
                label: "Script",
                value: "Asset.GMScript",
                advance: true
            },
            {
                label: "Shader",
                value: "Asset.GMShader",
                advance: true
            },
            {
                label: "Sound",
                value: "Asset.GMSound",
                advance: true
            },
            {
                label: "Timeline",
                value: "Asset.GMTimeline",
                advance: true
            },
            {
                label: "Sequence",
                value: "Asset.GMSequence",
                advance: true
            },
            {
                label: "TileSet",
                value: "Asset.GMTileSet",
                advance: true
            },
            {
                label: "AnimCurve",
                value: "Asset.GMAnimCurve",
                advance: true
            }
        ]
    }

    return [
        {label: "← Back", submenu: "root"},
        {
            label: "Color",
            value: "Constant.Color",
            advance: true
        },
        {
            label: "HAlign",
            value: "Constant.HAlign",
            advance: true
        },
        {
            label: "VAlign",
            value: "Constant.VAlign",
            advance: true
        },
        {
            label: "VirtualKey",
            value: "Constant.VirtualKey",
            advance: true
        },
        {
            label: "PrimitiveType",
            value: "Constant.PrimitiveType",
            advance: true
        },
        {label: "Other", value: "Constant."}
    ]
}

LoadTypePickerMenu(menuName)
{
    global typePickerMenu, typePickerItems, typePickerList

    typePickerMenu := menuName
    typePickerItems := GetTypePickerMenu(menuName)
    typePickerList.Delete()

    for item in typePickerItems
        typePickerList.Add("", item.label)

    typePickerList.ModifyCol(1, 215)
    typePickerList.Modify(1, "Select Focus Vis")
}

PositionJsdocGui(activate := false)
{
    global typePickerGui, typePickerEditorWindow

    editorWindow := typePickerEditorWindow

    if !editorWindow || !WinExist(editorWindow)
        editorWindow := WinExist("A")

    if editorWindow && editorWindow != typePickerGui.Hwnd {
        typePickerEditorWindow := editorWindow
        WinGetPos(
            &windowX,
            &windowY,
            ,
            &windowHeight,
            editorWindow
        )
        guiX := windowX + 20
        showOptions :=
            (activate ? "" : "NoActivate ")
            . "AutoSize"
        typePickerGui.Show(showOptions)
        WinGetPos(, , , &guiHeight, typePickerGui.Hwnd)
        guiY := windowY + Floor((windowHeight - guiHeight) / 2)
        typePickerGui.Move(guiX, guiY)
    }
    else {
        typePickerGui.Show(
            (activate ? "" : "NoActivate ") "AutoSize"
        )
    }
}

ShowTypePicker()
{
    global typePickerVisible, typePickerGui, typePickerList
    global typePickerEditorWindow, jsdocGuiNeedsPosition

    EnsureTypePicker()
    activeWindow := WinExist("A")

    if activeWindow != typePickerGui.Hwnd
        typePickerEditorWindow := activeWindow

    typePickerVisible := true
    typePickerList.Visible := true
    LoadTypePickerMenu("root")
    PositionJsdocGui(true)
    jsdocGuiNeedsPosition := false
    typePickerList.Focus()
}

HideTypePicker()
{
    global typePickerVisible, typePickerList, jsdocGuiNeedsPosition

    pickerWasVisible := typePickerVisible

    typePickerVisible := false

    if IsObject(typePickerList)
        typePickerList.Visible := false

    if pickerWasVisible
        jsdocGuiNeedsPosition := true
}

RepositionJsdocGui()
{
    global jsdocMode, typePickerVisible

    if jsdocMode && !typePickerVisible
        PositionJsdocGui(false)
}

MoveTypePicker(direction)
{
    global typePickerList, typePickerItems

    currentChoice := typePickerList.GetNext(0, "F")

    if currentChoice = 0
        currentChoice := 1

    nextChoice := currentChoice + direction

    if nextChoice > typePickerItems.Length
        nextChoice := 1
    else if nextChoice < 1
        nextChoice := typePickerItems.Length

    typePickerList.Modify(0, "-Select -Focus")
    typePickerList.Modify(nextChoice, "Select Focus Vis")
}

ChooseTypePicker()
{
    global jsdocMode, jsdocFields, jsdocFieldIndex
    global typePickerItems, typePickerList, typePickerEditorWindow

    if !jsdocMode
        return

    if jsdocFieldIndex < 1 || jsdocFieldIndex > jsdocFields.Length
        return

    selectedRow := typePickerList.GetNext(0, "F")

    if selectedRow = 0
        return

    item := typePickerItems[selectedRow]

    if item.HasOwnProp("submenu") {
        LoadTypePickerMenu(item.submenu)
        typePickerList.Focus()
        return
    }

    activeField := jsdocFields[jsdocFieldIndex]
    HideTypePicker()

    if typePickerEditorWindow {
        WinActivate(typePickerEditorWindow)
    }

    if !item.HasOwnProp("manual") {
        SendText(item.value)

        if item.HasOwnProp("insideBrackets")
            Send("{Left}")

        activeField.visited := true
    }

    if item.HasOwnProp("advance") && item.advance
        MoveJsdocField(1)
    else
        UpdateJsdocIndicator()
}

TypePickerClicked(control, rowNumber)
{
    if rowNumber > 0 {
        control.Modify(0, "-Select -Focus")
        control.Modify(rowNumber, "Select Focus Vis")
        ChooseTypePicker()
    }
}

TypePickerClosed(*)
{
    EndJsdocMode()
}

MouseClickEndsJsdoc()
{
    global typePickerGui

    if IsObject(typePickerGui) {
        MouseGetPos(, , &clickedWindow)
        clickedRoot := DllCall(
            "user32\GetAncestor",
            "Ptr", clickedWindow,
            "UInt", 2,
            "Ptr"
        )

        if clickedRoot = typePickerGui.Hwnd
            return
    }

    EndJsdocMode()
}

UpdateJsdocIndicator()
{
    global jsdocMode, jsdocFieldIndex, jsdocFields
    global typePickerStatus, typePickerVisible
    global jsdocGuiNeedsPosition

    if !jsdocMode {
        return
    }

    if jsdocFields.Length = 0 {
        EndJsdocMode()
        return
    }

    if jsdocFieldIndex < 1 || jsdocFieldIndex > jsdocFields.Length {
        EndJsdocMode()
        return
    }

    currentField := jsdocFields[jsdocFieldIndex]
    fieldLabel := currentField.label

    indicatorText :=
        "JSDoc "
        . jsdocFieldIndex
        . "/"
        . jsdocFields.Length
        . " fields"
        . "`n"
        . fieldLabel
        . "`n"
        . "Tab: next | Shift+Tab: previous | Esc: exit"

    EnsureTypePicker()
    typePickerStatus.Text := indicatorText

    if !typePickerVisible && jsdocGuiNeedsPosition {
        jsdocGuiNeedsPosition := false
        SetTimer(RepositionJsdocGui, -1)
    }
}

GetTrueCaretPos(&x, &y)
{
    x := ""
    y := ""

    if CaretGetPos(&x, &y)
        return true

    return GetUIAutomationCaretPos(&x, &y)
}

GetUIAutomationCaretPos(&x, &y)
{
    static UIA_TEXT_PATTERN_2_ID := 10024
    static IID_TEXT_PATTERN_2 := Buffer(16, 0)
    static uia := 0
    static initialized := false

    x := ""
    y := ""

    try {
        if !initialized {
            DllCall(
                "ole32\CLSIDFromString",
                "WStr", "{506A921A-FCC9-409F-B23B-37EB74106872}",
                "Ptr", IID_TEXT_PATTERN_2.Ptr,
                "HRESULT"
            )

            uia := ComObject(
                "{FF48DBA4-60EF-4201-AA87-54103EEF594E}",
                "{30CBE57D-D9D0-452A-AB13-7AC5AC4825EE}"
            )

            initialized := true
        }

        focusedElementPointer := 0

        /* IUIAutomation::GetFocusedElement, vtable index 8. */
        ComCall(
            8,
            uia,
            "Ptr*", &focusedElementPointer
        )

        if !focusedElementPointer
            return false

        focusedElement := ComValue(
            13,
            focusedElementPointer,
            1
        )

        textPatternPointer := 0

        /* IUIAutomationElement::GetCurrentPatternAs, index 14. */
        ComCall(
            14,
            focusedElement,
            "Int", UIA_TEXT_PATTERN_2_ID,
            "Ptr", IID_TEXT_PATTERN_2.Ptr,
            "Ptr*", &textPatternPointer
        )

        if !textPatternPointer
            return false

        textPattern := ComValue(
            13,
            textPatternPointer,
            1
        )

        caretIsActive := 0
        textRangePointer := 0

        /* IUIAutomationTextPattern2::GetCaretRange, index 10. */
        ComCall(
            10,
            textPattern,
            "Int*", &caretIsActive,
            "Ptr*", &textRangePointer
        )

        if !caretIsActive || !textRangePointer
            return false

        textRange := ComValue(
            13,
            textRangePointer,
            1
        )

        /*
         * The caret range has zero width. Expand it to the surrounding
         * character so GetBoundingRectangles returns a visible rectangle.
         * TextUnit_Character is enum value 0.
         */
        ComCall(
            6,
            textRange,
            "Int", 0
        )

        safeArrayPointer := 0
        dataPointer := 0
        dataIsLocked := false

        try {
            /* IUIAutomationTextRange::GetBoundingRectangles, index 10. */
            ComCall(
                10,
                textRange,
                "Ptr*", &safeArrayPointer
            )

            if !safeArrayPointer
                return false

            dimensions := DllCall(
                "oleaut32\SafeArrayGetDim",
                "Ptr", safeArrayPointer,
                "UInt"
            )

            if dimensions != 1
                return false

            lowerBound := 0
            upperBound := -1

            DllCall(
                "oleaut32\SafeArrayGetLBound",
                "Ptr", safeArrayPointer,
                "UInt", 1,
                "Int*", &lowerBound,
                "HRESULT"
            )
            DllCall(
                "oleaut32\SafeArrayGetUBound",
                "Ptr", safeArrayPointer,
                "UInt", 1,
                "Int*", &upperBound,
                "HRESULT"
            )

            if upperBound - lowerBound + 1 < 4
                return false

            DllCall(
                "oleaut32\SafeArrayAccessData",
                "Ptr", safeArrayPointer,
                "Ptr*", &dataPointer,
                "HRESULT"
            )
            dataIsLocked := true

            left := NumGet(dataPointer, 0, "Double")
            top := NumGet(dataPointer, 8, "Double")
            height := NumGet(dataPointer, 24, "Double")

            if left < 0 || top < 0 || height <= 0
                return false

            x := Round(left)
            y := Round(top + height)
            return true
        }
        finally {
            if dataIsLocked
                DllCall(
                    "oleaut32\SafeArrayUnaccessData",
                    "Ptr", safeArrayPointer
                )

            if safeArrayPointer
                DllCall(
                    "oleaut32\SafeArrayDestroy",
                    "Ptr", safeArrayPointer
                )
        }
    }
    catch {
        return false
    }
}

FormatFieldLabel(field)
{
    if field = "DESCRIPTION_HERE"
        return "Function description"

    if RegExMatch(
        field,
        "^PARAM_TYPE_(\d+)$",
        &match
    ) {
        return "Parameter " match[1] " type"
    }

    if RegExMatch(
        field,
        "^PARAM_DESCRIPTION_(\d+)$",
        &match
    ) {
        return "Parameter " match[1] " description"
    }

    if field = "RETURN_TYPE"
        return "Return type"

    if field = "RETURN_DESCRIPTION"
        return "Return description"

    return field
}

EndJsdocMode()
{
    global jsdocMode, jsdocFieldIndex, jsdocFields, jsdocCurrentLine
    global typePickerGui, jsdocGuiNeedsPosition

    HideTypePicker()

    if IsObject(typePickerGui)
        typePickerGui.Hide()

    jsdocMode := false
    jsdocFieldIndex := 0
    jsdocFields := []
    jsdocCurrentLine := 0
    jsdocGuiNeedsPosition := true

}

MoveJsdocField(direction)
{
    global jsdocFieldIndex, jsdocFields
    global typePickerVisible, typePickerEditorWindow

    pickerHadFocus := typePickerVisible
    HideTypePicker()

    if pickerHadFocus && typePickerEditorWindow {
        WinActivate(typePickerEditorWindow)
    }

    jsdocFields[jsdocFieldIndex].visited := true
    jsdocFieldIndex += direction

    if jsdocFieldIndex > jsdocFields.Length
        jsdocFieldIndex := 1

    if jsdocFieldIndex < 1
        jsdocFieldIndex := jsdocFields.Length

    SelectJsdocField(jsdocFields[jsdocFieldIndex])
    /* Let GameMaker render the selection before repainting the status GUI. */
    SetTimer(UpdateJsdocIndicator, -20)
    return true
}

TrackJsdocVerticalMove(direction)
{
    global jsdocCurrentLine

    jsdocCurrentLine := Max(1, jsdocCurrentLine + direction)
}

TrackJsdocNewLine()
{
    global jsdocCurrentLine, jsdocFieldIndex, jsdocFields

    insertionLine := jsdocCurrentLine
    activeField := jsdocFields[jsdocFieldIndex]
    enteredFromActiveDescription :=
        activeField.position = "end"
        && activeField.line = insertionLine

    /* Every stored field below the insertion point moves down one row. */
    for field in jsdocFields {
        if field.line > insertionLine
            field.line += 1
    }

    jsdocCurrentLine += 1

    /* Return to the continuation row for a multiline description. */
    if enteredFromActiveDescription
        activeField.line := jsdocCurrentLine
}

GetTextBeforeCaret()
{
    savedClipboard := ClipboardAll()
    A_Clipboard := ""
    textBeforeCaret := ""

    try {
        /* Select back to the absolute beginning of the current row. */
        Send("+{Home 2}")
        Send("^c")

        if ClipWait(0.05) {
            textBeforeCaret := A_Clipboard

            /* Restore the caret to the selection's original right edge. */
            Send("{Right}")
        }
    }
    finally {
        A_Clipboard := savedClipboard
    }

    return textBeforeCaret
}

HandleJsdocEnter()
{
    global jsdocCurrentLine, jsdocFieldIndex, jsdocFields

    activeField := jsdocFields[jsdocFieldIndex]
    alignParameterDescription :=
        activeField.line = jsdocCurrentLine
        && InStr(activeField.token, "PARAM_DESCRIPTION_") = 1
    targetColumn := 0

    if alignParameterDescription {
        if activeField.HasOwnProp("continuationColumn") {
            targetColumn := activeField.continuationColumn
        }
        else {
            textBeforeCaret := GetTextBeforeCaret()

            if RegExMatch(
                textBeforeCaret,
                "^(\s*\*\s*@param\s*\{[^}]*\}\s+\S+\s+)",
                &descriptionStart
            ) {
                targetColumn := StrLen(descriptionStart[1])
                activeField.continuationColumn := targetColumn
            }
        }
    }

    Send("{Enter}")
    Sleep(25)
    TrackJsdocNewLine()

    if targetColumn > 0 {
        currentColumn := StrLen(GetTextBeforeCaret())
        spacesToAdd := Max(0, targetColumn - currentColumn)

        if spacesToAdd > 0
            Send("{Space " spacesToAdd "}")
    }
}

#HotIf jsdocMode

Tab::
{
    global typePickerVisible

    if typePickerVisible
        MoveTypePicker(1)
    else
        MoveJsdocField(1)
}

+Tab::
{
    global typePickerVisible

    if typePickerVisible
        MoveTypePicker(-1)
    else
        MoveJsdocField(-1)
}

^Tab::MoveJsdocField(1)
^+Tab::MoveJsdocField(-1)

Up::
{
    global typePickerVisible

    if typePickerVisible {
        MoveTypePicker(-1)
    }
    else {
        Send("{Up}")
        TrackJsdocVerticalMove(-1)
    }
}

Down::
{
    global typePickerVisible

    if typePickerVisible {
        MoveTypePicker(1)
    }
    else {
        Send("{Down}")
        TrackJsdocVerticalMove(1)
    }
}
Enter::
{
    global typePickerVisible

    if typePickerVisible
        ChooseTypePicker()
    else
        HandleJsdocEnter()
}

NumpadEnter::
{
    global typePickerVisible

    if typePickerVisible
        ChooseTypePicker()
    else
        HandleJsdocEnter()
}

$Space::
{
    global typePickerVisible

    if typePickerVisible
        ChooseTypePicker()
    else
        Send("{Space}")
}

~*Esc::
{
    EndJsdocMode()
}

~*LButton::MouseClickEndsJsdoc()
~*RButton::MouseClickEndsJsdoc()
~*MButton::MouseClickEndsJsdoc()
~*XButton1::MouseClickEndsJsdoc()
~*XButton2::MouseClickEndsJsdoc()

#HotIf
