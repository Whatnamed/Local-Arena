namespace PlayerKnifeCustomizer;

public sealed record KnifeReplacementPlan(
    ushort CurrentDefIndex,
    ushort TargetDefIndex,
    string DesignerName,
    string DisplayName,
    KnifePreset Preset,
    bool IsVanilla,
    bool IsValid,
    string ErrorMessage
);

public static class KnifeReplacementPlanner
{
    public static KnifeReplacementPlan Plan(
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

        // The planner must be side-effect free. In particular, a failed GiveNamedItem
        // must not create a phantom preset that changes the next cycle.
        KnifePreset preset = loadout.KnifePresets.TryGetValue(targetDefIndex, out var configured)
            ? configured.Clone()
            : new KnifePreset { Paint = 0, Seed = 0, Wear = 0.01f };

        return new KnifeReplacementPlan(
            CurrentDefIndex: currentDefIndex,
            TargetDefIndex: targetDefIndex,
            DesignerName: KnifeShortcutCycle.GetKnifeDesignerName(targetDefIndex),
            DisplayName: KnifeShortcutCycle.GetKnifeDisplayName(targetDefIndex),
            Preset: preset,
            IsVanilla: preset.Paint <= 0,
            IsValid: true,
            ErrorMessage: string.Empty);
    }

    private static KnifeReplacementPlan Invalid(ushort currentDefIndex, string error) =>
        new(
            CurrentDefIndex: currentDefIndex,
            TargetDefIndex: 0,
            DesignerName: "weapon_knife",
            DisplayName: "Default Knife",
            Preset: new KnifePreset { Paint = 0, Seed = 0, Wear = 0.01f },
            IsVanilla: true,
            IsValid: false,
            ErrorMessage: error);
}
