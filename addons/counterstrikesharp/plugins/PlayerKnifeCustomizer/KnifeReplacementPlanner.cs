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
        IReadOnlyList<ushort> list = customKnives is { Count: > 0 }
            ? customKnives
            : KnifeShortcutCycle.DefaultShortcutKnives;

        if (list.Count == 0)
        {
            return new KnifeReplacementPlan(
                CurrentDefIndex: currentDefIndex,
                TargetDefIndex: 0,
                DesignerName: "weapon_knife",
                DisplayName: "Default Knife",
                Preset: new KnifePreset { Paint = 0, Seed = 0, Wear = 0.01f },
                IsVanilla: true,
                IsValid: false,
                ErrorMessage: "Shortcut knives list is empty."
            );
        }

        ushort nextDefIndex = KnifeShortcutCycle.GetNextKnifeDefIndex(currentDefIndex, list);
        if (nextDefIndex == 0)
        {
            return new KnifeReplacementPlan(
                CurrentDefIndex: currentDefIndex,
                TargetDefIndex: 0,
                DesignerName: "weapon_knife",
                DisplayName: "Default Knife",
                Preset: new KnifePreset { Paint = 0, Seed = 0, Wear = 0.01f },
                IsVanilla: true,
                IsValid: false,
                ErrorMessage: "Failed to determine target knife definition index."
            );
        }

        string designerName = KnifeShortcutCycle.GetKnifeDesignerName(nextDefIndex);
        string displayName = KnifeShortcutCycle.GetKnifeDisplayName(nextDefIndex);

        if (!loadout.KnifePresets.TryGetValue(nextDefIndex, out var preset))
        {
            preset = new KnifePreset { Paint = 0, Seed = 0, Wear = 0.01f };
            loadout.KnifePresets[nextDefIndex] = preset;
        }

        bool isVanilla = preset.Paint <= 0;

        return new KnifeReplacementPlan(
            CurrentDefIndex: currentDefIndex,
            TargetDefIndex: nextDefIndex,
            DesignerName: designerName,
            DisplayName: displayName,
            Preset: preset,
            IsVanilla: isVanilla,
            IsValid: true,
            ErrorMessage: string.Empty
        );
    }
}
