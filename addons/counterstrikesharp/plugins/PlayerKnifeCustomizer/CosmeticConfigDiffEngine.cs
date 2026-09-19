using System.Text.Json;

namespace PlayerKnifeCustomizer;

[Flags]
public enum CosmeticChangeSection
{
    None = 0,
    Knife = 1 << 0,
    Gloves = 1 << 1,
    Guns = 1 << 2,
    Agents = 1 << 3,
    Music = 1 << 4,
}

public sealed class CosmeticDiff
{
    public CosmeticChangeSection Sections { get; set; } = CosmeticChangeSection.None;
    public HashSet<ushort> ChangedGunDefIndexes { get; } = new();

    public bool HasChanges => Sections != CosmeticChangeSection.None || ChangedGunDefIndexes.Count > 0;
}

public static class CosmeticConfigDiffEngine
{
    public static bool GloveEquals(GlovePreset? a, GlovePreset? b)
    {
        if (ReferenceEquals(a, b)) return true;
        if (a == null || b == null) return false;
        return a.Enabled == b.Enabled
            && a.DefIndex == b.DefIndex
            && a.Paint == b.Paint
            && a.Seed == b.Seed
            && Math.Abs(a.Wear - b.Wear) < 0.000001f;
    }

    public static CosmeticDiff Diff(KnifeConfig previous, KnifeConfig current)
    {
        var diff = new CosmeticDiff();

        // 1. Knife check
        if (previous.Loadouts.Ct.DefaultKnifeDefIndex != current.Loadouts.Ct.DefaultKnifeDefIndex ||
            previous.Loadouts.T.DefaultKnifeDefIndex != current.Loadouts.T.DefaultKnifeDefIndex ||
            !KnivesEqual(previous.Loadouts.Ct.KnifePresets, current.Loadouts.Ct.KnifePresets) ||
            !KnivesEqual(previous.Loadouts.T.KnifePresets, current.Loadouts.T.KnifePresets))
        {
            diff.Sections |= CosmeticChangeSection.Knife;
        }

        // 2. Glove check
        if (!GloveEquals(previous.Loadouts.Ct.Glove, current.Loadouts.Ct.Glove) ||
            !GloveEquals(previous.Loadouts.T.Glove, current.Loadouts.T.Glove))
        {
            diff.Sections |= CosmeticChangeSection.Gloves;
        }

        // 3. Gun presets check - identify exactly which weapon defindexes changed
        var allGunDefs = new HashSet<ushort>(previous.Loadouts.Ct.GunPresets.Keys);
        allGunDefs.UnionWith(current.Loadouts.Ct.GunPresets.Keys);
        allGunDefs.UnionWith(previous.Loadouts.T.GunPresets.Keys);
        allGunDefs.UnionWith(current.Loadouts.T.GunPresets.Keys);

        foreach (var def in allGunDefs)
        {
            bool ctChanged = !PresetEquals(
                previous.Loadouts.Ct.GunPresets.GetValueOrDefault(def),
                current.Loadouts.Ct.GunPresets.GetValueOrDefault(def)
            );
            bool tChanged = !PresetEquals(
                previous.Loadouts.T.GunPresets.GetValueOrDefault(def),
                current.Loadouts.T.GunPresets.GetValueOrDefault(def)
            );

            if (ctChanged || tChanged)
            {
                diff.ChangedGunDefIndexes.Add(def);
            }
        }

        if (diff.ChangedGunDefIndexes.Count > 0)
        {
            diff.Sections |= CosmeticChangeSection.Guns;
        }

        // 4. Agent models check
        if (previous.AgentsEnabled != current.AgentsEnabled ||
            previous.Loadouts.Ct.AgentModel != current.Loadouts.Ct.AgentModel ||
            previous.Loadouts.T.AgentModel != current.Loadouts.T.AgentModel)
        {
            diff.Sections |= CosmeticChangeSection.Agents;
        }

        // 5. Music kit check
        if (previous.MusicKitId != current.MusicKitId)
        {
            diff.Sections |= CosmeticChangeSection.Music;
        }

        return diff;
    }

    private static bool KnivesEqual(Dictionary<ushort, KnifePreset> a, Dictionary<ushort, KnifePreset> b)
    {
        if (a.Count != b.Count) return false;
        foreach (var (key, valA) in a)
        {
            if (!b.TryGetValue(key, out var valB)) return false;
            if (!valA.ValueEquals(valB)) return false;
        }
        return true;
    }

    private static bool PresetEquals(KnifePreset? a, KnifePreset? b)
    {
        if (ReferenceEquals(a, b)) return true;
        if (a == null || b == null) return false;
        return a.ValueEquals(b);
    }
}

public sealed class DebounceScheduler : IDisposable
{
    private readonly object _lock = new();
    private readonly int _delayMs;
    private CancellationTokenSource? _cts;
    private bool _disposed;

    public DebounceScheduler(int delayMs = 150)
    {
        _delayMs = delayMs;
    }

    public void Schedule(Action action)
    {
        lock (_lock)
        {
            if (_disposed) return;
            _cts?.Cancel();
            _cts?.Dispose();
            _cts = new CancellationTokenSource();
            var token = _cts.Token;

            Task.Delay(_delayMs, token).ContinueWith(t =>
            {
                if (!t.IsCanceled && !token.IsCancellationRequested)
                {
                    lock (_lock)
                    {
                        if (!_disposed && !token.IsCancellationRequested)
                        {
                            action();
                        }
                    }
                }
            }, TaskScheduler.Default);
        }
    }

    public void Dispose()
    {
        lock (_lock)
        {
            _disposed = true;
            _cts?.Cancel();
            _cts?.Dispose();
            _cts = null;
        }
    }
}
