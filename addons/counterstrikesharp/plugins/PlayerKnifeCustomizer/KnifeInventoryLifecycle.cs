namespace PlayerKnifeCustomizer;

public static class KnifeInventoryLifecycle
{
    public static bool TryDetach(Action detach, Func<bool> isReferenced)
    {
        detach();
        return !isReferenced();
    }

    // RemovePlayerItem is distinct from UTIL_Remove. Never destroy an entity
    // while MyWeapons/ActiveWeapon still references it, even if detachment fails.
    public static bool TryRetire(Action detach, Func<bool> isReferenced, Action destroy)
    {
        detach();
        if (isReferenced()) return false;
        destroy();
        return true;
    }
}
