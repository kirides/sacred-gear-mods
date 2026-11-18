Smoke tests for the `buildsharer` and `questhelper` mods without the game: `harness.lua` is a strict mock of the parts of
the `gear` API those mods use (a call of a name the API docs do not list fails), the scenarios drive the panels and answer as the
server would. Needs the .NET SDK (the runner is LuaCSharp, the Lua of the SacredEngineRemake server).

    cd tests/modmock
    dotnet build
    set B=../../../sacred-bild/gear/lua
    dotnet run --no-build -- harness.lua fmt=%B%/fmt.lua store=%B%/store.lua toast=%B%/toast.lua ../../src/buildsharer/main.lua build_scenario.lua
    dotnet run --no-build -- harness.lua fmt=%B%/fmt.lua store=%B%/store.lua toast=%B%/toast.lua ../../src/questhelper/main.lua quest_scenario.lua

The `name=path` arguments run the libraries Sacred Gear ships in SacredGear.dll (`gear.fmt`, `gear.store`, `gear.toast`, from a
sacred-bild checkout) and put them at `gear.<name>`, as the kernel does for a mod.

Each prints `pass: ...` lines and `OK`, or `FAIL: ...` (exit code 1). This checks the mods' logic and their use of the documented API;
it does not draw anything and cannot tell how the panels look in the game.
