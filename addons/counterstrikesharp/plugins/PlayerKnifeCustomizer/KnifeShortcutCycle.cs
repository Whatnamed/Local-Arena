namespace PlayerKnifeCustomizer;

public static class KnifeShortcutCycle
{
    // The Panel writes an optional custom list. An empty list means that the
    // shortcut is disabled, while the command-side fallback remains stable for
    // configs written by older Panel builds.
    public static readonly ushort[] DefaultShortcutKnives =
    [
        507, // Karambit
        515, // Butterfly Knife
        508, // M9 Bayonet
        500, // Bayonet
        525, // Skeleton Knife
        512, // Falchion Knife
    ];

    private static readonly IReadOnlyDictionary<ushort, string> KnifeCatalog =
        new Dictionary<ushort, string>
        {
            [500] = "Bayonet",
            [503] = "Classic Knife",
            [505] = "Flip Knife",
            [506] = "Gut Knife",
            [507] = "Karambit",
            [508] = "M9 Bayonet",
            [509] = "Huntsman Knife",
            [512] = "Falchion Knife",
            [514] = "Bowie Knife",
            [515] = "Butterfly Knife",
            [516] = "Shadow Daggers",
            [517] = "Paracord Knife",
            [518] = "Survival Knife",
            [519] = "Ursus Knife",
            [520] = "Navaja Knife",
            [521] = "Nomad Knife",
            [522] = "Stiletto Knife",
            [523] = "Talon Knife",
            [525] = "Skeleton Knife",
            [526] = "Kukri Knife",
        };

    public static bool IsSupported(ushort defIndex) => KnifeCatalog.ContainsKey(defIndex);

    public static ushort GetNextKnifeDefIndex(
        ushort currentDefIndex,
        IReadOnlyList<ushort>? customKnives = null)
    {
        var list = Normalize(customKnives is { Count: > 0 } ? customKnives : DefaultShortcutKnives);
        if (list.Count == 0) return 0;
        int index = -1;
        for (int i = 0; i < list.Count; i++)
        {
            if (list[i] == currentDefIndex)
            {
                index = i;
                break;
            }
        }
        return list[(index + 1) % list.Count];
    }

    public static IReadOnlyList<ushort> Normalize(IReadOnlyList<ushort>? knives)
    {
        var result = new List<ushort>();
        foreach (ushort defIndex in knives ?? [])
        {
            if (IsSupported(defIndex) && !result.Contains(defIndex))
                result.Add(defIndex);
        }
        return result;
    }

    public static string GetKnifeDisplayName(ushort defIndex) =>
        KnifeCatalog.TryGetValue(defIndex, out var display) ? display : $"Knife #{defIndex}";

}
