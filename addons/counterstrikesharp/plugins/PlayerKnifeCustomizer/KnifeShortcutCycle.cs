namespace PlayerKnifeCustomizer;

public static class KnifeShortcutCycle
{
    // Canonical default knife cycle per docs/PRODUCT-SCOPE.md:
    // Karambit -> Butterfly -> M9 Bayonet -> Bayonet -> Skeleton -> Falchion
    public static readonly ushort[] DefaultShortcutKnives = [
        507, // Karambit (爪子刀)
        515, // Butterfly Knife (蝴蝶刀)
        508, // M9 Bayonet (M9 刺刀)
        500, // Bayonet (刺刀)
        525, // Skeleton Knife (骷髅匕首)
        512, // Falchion Knife (弯刀)
    ];

    public static ushort GetNextKnifeDefIndex(ushort currentDefIndex, IReadOnlyList<ushort>? customKnives = null)
    {
        var list = customKnives != null && customKnives.Count > 0 ? customKnives : DefaultShortcutKnives;
        int idx = -1;
        for (int i = 0; i < list.Count; i++)
        {
            if (list[i] == currentDefIndex)
            {
                idx = i;
                break;
            }
        }
        if (idx == -1) return list[0];
        return list[(idx + 1) % list.Count];
    }

    public static string GetKnifeDesignerName(ushort defIndex) => defIndex switch
    {
        500 => "weapon_bayonet",
        503 => "weapon_knife_css",
        505 => "weapon_knife_flip",
        506 => "weapon_knife_gut",
        507 => "weapon_knife_karambit",
        508 => "weapon_knife_m9_bayonet",
        509 => "weapon_knife_tactical",
        512 => "weapon_knife_falchion",
        514 => "weapon_knife_survival_bowie",
        515 => "weapon_knife_butterfly",
        516 => "weapon_knife_push",
        517 => "weapon_knife_cord",
        518 => "weapon_knife_canis",
        519 => "weapon_knife_ursus",
        520 => "weapon_knife_gypsy_jackknife",
        521 => "weapon_knife_outdoor",
        522 => "weapon_knife_stiletto",
        523 => "weapon_knife_widowmaker",
        525 => "weapon_knife_skeleton",
        526 => "weapon_knife_kukri",
        _ => "weapon_knife",
    };

    public static string GetKnifeDisplayName(ushort defIndex) => defIndex switch
    {
        500 => "Bayonet",
        503 => "Classic Knife",
        505 => "Flip Knife",
        506 => "Gut Knife",
        507 => "Karambit",
        508 => "M9 Bayonet",
        509 => "Huntsman Knife",
        512 => "Falchion Knife",
        514 => "Bowie Knife",
        515 => "Butterfly Knife",
        516 => "Shadow Daggers",
        517 => "Paracord Knife",
        518 => "Survival Knife",
        519 => "Ursus Knife",
        520 => "Navaja Knife",
        521 => "Nomad Knife",
        522 => "Stiletto Knife",
        523 => "Talon Knife",
        525 => "Skeleton Knife",
        526 => "Kukri Knife",
        _ => $"Knife #{defIndex}",
    };
}
