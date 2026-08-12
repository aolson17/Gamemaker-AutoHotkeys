#Requires AutoHotkey v2.0
#SingleInstance Force
#MaxThreadsPerHotkey 1

SetKeyDelay(-1, -1)
SetMouseDelay(-1)
CoordMode("Mouse", "Screen")

#HotIf IsGameMakerActive()
$MButton::HandleMiddleClick()
$F1::HandleF1()
#HotIf

HandleMiddleClick()
{
    MouseGetPos(&mouseX, &mouseY)

    /* Put GameMaker's text caret exactly where the middle-click occurred. */
    Click(mouseX, mouseY)
    Sleep(75)

    if OpenReferenceAtCaret()
        return

    /* No matching type: preserve GameMaker's normal middle-click behavior. */
    KeyWait("MButton")
    Click(mouseX, mouseY, "Middle")
}

HandleF1()
{
    if OpenReferenceAtCaret()
        return

    /* No matching type: preserve GameMaker's normal F1 behavior. */
    KeyWait("F1")
    Send("{F1}")
}

OpenReferenceAtCaret()
{
    reference := GetReferenceAtCaret()
    if !IsObject(reference)
        return false

    if reference.kind = "enum"
        OpenEnum(reference.name)
    else
        OpenStruct(reference.name)

    return true
}

GetReferenceAtCaret()
{
    savedClipboard := ClipboardAll()
    selectionActive := false

    try {
        /* Copy everything from the line start through the current caret. */
        Send("+{Home 2}")
        selectionActive := true
        Sleep(35)

        if !CopySelection(&textBeforeCaret) {
            Send("{Right}")
            selectionActive := false
            return 0
        }

        Send("{Right}")
        selectionActive := false
        Sleep(35)

        /* Copy everything from the current caret through the line end. */
        Send("+{End}")
        selectionActive := true
        Sleep(35)

        if !CopySelection(&textAfterCaret) {
            Send("{Left}")
            selectionActive := false
            return 0
        }

        Send("{Left}")
        selectionActive := false

        lineText := textBeforeCaret . textAfterCaret
        caretOffset := StrLen(textBeforeCaret)
        searchAt := 1

        while RegExMatch(
            lineText,
            "i)(?<![A-Z0-9_])(enum|struct)\.([A-Z_][A-Z0-9_]*)",
            &match,
            searchAt
        ) {
            matchStart := match.Pos(0) - 1
            matchEnd := matchStart + match.Len(0)

            if caretOffset >= matchStart && caretOffset <= matchEnd {
                return {
                    kind: StrLower(match[1]),
                    name: match[2]
                }
            }

            searchAt := match.Pos(0) + match.Len(0)
        }
    }
    finally {
        if selectionActive
            Send("{Left}")

        A_Clipboard := savedClipboard
    }

    return 0
}

CopySelection(&copiedText)
{
    copiedText := ""
    A_Clipboard := ""
    Send("^c")

    if !ClipWait(1)
        return false

    copiedText := A_Clipboard
    return true
}

OpenEnum(enumName)
{
    Send("^t")
    Sleep(400)
    Send("^a")
    Sleep(30)
    SendText(enumName)

    /* Allow Asset Search to finish populating its result list. */
    Sleep(600)

    /* Move from the Asset Search field to its result, then open it. */
    SendTabs(1)
    SendEvent("{Enter}")
}

OpenStruct(structName)
{
    Send("^+f")
    Sleep(400)
    Send("^a")
    Sleep(30)
    SendText("function " . structName . "(")
    Sleep(250)

    /* Move to Find Next and perform the global search. */
    SendTabs(8)
    SendEvent("{Enter}")
    Sleep(350)

    /* Return focus to Search, leave its text fields, and close the panel. */
    Send("^+f")
    Sleep(200)
    SendTabs(2)
    SendEvent("{Escape}")
}

SendTabs(count)
{
    Loop count {
        SendEvent("{Tab}")
        Sleep(100)
    }
}

IsGameMakerActive()
{
    try {
        processName := WinGetProcessName("A")
        windowTitle := WinGetTitle("A")

        return RegExMatch(processName, "i)^GameMaker.*\.exe$")
            || InStr(windowTitle, "GameMaker", false)
    }
    catch {
        return false
    }
}