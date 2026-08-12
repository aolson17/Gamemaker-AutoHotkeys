#Requires AutoHotkey v2.0
#SingleInstance Force
#MaxThreadsPerHotkey 1

SetKeyDelay(-1, -1)
SetMouseDelay(-1)
CoordMode("Mouse", "Screen")

/*
 * These hotkeys are active only while GameMaker is the foreground app.
 * Neither hotkey is passed through to GameMaker.
 */
#HotIf IsGameMakerActive()
$MButton::HandleMiddleClick()
$F1::HandleF1()
#HotIf

HandleMiddleClick()
{
    MouseGetPos(&mouseX, &mouseY)

    /* A normal left click asks GameMaker to place its text caret here. */
    Click(mouseX, mouseY)
    Sleep(20)

    if OpenReferenceAtCaret()
        return

    /* No reference was found, so preserve the normal middle-click action. */
    KeyWait("MButton")
    Click(mouseX, mouseY, "Middle")
}

HandleF1()
{
    if OpenReferenceAtCaret()
        return

    /* $F1 prevents this synthetic F1 from invoking the hotkey again. */
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

    try {
        /*
         * Read the text on both sides of the caret. Right/Left collapse each
         * temporary selection back to the caret, so its position is retained.
         */
        A_Clipboard := ""
        /* Two Home presses reach column zero in GameMaker's editor. */
        Send("+{Home 2}")
        Send("^c")
        ClipWait(0.25)
        textBeforeCaret := A_Clipboard
        Send("{Right}")

        A_Clipboard := ""
        Send("+{End}")
        Send("^c")
        ClipWait(0.25)
        textAfterCaret := A_Clipboard
        Send("{Left}")

        lineText := textBeforeCaret . textAfterCaret
        caretOffset := StrLen(textBeforeCaret)

        /* Only enum.Name and struct.Name are valid; matching ignores case. */
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
        A_Clipboard := savedClipboard
    }

    return 0
}

OpenEnum(enumName)
{
    /* GameMaker's Asset Search. */
    Send("^t")
    Sleep(80)
    SendText(enumName)
    Sleep(20)
    Send("{Enter}")
}

OpenStruct(structName)
{
    /* Search the project for the struct's function declaration. */
    Send("^+f")
    Sleep(80)
    SendText("function " . structName . "(")
    Sleep(20)
    Send("{Enter}")
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
