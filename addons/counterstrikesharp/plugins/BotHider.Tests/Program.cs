using System;
using System.IO;
using System.IO.MemoryMappedFiles;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using BotHiderApi;
using BotHiderImpl;

namespace BotHider.Tests;

internal static class Program
{
    private const string MappingName = "CS2BotHider_Slots";
    private const uint ExpectedMagic = 0x44494842; // 'BHID'
    private const uint ExpectedVersion = 1;
    private const int ExpectedMaxSlots = 64;
    private const int ExpectedTotalSize = 1_064_960;

    public static int Main()
    {
        Console.WriteLine("=== BotHider v0.5 Contract Tests ===");

        TestApiContractReflection();
        TestSharedMemoryConstantsAndOffsets();
        TestSharedMemoryLiveWireOpcodes();

        Console.WriteLine("ALL BotHider Contract Tests PASSED!");
        return 0;
    }

    private static void TestApiContractReflection()
    {
        Console.Write("Testing IBotHiderApi reflection contract... ");

        var apiType = typeof(IBotHiderApi);

        // 1. Verify SetIdentityMode exists and SetDisguise does NOT exist
        var setIdentityMethod = apiType.GetMethod("SetIdentityMode", [typeof(BotIdentityMode)]);
        if (setIdentityMethod == null || setIdentityMethod.ReturnType != typeof(bool))
            throw new Exception("IBotHiderApi.SetIdentityMode(BotIdentityMode) is missing or has wrong signature!");

        var setDisguiseMethod = apiType.GetMethod("SetDisguise");
        if (setDisguiseMethod != null)
            throw new Exception("IBotHiderApi still contains obsolete SetDisguise method!");

        // 2. Verify RequestRebuild is NOT present on IBotHiderApi or SharedMemoryClient
        if (apiType.GetMethod("RequestRebuild") != null)
            throw new Exception("IBotHiderApi still contains obsolete RequestRebuild method!");

        var clientType = typeof(SharedMemoryClient);
        if (clientType.GetMethod("RequestRebuild") != null)
            throw new Exception("SharedMemoryClient still contains obsolete RequestRebuild method!");

        // 3. Verify BotIdentityMode enum values (Player = 0, Bot = 1)
        if ((int)BotIdentityMode.Player != 0)
            throw new Exception($"BotIdentityMode.Player must be 0, got {(int)BotIdentityMode.Player}");
        if ((int)BotIdentityMode.Bot != 1)
            throw new Exception($"BotIdentityMode.Bot must be 1, got {(int)BotIdentityMode.Bot}");

        // 4. Verify BotHiderContract
        if (BotHiderContract.MaxPlayerNameUtf8Bytes != 31)
            throw new Exception($"MaxPlayerNameUtf8Bytes must be 31, got {BotHiderContract.MaxPlayerNameUtf8Bytes}");

        Console.WriteLine("PASS");
    }

    private static void TestSharedMemoryConstantsAndOffsets()
    {
        Console.Write("Testing Shared Memory wire offsets and capacity... ");

        var clientType = typeof(SharedMemoryClient);

        uint magic = (uint)GetConst(clientType, "Magic");
        uint version = (uint)GetConst(clientType, "Version");
        int maxSlots = (int)GetConst(clientType, "MaxSlots");
        int totalSize = (int)GetConst(clientType, "TotalSize");

        if (magic != ExpectedMagic) throw new Exception($"Magic mismatch: {magic:X8} != {ExpectedMagic:X8}");
        if (version != ExpectedVersion) throw new Exception($"Version mismatch: {version} != {ExpectedVersion}");
        if (maxSlots != ExpectedMaxSlots) throw new Exception($"MaxSlots mismatch: {maxSlots} != {ExpectedMaxSlots}");
        if (totalSize != ExpectedTotalSize) throw new Exception($"TotalSize mismatch: {totalSize} != {ExpectedTotalSize}");

        // Data region offsets
        AssertConst(clientType, "OffMagic", 0);
        AssertConst(clientType, "OffVersion", 4);
        AssertConst(clientType, "OffMaxSlots", 8);
        AssertConst(clientType, "OffSlotState", 16);
        AssertConst(clientType, "OffSyntheticSid", 80);
        AssertConst(clientType, "OffPersonaName", 592);

        // Command region offsets
        AssertConst(clientType, "OffWriteIdx", 2640);
        AssertConst(clientType, "OffReadIdx", 2644);
        AssertConst(clientType, "OffCmds", 2648);
        AssertConst(clientType, "CmdSize", 48);
        AssertConst(clientType, "CmdCount", 64);

        // Extra data region offsets
        AssertConst(clientType, "OffCurrentPing", 5720);
        AssertConst(clientType, "OffCrosshair", 5976);
        AssertConst(clientType, "CrosshairLen", 64);

        // Signature region offsets
        AssertConst(clientType, "OffSigCount", 10072);
        AssertConst(clientType, "OffSigEntries", 10080);
        AssertConst(clientType, "MaxSigs", 8);
        AssertConst(clientType, "SigEntrySize", 40);

        // Scoreboard flair and base identities
        AssertConst(clientType, "OffScoreboardFlair", 10400);
        AssertConst(clientType, "OffBaseSyntheticSid", 10656);
        AssertConst(clientType, "OffBasePersonaName", 11168);
        AssertConst(clientType, "OffIncarnation", 13216);

        // Custom avatar region
        AssertConst(clientType, "OffAvatarSequence", 13728);
        AssertConst(clientType, "OffAvatarLength", 13984);
        AssertConst(clientType, "OffAvatarIncarnation", 14240);
        AssertConst(clientType, "OffAvatarApplied", 14752);
        AssertConst(clientType, "OffAvatarAppliedSid", 14816);
        AssertConst(clientType, "OffAvatarData", 16384);
        AssertConst(clientType, "AvatarMaxBytes", 16 * 1024);

        // Verify total size invariant: OffAvatarData + MaxSlots * AvatarMaxBytes == TotalSize
        int calculatedTotal = 16384 + (64 * 16 * 1024);
        if (calculatedTotal != ExpectedTotalSize)
            throw new Exception($"Calculated total size {calculatedTotal} != ExpectedTotalSize {ExpectedTotalSize}");

        // Opcode semantics constants
        AssertConst(clientType, "CmdSetSteamId", (byte)1);
        AssertConst(clientType, "CmdSetPersona", (byte)2);
        AssertConst(clientType, "CmdSetIdentityMode", (byte)3);
        AssertConst(clientType, "CmdSetNameSource", (byte)7);

        // Confirm retired commands are NOT defined
        if (clientType.GetField("CmdRebuild", BindingFlags.NonPublic | BindingFlags.Static) != null)
            throw new Exception("CmdRebuild constant is still present!");
        if (clientType.GetField("CmdSetDisguise", BindingFlags.NonPublic | BindingFlags.Static) != null)
            throw new Exception("CmdSetDisguise constant is still present!");

        Console.WriteLine("PASS");
    }

    private static void TestSharedMemoryLiveWireOpcodes()
    {
        Console.Write("Testing Live Shared Memory wire write & opcode serialization... ");

        // Create an in-memory mapped file simulating BotHider's shared memory
        using var mmf = MemoryMappedFile.CreateOrOpen(MappingName, ExpectedTotalSize, MemoryMappedFileAccess.ReadWrite);
        using var view = mmf.CreateViewAccessor(0, ExpectedTotalSize, MemoryMappedFileAccess.ReadWrite);

        // Initialize header
        view.Write(0, ExpectedMagic);
        view.Write(4, ExpectedVersion);
        view.Write(8, (uint)ExpectedMaxSlots);
        view.Write(2640, 0U); // WriteIdx
        view.Write(2644, 0U); // ReadIdx

        using var client = new SharedMemoryClient();
        if (!client.TryConnect())
            throw new Exception("SharedMemoryClient.TryConnect() failed to connect to simulated mapping!");

        // 1. Test SetIdentityMode(Player) -> CmdSetIdentityMode = 3, slot = 255, steamId = 0 (Player)
        bool ok = client.SetIdentityMode(BotIdentityMode.Player);
        if (!ok) throw new Exception("SetIdentityMode(Player) returned false!");
        VerifyCommand(view, 0, expectedType: 3, expectedSlot: 255, expectedSid: 0UL, expectedName: "");

        // 2. Test SetIdentityMode(Bot) -> CmdSetIdentityMode = 3, slot = 255, steamId = 1 (Bot)
        ok = client.SetIdentityMode(BotIdentityMode.Bot);
        if (!ok) throw new Exception("SetIdentityMode(Bot) returned false!");
        VerifyCommand(view, 1, expectedType: 3, expectedSlot: 255, expectedSid: 1UL, expectedName: "");

        // 3. Test SetNameSource(true) -> CmdSetNameSource = 7, slot = 255, steamId = 1
        ok = client.SetNameSource(true);
        if (!ok) throw new Exception("SetNameSource(true) returned false!");
        VerifyCommand(view, 2, expectedType: 7, expectedSlot: 255, expectedSid: 1UL, expectedName: "");

        // 4. Test SetNameSource(false) -> CmdSetNameSource = 7, slot = 255, steamId = 0
        ok = client.SetNameSource(false);
        if (!ok) throw new Exception("SetNameSource(false) returned false!");
        VerifyCommand(view, 3, expectedType: 7, expectedSlot: 255, expectedSid: 0UL, expectedName: "");

        // 5. Test SetBotSteamId(5, 76561198000000001UL) -> CmdSetSteamId = 1, slot = 5
        ok = client.SetBotSteamId(5, 76561198000000001UL);
        if (!ok) throw new Exception("SetBotSteamId returned false!");
        VerifyCommand(view, 4, expectedType: 1, expectedSlot: 5, expectedSid: 76561198000000001UL, expectedName: "");

        // 6. Test SetPersonaName(5, "NiKo") -> CmdSetPersona = 2, slot = 5, name = "NiKo"
        ok = client.SetPersonaName(5, "NiKo");
        if (!ok) throw new Exception("SetPersonaName returned false!");
        VerifyCommand(view, 5, expectedType: 2, expectedSlot: 5, expectedSid: 0UL, expectedName: "NiKo");

        // Verify total write count
        uint finalWriteIdx = view.ReadUInt32(2640);
        if (finalWriteIdx != 6)
            throw new Exception($"Expected 6 commands posted, got {finalWriteIdx}");

        Console.WriteLine("PASS");
    }

    private static void VerifyCommand(MemoryMappedViewAccessor view, int cmdIndex,
                                      byte expectedType, byte expectedSlot, ulong expectedSid, string expectedName)
    {
        int baseOff = 2648 + cmdIndex * 48;
        byte type = view.ReadByte(baseOff + 0);
        byte slot = view.ReadByte(baseOff + 1);
        ulong sid = view.ReadUInt64(baseOff + 8);

        byte[] nameBuf = new byte[32];
        view.ReadArray(baseOff + 16, nameBuf, 0, 32);
        int len = Array.IndexOf(nameBuf, (byte)0);
        if (len < 0) len = 32;
        string name = Encoding.UTF8.GetString(nameBuf, 0, len);

        if (type != expectedType)
            throw new Exception($"Cmd[{cmdIndex}] type {type} != expected {expectedType}");
        if (slot != expectedSlot)
            throw new Exception($"Cmd[{cmdIndex}] slot {slot} != expected {expectedSlot}");
        if (sid != expectedSid)
            throw new Exception($"Cmd[{cmdIndex}] sid {sid} != expected {expectedSid}");
        if (!string.Equals(name, expectedName, StringComparison.Ordinal))
            throw new Exception($"Cmd[{cmdIndex}] name '{name}' != expected '{expectedName}'");
    }

    private static object GetConst(Type type, string fieldName)
    {
        var f = type.GetField(fieldName, BindingFlags.NonPublic | BindingFlags.Public | BindingFlags.Static);
        if (f == null) throw new Exception($"Constant field {fieldName} not found on {type.Name}");
        return f.GetValue(null)!;
    }

    private static void AssertConst(Type type, string fieldName, object expected)
    {
        object val = GetConst(type, fieldName);
        if (!object.Equals(val, expected))
            throw new Exception($"{type.Name}.{fieldName} is {val}, expected {expected}");
    }
}
