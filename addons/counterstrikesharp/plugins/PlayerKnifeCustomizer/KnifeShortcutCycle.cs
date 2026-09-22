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

    private static readonly IReadOnlyDictionary<ushort, (string Designer, string Display)> KnifeCatalog =
        new Dictionary<ushort, (string Designer, string Display)>
        {
            [500] = ("weapon_bayonet", "Bayonet"),
            [503] = ("weapon_knife_css", "Classic Knife"),
            [505] = ("weapon_knife_flip", "Flip Knife"),
            [506] = ("weapon_knife_gut", "Gut Knife"),
            [507] = ("weapon_knife_karambit", "Karambit"),
            [508] = ("weapon_knife_m9_bayonet", "M9 Bayonet"),
            [509] = ("weapon_knife_tactical", "Huntsman Knife"),
            [512] = ("weapon_knife_falchion", "Falchion Knife"),
            [514] = ("weapon_knife_survival_bowie", "Bowie Knife"),
            [515] = ("weapon_knife_butterfly", "Butterfly Knife"),
            [516] = ("weapon_knife_push", "Shadow Daggers"),
            [517] = ("weapon_knife_cord", "Paracord Knife"),
            [518] = ("weapon_knife_canis", "Survival Knife"),
            [519] = ("weapon_knife_ursus", "Ursus Knife"),
            [520] = ("weapon_knife_gypsy_jackknife", "Navaja Knife"),
            [521] = ("weapon_knife_outdoor", "Nomad Knife"),
            [522] = ("weapon_knife_stiletto", "Stiletto Knife"),
            [523] = ("weapon_knife_widowmaker", "Talon Knife"),
            [525] = ("weapon_knife_skeleton", "Skeleton Knife"),
            [526] = ("weapon_knife_kukri", "Kukri Knife"),
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

    public static string GetKnifeDesignerName(ushort defIndex) =>
        KnifeCatalog.TryGetValue(defIndex, out var entry) ? entry.Designer : "weapon_knife";

    public static string GetKnifeDisplayName(ushort defIndex) =>
        KnifeCatalog.TryGetValue(defIndex, out var entry) ? entry.Display : $"Knife #{defIndex}";

    public static string GetBaseDesignerName(CosmeticTeam team) =>
        team == CosmeticTeam.T ? "weapon_knife_t" : "weapon_knife";
}
