namespace PlayerKnifeCustomizer;

public sealed record KnifeTargetPlan(
    ushort CurrentDefIndex,
    ushort TargetDefIndex,
    string DisplayName,
    KnifePreset Preset,
    bool IsVanilla,
    bool IsValid,
    string ErrorMessage
);

public static class KnifeTargetPlanner
{
    public static KnifeTargetPlan Plan(
        ushort currentDefIndex,
        IReadOnlyList<ushort>? customKnives,
        TeamLoadout loadout)
    {
        var source = customKnives is { Count: > 0 }
            ? customKnives
            : KnifeShortcutCycle.DefaultShortcutKnives;
        var list = KnifeShortcutCycle.Normalize(source);
        if (list.Count == 0)
            return Invalid(currentDefIndex, "The shortcut knives list is empty.");

        ushort targetDefIndex = KnifeShortcutCycle.GetNextKnifeDefIndex(currentDefIndex, list);
        if (!KnifeShortcutCycle.IsSupported(targetDefIndex))
            return Invalid(currentDefIndex, "The target knife definition is unavailable.");

        return Create(currentDefIndex, targetDefIndex, loadout);
    }

    public static KnifeTargetPlan? PlanDefault(ushort currentDefIndex, ushort defaultDefIndex, TeamLoadout loadout)
    {
        if (defaultDefIndex > 0 && !KnifeShortcutCycle.IsSupported(defaultDefIndex)) return null;
        ushort targetDefIndex = defaultDefIndex > 0 ? defaultDefIndex : currentDefIndex;
        if (!KnifeShortcutCycle.IsSupported(targetDefIndex)) return null;
        if (targetDefIndex == currentDefIndex && !loadout.KnifePresets.ContainsKey(targetDefIndex))
            return null;
        return Create(currentDefIndex, targetDefIndex, loadout);
    }

    private static KnifeTargetPlan Create(ushort currentDefIndex, ushort targetDefIndex, TeamLoadout loadout)
    {
        // Always resolve the target knife's own preset, without mutating the loadout.
        KnifePreset preset = loadout.KnifePresets.TryGetValue(targetDefIndex, out var configured) && configured.Paint > 0
            ? configured.Clone()
            : new KnifePreset { Paint = 0, Seed = 0, Wear = 0.01f };
        return new KnifeTargetPlan(
            CurrentDefIndex: currentDefIndex,
            TargetDefIndex: targetDefIndex,
            DisplayName: KnifeShortcutCycle.GetKnifeDisplayName(targetDefIndex),
            Preset: preset,
            IsVanilla: preset.Paint <= 0,
            IsValid: true,
            ErrorMessage: string.Empty);
    }

    private static KnifeTargetPlan Invalid(ushort currentDefIndex, string error) =>
        new(
            CurrentDefIndex: currentDefIndex,
            TargetDefIndex: 0,
            DisplayName: "Default Knife",
            Preset: new KnifePreset { Paint = 0, Seed = 0, Wear = 0.01f },
            IsVanilla: true,
            IsValid: false,
            ErrorMessage: error);
}
