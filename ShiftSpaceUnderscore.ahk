/* Made for GameMaker IDE v2024.14.4.222. */
#Requires AutoHotkey v2.0
#SingleInstance Force

#HotIf IsGameMakerActive()
+Space::SendText("_")
#HotIf

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