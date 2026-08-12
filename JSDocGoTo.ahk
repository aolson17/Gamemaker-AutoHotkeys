/* Made for GameMaker IDE v2024.14.4.222. */
#Requires AutoHotkey v2.0
#SingleInstance Force
#MaxThreadsPerHotkey 1

SetKeyDelay(-1, -1)
SetMouseDelay(-1)
CoordMode("Mouse", "Screen")

/*
 * Timing settings for GameMaker IDE interactions.
 * Sleep values are milliseconds; ClipboardTimeout is seconds.
 */
class Timing
{
    /* Wait for a middle-click's left-click replacement to place the caret. */
    static MiddleClickCaret := 10

    /* Give Escape time to dismiss signature help before native navigation. */
    static PopupDismiss := 40

    /* Let GameMaker render each temporary line selection before copying it. */
    static SelectionSettle := 25

    /* Maximum seconds to wait for copied text; lower values reject tabs faster. */
    static ClipboardTimeout := 0.15

    /* Wait for Ctrl+T to create and focus the Asset Search text field. */
    static AssetSearchOpen := 150

    /* Wait for Asset Search to populate results after entering an enum name. */
    static AssetResultsPopulate := 450

    /* Wait after Tab focuses the asset result before Enter opens it. */
    static AssetResultActivate := 50

    /* Wait for Ctrl+Shift+F to open and focus Global Search. */
    static GlobalSearchOpen := 40

    /* Let GameMaker process the new `function Name(` query before navigation. */
    static GlobalQuerySettle := 50

    /* Wait after Enter enables the Ignore Comments checkbox. */
    static IgnoreCommentsToggle := 10

    /* Wait for Ctrl+F3 to open and highlight the next global result. */
    static GlobalResultOpen := 50

    /* Wait for the second Ctrl+Shift+F before tabbing out of Search fields. */
    static GlobalSearchReopen := 50

    /* Pause between individual Tab presses so GameMaker changes focus once. */
    static TabStep := 30
}

#HotIf IsGameMakerActive()
$MButton::HandleMiddleClick()
$F1::HandleF1()
#HotIf

HandleMiddleClick()
{
    MouseGetPos(&mouseX, &mouseY)

    /* Put GameMaker's text caret exactly where the middle-click occurred. */
    Click(mouseX, mouseY)
    Sleep(Timing.MiddleClickCaret)

    if OpenReferenceAtCaret()
        return

    /* Dismiss signature help opened by the temporary line selections. */
    DismissEditorPopup()

    /* No matching type: preserve GameMaker's normal middle-click behavior. */
    KeyWait("MButton")
    ReplayMiddleClick(mouseX, mouseY)
}

ReplayMiddleClick(clickX, clickY)
{
    /* Replay at the original target, then restore the user's current mouse. */
    MouseGetPos(&restoreX, &restoreY)
    Click(clickX, clickY, "Middle")

    if restoreX != clickX || restoreY != clickY
        MouseMove(restoreX, restoreY, 0)
}

HandleF1()
{
    if OpenReferenceAtCaret()
        return

    /* Dismiss signature help opened by the temporary line selections. */
    DismissEditorPopup()

    /* No matching type: preserve GameMaker's normal F1 behavior. */
    KeyWait("F1")
    Send("{F1}")
}

DismissEditorPopup()
{
    SendEvent("{Escape}")
    Sleep(Timing.PopupDismiss)
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
        Sleep(Timing.SelectionSettle)

        if !CopySelection(&textBeforeCaret) {
            Send("{Right}")
            selectionActive := false
            return 0
        }

        Send("{Right}")
        selectionActive := false
        Sleep(Timing.SelectionSettle)

        /* Copy everything from the current caret through the line end. */
        Send("+{End}")
        selectionActive := true
        Sleep(Timing.SelectionSettle)

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

            if caretOffset >= matchStart && caretOffset < matchEnd {
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

    if !ClipWait(Timing.ClipboardTimeout)
        return false

    copiedText := A_Clipboard
    return true
}

OpenEnum(enumName)
{
    Send("^t")
    Sleep(Timing.AssetSearchOpen)

    SendText(enumName)

    /* Allow Asset Search to finish populating its result list. */
    Sleep(Timing.AssetResultsPopulate)

    /* Asset Search needs slower, distinct focus and activation events. */
    SendEvent("{Tab}")
    Sleep(Timing.AssetResultActivate)
    SendEvent("{Enter}")
}

OpenStruct(structName)
{
    Send("^+f")
    Sleep(Timing.GlobalSearchOpen)

    SendText("function " . structName . "(")
    Sleep(Timing.GlobalQuerySettle)

    /* Enable Ignore Comments after reaching its checkbox. */
    SendTabs(4)
    SendEvent("{Enter}")
    Sleep(Timing.IgnoreCommentsToggle)

    /* Find the next global occurrence. */
    Send("^{F3}")
    Sleep(Timing.GlobalResultOpen)

    /* Dismiss signature help, then move to the found function name's start. */
    DismissEditorPopup()
    Send("^{Left}")

    /* Reopen Search, leave its text fields, and close the panel. */
    Send("^+f")
    Sleep(Timing.GlobalSearchReopen)
    SendTabs(2)
    SendEvent("{Escape}")
}

SendTabs(count)
{
    Loop count {
        SendEvent("{Tab}")
        Sleep(Timing.TabStep)
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