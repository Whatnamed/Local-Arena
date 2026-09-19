namespace PlayerKnifeCustomizer;

/// <summary>
/// Tracks which weapon entities this plugin has itself granted to a player, so a
/// preset is only ever written onto a weapon the player owns through the normal
/// purchase, spawn or grant path. A weapon picked up off the ground was created by
/// someone else and keeps the appearance it already has.
///
/// Entries are keyed by entity handle and validated against the identity that was
/// recorded, because a freed handle can come back as a different weapon. When the
/// identity does not match, the answer is "not ours", which is the safe direction:
/// an unrecognised entity is left alone.
/// </summary>
public sealed class WeaponProvenance
{
    private readonly Dictionary<nint, (ushort DefIndex, string Designer)> _granted = new();
    private readonly Dictionary<nint, HashSet<nint>> _byPlayer = new();

    public int Count => _granted.Count;

    public void RecordGrant(nint playerHandle, nint weaponHandle, ushort defIndex, string designerName)
    {
        if (weaponHandle == nint.Zero) return;
        _granted[weaponHandle] = (defIndex, designerName ?? string.Empty);
        if (!_byPlayer.TryGetValue(playerHandle, out HashSet<nint>? handles))
        {
            handles = [];
            _byPlayer[playerHandle] = handles;
        }
        handles.Add(weaponHandle);
    }

    public bool IsOwned(nint weaponHandle, ushort defIndex, string designerName) =>
        _granted.TryGetValue(weaponHandle, out (ushort DefIndex, string Designer) recorded) &&
        recorded.DefIndex == defIndex &&
        string.Equals(recorded.Designer, designerName ?? string.Empty, StringComparison.Ordinal);

    public void Forget(nint weaponHandle) => _granted.Remove(weaponHandle);

    public void ForgetPlayer(nint playerHandle)
    {
        if (!_byPlayer.Remove(playerHandle, out HashSet<nint>? handles)) return;
        foreach (nint weaponHandle in handles) _granted.Remove(weaponHandle);
    }

    public void Clear()
    {
        _granted.Clear();
        _byPlayer.Clear();
    }
}
