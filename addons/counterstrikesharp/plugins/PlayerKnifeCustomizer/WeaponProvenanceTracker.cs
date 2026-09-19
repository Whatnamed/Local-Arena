namespace PlayerKnifeCustomizer;

public enum ProvenanceAction
{
    ApplyPreset,
    PreserveExisting,
    Ignore,
}

public readonly record struct ProvenanceDecision(
    ProvenanceAction Action,
    bool IsOwnedByPlayer,
    string Reason
);

public sealed class WeaponProvenanceTracker
{
    private readonly record struct EntityRecord(
        nint Handle,
        uint Index,
        ushort DefIndex,
        nint OwnerPlayerHandle,
        int OwnerTeam,
        bool AppliedPreset,
        long Generation
    );

    private readonly Dictionary<(nint Handle, uint Index), EntityRecord> _entities = new();
    private long _nextGeneration;

    public int TrackedCount => _entities.Count;

    public long RegisterGrantedWeapon(nint playerHandle, int team, nint weaponHandle, uint weaponIndex, ushort defIndex)
    {
        if (playerHandle == nint.Zero || weaponHandle == nint.Zero)
            return 0;

        long gen = ++_nextGeneration;
        var record = new EntityRecord(
            Handle: weaponHandle,
            Index: weaponIndex,
            DefIndex: defIndex,
            OwnerPlayerHandle: playerHandle,
            OwnerTeam: team,
            AppliedPreset: false,
            Generation: gen
        );

        _entities[(weaponHandle, weaponIndex)] = record;
        return gen;
    }

    public ProvenanceDecision EvaluatePickup(nint playerHandle, int team, nint weaponHandle, uint weaponIndex, ushort defIndex)
    {
        if (playerHandle == nint.Zero || weaponHandle == nint.Zero)
            return new ProvenanceDecision(ProvenanceAction.Ignore, false, "invalid handles");

        var key = (weaponHandle, weaponIndex);
        if (_entities.TryGetValue(key, out var record))
        {
            if (record.OwnerPlayerHandle == playerHandle && record.DefIndex == defIndex)
            {
                // Previously owned and dropped weapon: keep its already-applied cosmetic state
                return new ProvenanceDecision(
                    ProvenanceAction.PreserveExisting,
                    true,
                    "re-picked owned weapon; existing cosmetics preserved"
                );
            }

            // Entity belongs to someone else (or different defIndex reuse)
            return new ProvenanceDecision(
                ProvenanceAction.PreserveExisting,
                false,
                "picked up foreign weapon; foreign cosmetics preserved"
            );
        }

        // Completely unknown ground entity (e.g. spawned by map or dropped by bot before tracking)
        return new ProvenanceDecision(
            ProvenanceAction.PreserveExisting,
            false,
            "untracked ground weapon; preserved as foreign"
        );
    }

    public bool IsEligibleForApply(nint playerHandle, nint weaponHandle, uint weaponIndex, ushort defIndex)
    {
        if (playerHandle == nint.Zero || weaponHandle == nint.Zero)
            return false;

        var key = (weaponHandle, weaponIndex);
        if (!_entities.TryGetValue(key, out var record))
            return false;

        return record.OwnerPlayerHandle == playerHandle && record.DefIndex == defIndex;
    }

    public bool IsEligibleForLiveReload(nint playerHandle, nint weaponHandle, uint weaponIndex, ushort defIndex)
    {
        if (playerHandle == nint.Zero || weaponHandle == nint.Zero)
            return false;

        var key = (weaponHandle, weaponIndex);
        if (!_entities.TryGetValue(key, out var record))
            return false;

        // Only weapons that were explicitly granted to this player may be refreshed live
        return record.OwnerPlayerHandle == playerHandle && record.DefIndex == defIndex;
    }

    public void RecordApplied(nint weaponHandle, uint weaponIndex)
    {
        var key = (weaponHandle, weaponIndex);
        if (_entities.TryGetValue(key, out var record))
        {
            _entities[key] = record with { AppliedPreset = true };
        }
    }

    public bool UnregisterEntity(nint weaponHandle, uint weaponIndex)
    {
        return _entities.Remove((weaponHandle, weaponIndex));
    }

    public int ClearPlayer(nint playerHandle)
    {
        if (playerHandle == nint.Zero)
            return 0;

        var keysToRemove = _entities
            .Where(pair => pair.Value.OwnerPlayerHandle == playerHandle)
            .Select(pair => pair.Key)
            .ToList();

        foreach (var key in keysToRemove)
        {
            _entities.Remove(key);
        }

        return keysToRemove.Count;
    }

    public void ClearAll()
    {
        _entities.Clear();
    }
}
