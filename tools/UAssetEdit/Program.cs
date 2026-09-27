using UAssetAPI;
using UAssetAPI.UnrealTypes;
using UAssetAPI.Unversioned;

var mode = args.Length > 0 ? args[0] : "";
try
{
    switch (mode)
    {
        case "tojson":
        {
            var asset = Load(args[1], args.Length > 3 ? args[3] : null);
            File.WriteAllText(args[2], asset.SerializeJson(true));
            Console.WriteLine($"wrote {args[2]}");
            return 0;
        }
        case "fromjson":
        {
            var asset = UAsset.DeserializeJson(File.ReadAllText(args[1]));
            if (args.Length > 3) asset.Mappings = new Usmap(args[3]);
            var outPath = Path.GetFullPath(args[2]);
            asset.Write(outPath);
            Console.WriteLine($"wrote {outPath}");
            return 0;
        }
        case "info":
        {
            var asset = Load(args[1], args.Length > 2 ? args[2] : null);
            Console.WriteLine($"exports={asset.Exports.Count} imports={asset.Imports.Count} names={asset.GetNameMapIndexList().Count}");
            foreach (var e in asset.Exports) Console.WriteLine($"  {e.GetType().Name} {e.ObjectName}");
            return 0;
        }
        default:
            Console.Error.WriteLine("usage: UAssetEdit tojson <in.uasset> <out.json> [mappings.usmap]");
            Console.Error.WriteLine("       UAssetEdit fromjson <in.json> <out.uasset> [mappings.usmap]");
            Console.Error.WriteLine("       UAssetEdit info <in.uasset> [mappings.usmap]");
            return 2;
    }
}
catch (Exception ex)
{
    Console.Error.WriteLine("ERROR: " + ex);
    return 1;
}

static UAsset Load(string path, string? usmapPath)
{
    if (!string.IsNullOrEmpty(usmapPath))
        return new UAsset(path, EngineVersion.VER_UE5_5, new Usmap(usmapPath));
    return new UAsset(path, EngineVersion.VER_UE5_5);
}
