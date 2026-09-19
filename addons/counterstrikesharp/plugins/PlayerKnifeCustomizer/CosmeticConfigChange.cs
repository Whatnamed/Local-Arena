using System.Threading;

namespace PlayerKnifeCustomizer;

[Flags]
public enum CosmeticChangeSection
{
    None = 0,
    Knife = 1,
    Gloves = 2,
    Guns = 4,
    Music = 8,
    Agent = 16,
    All = Knife | Gloves | Guns | Music | Agent,
}

/// <summary>
/// What actually changed between the last accepted configuration and a new one,
/// so a live edit only re-applies the region the user touched.
///
/// StatTrak kill counts are deliberately excluded: the plugin writes them back
/// itself after a kill, and treating that as a cosmetic change would make every
/// kill schedule another full re-apply of the player's weapons.
/// </summary>
public sealed record CosmeticConfigDiff(
    CosmeticChangeSection Sections,
    IReadOnlyCollection<ushort> ChangedGunDefIndexes)
{
    public bool ChangesNothing => Sections == CosmeticChangeSection.None;

    public static CosmeticConfigDiff Compute(KnifeConfig before, KnifeConfig after)
    {
        var sections = CosmeticChangeSection.None;
        var guns = new SortedSet<ushort>();

        if (before.Enabled != after.Enabled ||
            before.ApplyToHumanPlayers != after.ApplyToHumanPlayers)
            sections |= CosmeticChangeSection.All;
        if (before.MusicKitId != after.MusicKitId || !before.StickersEnabled && after.StickersEnabled)
            sections |= CosmeticChangeSection.Music;
        if (before.AgentsEnabled != after.AgentsEnabled) sections |= CosmeticChangeSection.Agent;
        if (before.CharmsEnabled != after.CharmsEnabled)
            sections |= CosmeticChangeSection.Knife | CosmeticChangeSection.Guns;

        foreach (CosmeticTeam team in new[] { CosmeticTeam.Ct, CosmeticTeam.T })
        {
            var left = before.Loadouts.For(team);
            var right = after.Loadouts.For(team);
            if (left.DefaultKnifeDefIndex != right.DefaultKnifeDefIndex ||
                !PresetsEqual(left.KnifePresets, right.KnifePresets))
                sections |= CosmeticChangeSection.Knife;
            if (!GloveEquals(left.Glove, right.Glove)) sections |= CosmeticChangeSection.Gloves;
            CollectChangedGuns(left.GunPresets, right.GunPresets, guns);
        }
        if (!before.SharedWeaponLinks.SequenceEqual(after.SharedWeaponLinks) ||
            !PresetsEqual(before.Loadouts.Ct.GunPresets, after.Loadouts.Ct.GunPresets) ||
            !PresetsEqual(before.Loadouts.T.GunPresets, after.Loadouts.T.GunPresets))
            sections |= CosmeticChangeSection.Guns;
        if (guns.Count > 0) sections |= CosmeticChangeSection.Guns;
        if (!string.Equals(before.Loadouts.Ct.AgentModel, after.Loadouts.Ct.AgentModel, StringComparison.Ordinal) ||
            !string.Equals(before.Loadouts.T.AgentModel, after.Loadouts.T.AgentModel, StringComparison.Ordinal))
            sections |= CosmeticChangeSection.Agent;

        return new CosmeticConfigDiff(sections, guns);
    }

    private static void CollectChangedGuns(
        Dictionary<ushort, KnifePreset> before,
        Dictionary<ushort, KnifePreset> after,
        SortedSet<ushort> changed)
    {
        foreach (ushort defIndex in after.Keys.Concat(before.Keys).Distinct())
        {
            bool had = before.TryGetValue(defIndex, out KnifePreset? previous);
            bool has = after.TryGetValue(defIndex, out KnifePreset? current);
            if (had && has && AppearanceEquals(previous!, current!)) continue;
            if (!had && !has) continue;
            changed.Add(defIndex);
        }
    }

    private static bool PresetsEqual(Dictionary<ushort, KnifePreset> before, Dictionary<ushort, KnifePreset> after)
    {
        if (before.Count != after.Count) return false;
        foreach (var (defIndex, preset) in after)
            if (!before.TryGetValue(defIndex, out KnifePreset? previous) || !AppearanceEquals(previous, preset))
                return false;
        return true;
    }

    private static bool GloveEquals(GlovePreset before, GlovePreset after) =>
        before.Enabled == after.Enabled && before.DefIndex == after.DefIndex &&
        before.Paint == after.Paint && before.Seed == after.Seed && before.Wear.Equals(after.Wear);

    private static bool AppearanceEquals(KnifePreset before, KnifePreset after) =>
        before.Paint == after.Paint && before.Seed == after.Seed && before.Wear.Equals(after.Wear) &&
        string.Equals(before.NameTag, after.NameTag, StringComparison.Ordinal) &&
        before.StatTrakEnabled == after.StatTrakEnabled &&
        before.SouvenirEnabled == after.SouvenirEnabled &&
        DecorationsEqual(before, after);

    private static bool DecorationsEqual(KnifePreset before, KnifePreset after)
    {
        var left = before.Stickers ?? [];
        var right = after.Stickers ?? [];
        if (left.Count != right.Count) return false;
        for (int index = 0; index < left.Count; index++)
            if (!left[index].ValueEquals(right[index])) return false;
        return before.Charm is null
            ? after.Charm is null
            : after.Charm is not null && before.Charm.ValueEquals(after.Charm);
    }
}

/// <summary>
/// Collapses the burst of file-system notifications a single atomic replace
/// produces into at most one reload task. A Panel save can raise several
/// Changed/Created/Renamed events, and the plugin's own StatTrak write-back
/// raises more; without this, each event would queue another reload.
/// </summary>
public sealed class ConfigReloadGate
{
    private int _inFlight;
    private int _signals;

    public ConfigReloadGate(int debounceMilliseconds)
    {
        if (debounceMilliseconds <= 0)
            throw new ArgumentOutOfRangeException(nameof(debounceMilliseconds));
        DebounceMilliseconds = debounceMilliseconds;
    }

    public int DebounceMilliseconds { get; }

    /// <summary>True when the caller must arm the single debounce timer.</summary>
    public bool Signal()
    {
        _signals++;
        return Interlocked.CompareExchange(ref _inFlight, 1, 0) == 0;
    }

    /// <summary>Timer fired: take the accumulated signals if the plugin is still loaded.</summary>
    public bool TryBeginWork()
    {
        Interlocked.Exchange(ref _inFlight, 0);
        return Interlocked.Exchange(ref _signals, 0) > 0;
    }

    /// <summary>True when a save landed while this reload was running and needs another pass.</summary>
    public bool HasPendingWork() => Volatile.Read(ref _signals) > 0;

    public void Reset()
    {
        Interlocked.Exchange(ref _inFlight, 0);
        Interlocked.Exchange(ref _signals, 0);
    }
}
