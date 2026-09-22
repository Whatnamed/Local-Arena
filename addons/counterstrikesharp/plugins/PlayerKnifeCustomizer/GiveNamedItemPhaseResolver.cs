namespace PlayerKnifeCustomizer;

public static class GiveNamedItemPhaseResolver
{
    public static CosmeticApplyPhase Resolve(string? designerName, ushort defIndex)
    {
        if (IsKnife(designerName, defIndex)) return CosmeticApplyPhase.Knife;
        if (!string.IsNullOrWhiteSpace(designerName) || defIndex != 0)
            return CosmeticApplyPhase.Guns;

        // A null return can be a hook/API timing issue. Keep both item phases
        // pending so a late knife or gun entity is covered by the bounded retry.
        return CosmeticApplyPhase.Knife | CosmeticApplyPhase.Guns;
    }

    private static bool IsKnife(string? designerName, ushort defIndex) =>
        KnifeShortcutCycle.IsSupported(defIndex) ||
        (!string.IsNullOrWhiteSpace(designerName) &&
         (designerName.Contains("knife", StringComparison.OrdinalIgnoreCase) ||
          designerName.Contains("bayonet", StringComparison.OrdinalIgnoreCase)));
}
