# GameMaker AutoHotkeys

AutoHotkey v2 scripts for writing and navigating JSDoc in GameMaker.

Made for **GameMaker IDE v2024.14.4.222**.

## Requirements and setup

1. Install [AutoHotkey v2](https://www.autohotkey.com/).
2. Run `LaunchGameMakerHotkeys.bat` to start both scripts.
3. Alternatively, run either `.ahk` file separately if you only need one script.

Each script uses `#SingleInstance Force`, so launching it again reloads its latest version instead of creating a duplicate instance.

## CompleteJSDoc.ahk

Creates a JSDoc template for the GameMaker function immediately below the cursor.

### Creating a template

On an empty line directly above a function declaration, type:

```gml
///
function find_node(_tree, _value) {
    // ...
}
```

Typing the third slash triggers the script. It reads the function declaration and creates:

- One editable function-description field.
- One `@param` row for every function parameter, with parameter names filled in automatically.
- A `@returns` row when the function has a top-level `return` containing a value.
- A fixed `@return {Struct.FunctionName}` row for constructor functions.

The script enters a field-navigation mode and displays the current field number.

### JSDoc mode hotkeys

| Hotkey | Action |
| --- | --- |
| `Tab` | Move to the next JSDoc field. In the type picker, move to the next option. Fields loop from the end back to the beginning. |
| `Shift+Tab` | Move to the previous field or type option. |
| `Ctrl+Tab` | Move to the next JSDoc field even while the type picker has focus. |
| `Ctrl+Shift+Tab` | Move to the previous JSDoc field even while the type picker has focus. |
| `Up` / `Down` | Move through type-picker options. Outside the picker, move normally while keeping field tracking synchronized. |
| `Enter` / `Numpad Enter` | Choose the selected type. In a description, create a properly aligned continuation line. |
| `Space` | Choose the selected type while the picker is open; otherwise type a normal space. |
| `Escape` | End JSDoc field-navigation mode. |
| Any mouse button | End JSDoc field-navigation mode. |

### Type picker

The type picker opens for parameter and return type fields. It includes common GameMaker types and grouped `Id.`, `Asset.`, and `Constant.` options.

Complete types such as `Real`, `String`, and `Boolean` automatically advance to the next field. Types that require more input keep the caret in place. For example, between the brackets in `Array<>` or after `Struct.` and `Enum.`.

## JSDocGoTo.ahk

Navigates from JSDoc type references to their GameMaker definitions. Matching is case-insensitive and recognizes only `Enum.Name` and `Struct.Name`.

Example references:

```gml
/// @param {Enum.ABILITIES} _tree The root tree node to search
/// @param {Struct.Tree} _tree The root tree node to search
```

### Navigation hotkeys

| Hotkey | Action |
| --- | --- |
| `Middle mouse` | Place the text caret under the mouse and navigate when it is inside a recognized type reference. Normal middle-click behavior is preserved when no reference is found. |
| `F1` | Navigate using the current text-caret position. Normal F1 behavior is preserved when no reference is found. |

For an enum such as `Enum.ABILITIES`, the script opens Asset Search with `Ctrl+T`, searches for `ABILITIES`, and opens the result.

For a struct such as `Struct.Tree`, the script opens Global Search with `Ctrl+Shift+F`, searches for `function Tree(`, enables **Ignore Comments**, selects **Find Next**, and closes the search panel.

The navigation hotkeys are active only while GameMaker is the foreground application.