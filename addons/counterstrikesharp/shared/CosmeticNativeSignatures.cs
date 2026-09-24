using System.Runtime.InteropServices;

namespace LocalArena.Cosmetics;

// Windows signatures: Inventory Simulator 3.1.2 (982a859c), 2026-09-23.
// Keep the native bindings used by both cosmetic plugins in one place.
internal static class CosmeticNativeSignatures
{
    internal static string AttributeWriter => RuntimeInformation.IsOSPlatform(OSPlatform.Linux)
        ? "55 48 89 E5 41 57 41 56 41 55 49 89 FD 41 54 53 48 89 F3 48 83 EC ? F3 0F 11 85"
        : "48 89 4C 24 ? 53 41 55 41 56";

    internal static string ItemViewConstructor => RuntimeInformation.IsOSPlatform(OSPlatform.Linux)
        ? "55 48 8D 05 ? ? ? ? 66 0F EF C0 48 89 E5 41 57 45 31 FF"
        : "48 89 5C 24 ? 48 89 6C 24 ? 48 89 74 24 ? 57 41 54 41 55 41 56 41 57 48 83 EC ? 48 8B F9 48 8D 05";

    internal static string SetWearables => RuntimeInformation.IsOSPlatform(OSPlatform.Linux)
        ? "55 48 89 E5 41 57 41 56 41 55 41 54 53 48 89 FB 48 83 EC ? 4C 8B 67 ? 4D 85 E4 0F 84 ? ? ? ? 48 89 DF"
        : "40 55 41 56 48 83 EC ? 48 83 79";

    // CounterStrikeSharp 1.0.371/current main retains a stale Windows tail here.
    // Windows: source2toolkit current gamedata, checked against installed CS2.
    internal static string SetModel => RuntimeInformation.IsOSPlatform(OSPlatform.Linux)
        ? "55 48 89 E5 53 48 89 FB 48 83 EC ? 48 8D 05 ? ? ? ? 48 8B 38 48 8B 07 FF 50 ? 48 89 DF 48 8B 5D ? C9 48 89 C6 E9 ? ? ? ? CC CC CC CC 55"
        : "40 53 48 83 EC ? 48 8B D9 4C 8B C2 48 8B 0D ? ? ? ? 48 8D 54 24 ? 48 8B 01 FF 50 ? 48 8B 54 24 ? 48 8B CB E8 ? ? ? ? 48 83 C4 ? 5B C3 CC CC CC CC CC CC CC CC CC CC CC CC CC CC CC 48 89 5C 24";
}
