using Lua;
using Lua.Standard;
// args: harness.lua [name=path/to/library.lua ...] mod_main.lua scenario.lua
// A name=path argument runs a library of SacredGear.dll (sacred-bild gear/lua/<name>.lua) and puts what it returns at gear.<name>.
var state = LuaState.Create();
state.OpenBasicLibrary(); state.OpenStringLibrary(); state.OpenTableLibrary(); state.OpenMathLibrary();
state.Environment["print"] = new LuaFunction("print", (c, _) => { var parts = new List<string>(); for (var i = 0; i < c.ArgumentCount; i++) parts.Add(c.GetArgument(i).ToString()); Console.WriteLine(string.Join("\t", parts)); return new ValueTask<int>(c.Return()); });
try
{
    foreach (var arg in args)
    {
        var eq = arg.IndexOf('=');
        if (eq > 0 && !File.Exists(arg))
        {
            var name = arg[..eq];
            var path = arg[(eq + 1)..];
            var source = "gear." + name + " = (function()\n" + File.ReadAllText(path) + "\nend)()";
            await state.DoStringAsync(source, Path.GetFileName(path));
        }
        else
        {
            await state.DoStringAsync(File.ReadAllText(arg), Path.GetFileName(arg));
        }
    }
    Console.WriteLine("OK");
}
catch (Exception e) { Console.WriteLine("FAIL: " + e.Message); Environment.Exit(1); }
