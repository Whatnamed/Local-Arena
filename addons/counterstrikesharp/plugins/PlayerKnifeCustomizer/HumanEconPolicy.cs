namespace PlayerKnifeCustomizer;

public enum HumanItemKind { Gun, Knife, Glove }

public static class HumanEconPolicy
{
    public static byte Quality(HumanItemKind kind, bool statTrak, bool souvenir) =>
        souvenir ? (byte)12 : statTrak ? (byte)9 : kind == HumanItemKind.Gun ? (byte)4 : (byte)3;

    public static uint AccountId(ulong steamId) => unchecked((uint)steamId);

}
