using PlayerKnifeCustomizer;

static KnifePreset Preset(int paint, int count = 0) => new()
{
    Paint = paint,
    Seed = 0,
    Wear = 0.01f,
    StatTrakEnabled = true,
    StatTrakCount = count,
};

static void Require(bool condition, string message)
{
    if (!condition) throw new InvalidOperationException(message);
}
// Test the weapon preset resolver
var config = new KnifeConfig();
config.Loadouts.Ct.GunPresets[16] = Preset(309);
config.Loadouts.T.GunPresets[7] = Preset(661);
config.Loadouts.Ct.GunPresets[9] = Preset(344, 10);
config.Loadouts.T.GunPresets[9] = Preset(279, 20);
config.SharedWeaponLinks[9] = false;

Require(WeaponPresetResolver.TryResolveGunPreset(config, 16, CosmeticTeam.T, out var m4) && m4.Paint == 309,
    "A CT-exclusive weapon must resolve the CT preset after a T pickup.");
Require(WeaponPresetResolver.TryResolveGunPreset(config, 7, CosmeticTeam.Ct, out var ak) && ak.Paint == 661,
    "A T-exclusive weapon must resolve the T preset after a CT pickup.");
Require(WeaponPresetResolver.TryResolveGunPreset(config, 9, CosmeticTeam.Ct, out var ctAwp) && ctAwp.Paint == 344,
    "An unlinked shared weapon must resolve the current CT preset.");
Require(WeaponPresetResolver.TryResolveGunPreset(config, 9, CosmeticTeam.T, out var tAwp) && tAwp.Paint == 279,
    "An unlinked shared weapon must resolve the current T preset.");
Require(!WeaponPresetResolver.TryResolveGunPreset(config, 9, null, out _),
    "A spectator or unknown team must not receive a cosmetic preset.");

tAwp.StatTrakCount++;
Require(config.Loadouts.T.GunPresets[9].StatTrakCount == 21 && config.Loadouts.Ct.GunPresets[9].StatTrakCount == 10,
    "StatTrak must update only the resolved team preset.");

config.Loadouts.T.GunPresets.Remove(9);
config.SharedWeaponLinks[9] = true;
Require(WeaponPresetResolver.TryResolveGunPreset(config, 9, CosmeticTeam.T, out var linkedAwp) && linkedAwp.Paint == 344,
    "A linked shared weapon must fall back to the configured side.");

var validStickerIds = new HashSet<uint> { 1, 2, 3, 4, 5, 6 };
var stickerSchemaCounts = new Dictionary<ushort, uint> { [7] = 4, [9] = 5 };
var customSticker = new StickerPreset
{
    Slot = 0, Id = 1, Schema = 2, Wear = 0.25f, Scale = 1.2f, Rotation = 45f,
    OffsetX = -0.4f, OffsetY = 0.7f, CustomPosition = true,
};
Require(StickerAttributePlanner.TryBuild(7, true, [customSticker], validStickerIds, stickerSchemaCounts, out var attributes, out var stickerError),
    $"A valid sticker plan must build: {stickerError}");
Require(attributes.Select(attribute => attribute.Name).SequenceEqual([
    "sticker slot 0 id", "sticker slot 0 schema", "sticker slot 0 offset x", "sticker slot 0 offset y",
    "sticker slot 0 wear", "sticker slot 0 scale", "sticker slot 0 rotation",
]), "Sticker attributes must use the exact CS2 attribute names and deterministic order.");
Require(unchecked((uint)BitConverter.SingleToInt32Bits(attributes[0].Value)) == customSticker.Id,
    "Sticker IDs must be encoded by reinterpreting uint bits as float bits.");
Require(unchecked((uint)BitConverter.SingleToInt32Bits(attributes[1].Value)) == customSticker.Schema
    && attributes[2].Value == customSticker.OffsetX && attributes[3].Value == customSticker.OffsetY,
    "Custom positions must preserve the selected weapon schema and bounded X/Y offsets.");

customSticker.CustomPosition = false;
Require(StickerAttributePlanner.TryBuild(7, true, [customSticker], validStickerIds, stickerSchemaCounts, out attributes, out _)
    && attributes.Any(attribute => attribute.Name.EndsWith("schema"))
    && attributes.All(attribute => !attribute.Name.Contains("offset")),
    "Default sticker placement must emit its schema without custom offsets.");
Require(StickerAttributePlanner.TryBuild(7, false, [customSticker], validStickerIds, stickerSchemaCounts, out attributes, out _)
    && attributes.Count == 0,
    "Disabling the feature must preserve configuration without emitting sticker attributes.");
Require(!StickerAttributePlanner.TryBuild(515, false, [customSticker], validStickerIds, stickerSchemaCounts, out _, out stickerError)
    && stickerError.Contains("knife"),
    "Knife stickers must be rejected even while sticker application is disabled.");
Require(!StickerAttributePlanner.TryBuild(7, true,
        Enumerable.Range(0, 6).Select(index => new StickerPreset { Slot = (byte)index, Id = (uint)(index + 1), Scale = 1f }),
        validStickerIds, stickerSchemaCounts, out _, out stickerError) && stickerError.Contains("more than five"),
    "A weapon must reject more than five stickers.");
Require(!StickerAttributePlanner.TryBuild(7, true,
        [new StickerPreset { Slot = 0, Id = 1, Scale = 1f }, new StickerPreset { Slot = 0, Id = 2, Scale = 1f }],
        validStickerIds, stickerSchemaCounts, out _, out stickerError) && stickerError.Contains("unique"),
    "Duplicate sticker slots must be rejected.");
Require(!StickerAttributePlanner.TryBuild(7, true,
        [new StickerPreset { Slot = 0, Id = 999, Scale = 1f }], validStickerIds, stickerSchemaCounts, out _, out stickerError)
    && stickerError.Contains("unknown"),
    "Unknown sticker IDs must be rejected before native writes.");
Require(!StickerAttributePlanner.TryBuild(7, true,
        [new StickerPreset { Slot = 0, Id = 1, Scale = float.NaN }], validStickerIds, stickerSchemaCounts, out _, out stickerError)
    && stickerError.Contains("range"),
    "Non-finite sticker values must be rejected before native writes.");
Require(!StickerAttributePlanner.TryBuild(42, true, [customSticker], validStickerIds, stickerSchemaCounts, out _, out stickerError)
    && stickerError.Contains("not supported"),
    "Weapons outside the fixed capability catalog must be rejected before native writes.");
customSticker.Schema = 4;
Require(!StickerAttributePlanner.TryBuild(7, true, [customSticker], validStickerIds, stickerSchemaCounts, out _, out stickerError)
    && stickerError.Contains("schema"),
    "Sticker schemas outside the selected weapon catalog must be rejected before native writes.");
customSticker.Schema = 2;

var validCharmIds = new HashSet<uint> { 37, 38 };
var charmPlacements = new Dictionary<ushort, IReadOnlyDictionary<uint, CharmNativePlacement>>
{
    [7] = new Dictionary<uint, CharmNativePlacement>
    {
        [3] = new CharmNativePlacement(3, 2.1f, 0.43f, 3.43f),
    },
};
var charm = new CharmPreset { Id = 37, PlacementId = 3, Seed = 12345 };
Require(CharmAttributePlanner.TryBuild(7, true, charm, validCharmIds, charmPlacements, out var charmAttributes, out var charmError)
    && charmAttributes.Select(attribute => attribute.Name).SequenceEqual([
        "keychain slot 0 id", "keychain slot 0 seed", "keychain slot 0 offset x",
        "keychain slot 0 offset y", "keychain slot 0 offset z",
    ]), $"A valid charm plan must resolve catalog-owned XYZ attributes: {charmError}");
Require(!CharmAttributePlanner.TryBuild(7, true, new CharmPreset { Id = 37, PlacementId = 99 }, validCharmIds, charmPlacements, out _, out charmError)
    && charmError.Contains("placement"), "Unknown charm placements must be rejected before native writes.");
Require(!CharmAttributePlanner.TryBuild(515, true, charm, validCharmIds, charmPlacements, out _, out charmError)
    && charmError.Contains("knife"), "Knife charms must be rejected before native writes.");
Require(DecorationConfigPolicy.CanPreserveStickers(
        7, true, [customSticker], new HashSet<uint>(), new Dictionary<ushort, uint>()),
    "A temporarily missing catalog must not erase structurally valid saved stickers.");
Require(DecorationConfigPolicy.CanPreserveCharm(
        7, true, charm, new HashSet<uint>(),
        new Dictionary<ushort, IReadOnlyDictionary<uint, CharmNativePlacement>>()),
    "A temporarily missing catalog must not erase a structurally valid saved charm.");
Require(!DecorationConfigPolicy.CanPreserveStickers(
        7, true, [new StickerPreset { Slot = 0, Id = 1, Scale = float.NaN }],
        new HashSet<uint>(), new Dictionary<ushort, uint>()),
    "Catalog fallback must still reject invalid sticker ranges.");
Require(!DecorationConfigPolicy.CanPreserveCharm(
        7, true, new CharmPreset { Id = 37, PlacementId = 3, Seed = -1 }, new HashSet<uint>(),
        new Dictionary<ushort, IReadOnlyDictionary<uint, CharmNativePlacement>>()),
    "Catalog fallback must still reject invalid charm ranges.");
const string ctAgent = "agents\\models\\ctm_fbi\\ctm_fbi.vmdl";
const string tAgent = "agents\\models\\tm_phoenix\\tm_phoenix.vmdl";
var agentModels = new Dictionary<CosmeticTeam, HashSet<string>>
{
    [CosmeticTeam.Ct] = new(StringComparer.OrdinalIgnoreCase) { ctAgent },
    [CosmeticTeam.T] = new(StringComparer.OrdinalIgnoreCase) { tAgent },
};
Require(AgentModelPolicy.IsAllowed(CosmeticTeam.Ct, ctAgent, agentModels),
    "A catalog-owned CT agent model must be accepted for CT.");
Require(!AgentModelPolicy.IsAllowed(CosmeticTeam.T, ctAgent, agentModels),
    "A CT agent model must never be accepted for T.");
Require(!AgentModelPolicy.IsAllowed(CosmeticTeam.Ct, "agents\\models\\ctm_unknown\\escape.vmdl", agentModels),
    "An unknown agent model must be rejected before SetModel.");
Require(AgentModelPolicy.IsAllowed(CosmeticTeam.Ct, string.Empty, agentModels),
    "An empty agent model must preserve the game default.");
Require(StickerFailurePolicy.ShouldRestoreBaseSkin(false) && !StickerFailurePolicy.ShouldRestoreBaseSkin(true),
    "A failed sticker plan or native write must restore the ordinary gun skin attributes.");

var linkedStickerConfig = new KnifeConfig();
linkedStickerConfig.Loadouts.Ct.GunPresets[9] = Preset(344);
linkedStickerConfig.Loadouts.Ct.GunPresets[9].Stickers = [customSticker.Clone()];
linkedStickerConfig.Loadouts.Ct.GunPresets[9].Charm = charm.Clone();
linkedStickerConfig.SharedWeaponLinks[9] = true;
linkedStickerConfig.Normalize();
Require(linkedStickerConfig.Loadouts.T.GunPresets[9].BaseValueEquals(linkedStickerConfig.Loadouts.Ct.GunPresets[9])
    && linkedStickerConfig.Loadouts.T.GunPresets[9].Stickers.Count == 0
    && linkedStickerConfig.Loadouts.T.GunPresets[9].Charm == null,
    "Shared CT/T normalization must copy only the base skin into a missing team preset.");
linkedStickerConfig.Loadouts.T.GunPresets[9].Paint = 279;
linkedStickerConfig.Loadouts.T.GunPresets[9].Stickers = [new StickerPreset { Slot = 1, Id = 2, Schema = 1, Scale = 1f }];
linkedStickerConfig.Loadouts.T.GunPresets[9].Charm = new CharmPreset { Id = 38, PlacementId = charm.PlacementId, Seed = 7 };
linkedStickerConfig.Normalize();
Require(linkedStickerConfig.Loadouts.T.GunPresets[9].Paint == 344
    && linkedStickerConfig.Loadouts.T.GunPresets[9].Stickers.Single().Id == 2
    && linkedStickerConfig.Loadouts.T.GunPresets[9].Charm?.Id == 38,
    "Shared CT/T normalization must synchronize base skin fields without replacing team decorations.");

var tracker = new ApplyGenerationTracker();
nint playerHandle = (nint)0x1000;

long initialSpawn = tracker.Begin(playerHandle, CosmeticApplyPhase.All);
long firstGive = tracker.Begin(playerHandle, CosmeticApplyPhase.Guns);
Require(!tracker.IsCurrent(playerHandle, initialSpawn),
    "A GiveNamedItem event must invalidate callbacks from the previous generation.");
Require(tracker.IsPending(playerHandle, firstGive, CosmeticApplyPhase.Knife) &&
        tracker.IsPending(playerHandle, firstGive, CosmeticApplyPhase.Gloves) &&
        tracker.IsPending(playerHandle, firstGive, CosmeticApplyPhase.Guns) &&
        tracker.IsPending(playerHandle, firstGive, CosmeticApplyPhase.Music) &&
        tracker.IsPending(playerHandle, firstGive, CosmeticApplyPhase.Agent),
    "A GiveNamedItem event must carry every unfinished spawn phase, including agents, into the new generation.");

Require(tracker.Complete(playerHandle, firstGive, CosmeticApplyPhase.Music),
    "The current generation must complete a phase before a pickup storm.");
long pickupStorm = firstGive;
for (int i = 0; i < 100; i++)
    pickupStorm = tracker.Begin(playerHandle, CosmeticApplyPhase.Guns);
Require(!tracker.IsPending(playerHandle, pickupStorm, CosmeticApplyPhase.Music),
    "A completed phase must not be reintroduced by later gun-only events.");
Require(tracker.IsPending(playerHandle, pickupStorm, CosmeticApplyPhase.Knife) &&
        tracker.IsPending(playerHandle, pickupStorm, CosmeticApplyPhase.Gloves) &&
        tracker.IsPending(playerHandle, pickupStorm, CosmeticApplyPhase.Guns) &&
        tracker.IsPending(playerHandle, pickupStorm, CosmeticApplyPhase.Agent),
    "A GiveNamedItem storm must preserve unfinished knife, glove, gun, and agent phases.");
Require(tracker.MarkRetryExhausted(playerHandle, pickupStorm),
    "The final bounded attempt must record unfinished phases once.");
Require(!tracker.MarkRetryExhausted(playerHandle, pickupStorm) && tracker.RetryExhaustions == 1,
    "Repeated final callbacks must not duplicate retry exhaustion diagnostics.");
long retryAfterEvent = tracker.Begin(playerHandle, CosmeticApplyPhase.Guns);
Require(tracker.MarkRetryExhausted(playerHandle, retryAfterEvent) && tracker.RetryExhaustions == 2,
    "A later gameplay event must create a fresh bounded retry window.");
Require(tracker.TryMarkReequip(playerHandle, retryAfterEvent) && !tracker.TryMarkReequip(playerHandle, retryAfterEvent),
    "A generation must issue at most one controlled re-equip fallback.");
long nextReequipGeneration = tracker.Begin(playerHandle, CosmeticApplyPhase.Guns);
Require(tracker.TryMarkReequip(playerHandle, nextReequipGeneration),
    "A later gameplay generation may issue one new controlled re-equip fallback.");

tracker.CancelAll();
for (int i = 0; i < 1000; i++)
{
    nint firstPawn = (nint)(0x2000 + i * 2);
    nint replacementPawn = firstPawn + 1;

    long spawn = tracker.Begin(playerHandle, CosmeticApplyPhase.All);
    Require(tracker.TryBindContext(playerHandle, spawn, firstPawn, (int)CosmeticTeam.Ct),
        "The current spawn generation must bind its initial pawn and team.");
    Require(tracker.Complete(playerHandle, spawn, CosmeticApplyPhase.Knife),
        "The first knife write must complete the knife phase.");
    Require(!tracker.IsPending(playerHandle, spawn, CosmeticApplyPhase.Knife),
        "A completed phase must not be written again by a later retry.");

    long teamChange = tracker.Begin(playerHandle, CosmeticApplyPhase.All);
    Require(!tracker.IsCurrent(playerHandle, spawn),
        "A team change must invalidate every callback from the old spawn generation.");
    Require(!tracker.Complete(playerHandle, spawn, CosmeticApplyPhase.Gloves),
        "A stale callback must not complete or write any phase.");
    Require(tracker.TryBindContext(playerHandle, teamChange, replacementPawn, (int)CosmeticTeam.T),
        "The replacement generation must bind the replacement pawn and team.");
    Require(!tracker.TryBindContext(playerHandle, teamChange, firstPawn, (int)CosmeticTeam.T),
        "A pawn replacement inside one generation must cancel that generation.");
    Require(!tracker.IsCurrent(playerHandle, teamChange),
        "A generation with a changed pawn must remain cancelled.");

    long pickup = tracker.Begin(playerHandle, CosmeticApplyPhase.Guns);
    Require(tracker.TryBindContext(playerHandle, pickup, replacementPawn, (int)CosmeticTeam.T),
        "A pickup generation must bind the current pawn.");
    Require(tracker.Complete(playerHandle, pickup, CosmeticApplyPhase.Guns),
        "A pickup generation must complete its single gun phase.");
    Require(!tracker.HasPending(playerHandle, pickup),
        "A completed pickup generation must not schedule repeated native writes.");
}

tracker.CancelAll();
Require(!tracker.IsCurrent(playerHandle, 3000), "Map or round cleanup must cancel all generations.");
Require(tracker.ActiveCount == 0 && tracker.ContextInvalidations == 1000,
    "Lifecycle diagnostics must count invalidated Pawn contexts without retaining generations.");

Require(!ApplyPipelineContext.IsReady(false, true, (nint)0x3000, CosmeticTeam.Ct),
    "A dead Pawn exposed by an early deathmatch spawn callback must not bind the new generation.");
Require(ApplyPipelineContext.IsReady(true, true, (nint)0x3001, CosmeticTeam.Ct),
    "A live replacement Pawn must be accepted on a later bounded retry.");
Require(ApplyPipelineContext.RetryDelays[^1] >= 0.90f,
    "The bounded retry window must cover delayed deathmatch and retake respawns.");

for (int i = 0; i < 1000; i++)
{
    tracker.Cancel(playerHandle);
    long respawn = tracker.Begin(playerHandle, CosmeticApplyPhase.All);
    nint oldCorpse = (nint)(0x4000 + i * 2);
    nint newPawn = oldCorpse + 1;
    Require(!ApplyPipelineContext.IsReady(false, true, oldCorpse, CosmeticTeam.T),
        "A corpse must not become the bound context for a rapid respawn.");
    Require(tracker.TryBindContext(playerHandle, respawn, newPawn, (int)CosmeticTeam.T),
        "The live replacement Pawn must bind after death cancellation.");
    Require(tracker.Complete(playerHandle, respawn, CosmeticApplyPhase.All),
        "Every cosmetic phase must be eligible to complete after a rapid respawn.");
}

var throttle = new ApplyErrorThrottle(TimeSpan.FromSeconds(30));
var now = DateTimeOffset.UtcNow;
Require(throttle.Check("gun", now).ShouldLog, "The first native write error must be logged.");
Require(!throttle.Check("gun", now.AddSeconds(1)).ShouldLog,
    "Repeated errors inside the throttle window must be suppressed.");
var resumed = throttle.Check("gun", now.AddSeconds(31));
Require(resumed.ShouldLog && resumed.Suppressed == 1,
    "The next error record must report how many duplicate errors were suppressed.");

// Weapon provenance decides which weapon entities a preset may be written onto.
{
    var provenance = new WeaponProvenance();
    provenance.RecordGrant((nint)0x1000, (nint)0x5100, 7, "weapon_ak47");
    provenance.RecordGrant((nint)0x1000, (nint)0x5101, 7, "weapon_ak47");
    Require(provenance.IsOwned((nint)0x5100, 7, "weapon_ak47"),
        "A weapon granted to the player must be eligible for their own preset.");
    Require(!provenance.IsOwned((nint)0x2000, 7, "weapon_ak47"),
        "A weapon entity this plugin never granted must keep the appearance it was picked up with.");
    provenance.Forget((nint)0x5101);
    Require(!provenance.IsOwned((nint)0x5101, 7, "weapon_ak47"),
        "A destroyed weapon must not leave ownership behind for a reused handle.");
    provenance.RecordGrant((nint)0x1000, (nint)0x5101, 9, "weapon_awp");
    Require(!provenance.IsOwned((nint)0x5101, 7, "weapon_ak47"),
        "A reused handle must not inherit the identity of the weapon that used to live there.");
    provenance.RecordGrant((nint)0x1000, (nint)0x5102, 9, "weapon_awp");
    Require(provenance.IsOwned((nint)0x5100, 7, "weapon_ak47"),
        "Another weapon with the same DefIndex must keep its own separate verdict.");
    provenance.ForgetPlayer((nint)0x1000);
    Require(!provenance.IsOwned((nint)0x5102, 9, "weapon_awp"),
        "Disconnecting a player must drop the weapons tracked for them.");
    provenance.RecordGrant((nint)0x1100, (nint)0x5300, 9, "weapon_awp");
    provenance.RecordGrant((nint)0x1200, (nint)0x5301, 9, "weapon_awp");
    provenance.ForgetPlayer((nint)0x1100);
    Require(!provenance.IsOwned((nint)0x5300, 9, "weapon_awp") && provenance.IsOwned((nint)0x5301, 9, "weapon_awp"),
        "Forgetting one player must not prune another player's weapons.");
    provenance.Clear();
    Require(provenance.Count == 0, "A map change must clear provenance entirely.");
}

// A live Panel edit only re-applies the region that actually changed.
{
    static KnifeConfig Configured()
    {
        var config = new KnifeConfig { Enabled = true };
        config.Loadouts.Ct.KnifePresets[507] = Preset(417);
        config.Loadouts.Ct.GunPresets[7] = Preset(2);
        config.Loadouts.Ct.Glove = new GlovePreset { Enabled = true, DefIndex = 5027, Paint = 10041 };
        config.Loadouts.T.KnifePresets[507] = Preset(417);
        config.Loadouts.T.GunPresets[7] = Preset(2);
        config.Normalize();
        return config;
    }

    Require(CosmeticConfigDiff.Compute(Configured(), Configured()).ChangesNothing,
        "An identical configuration must not schedule any apply.");

    KnifeConfig countOnly = Configured();
    countOnly.Loadouts.Ct.GunPresets[7].StatTrakCount = 42;
    Require(CosmeticConfigDiff.Compute(Configured(), countOnly).ChangesNothing,
        "A StatTrak counter change, which the plugin writes back itself, is not a cosmetic change.");

    KnifeConfig knife = Configured();
    knife.Loadouts.Ct.KnifePresets[507] = Preset(278);
    CosmeticApplyPhase knifePhases = (CosmeticApplyPhase)(int)CosmeticConfigDiff.Compute(Configured(), knife).Sections;
    Require(knifePhases.HasFlag(CosmeticApplyPhase.Knife) && !knifePhases.HasFlag(CosmeticApplyPhase.Guns),
        "A knife paint change must schedule the knife region only.");

    KnifeConfig glove = Configured();
    glove.Loadouts.Ct.Glove.Paint = 10042;
    CosmeticConfigDiff gloveDiff = CosmeticConfigDiff.Compute(Configured(), glove);
    Require(gloveDiff.Sections.HasFlag(CosmeticChangeSection.Gloves) &&
            !gloveDiff.Sections.HasFlag(CosmeticChangeSection.Guns),
        "A glove change must schedule the glove region only.");

    KnifeConfig gun = Configured();
    gun.Loadouts.Ct.GunPresets[7] = Preset(58);
    gun.Loadouts.Ct.GunPresets[9] = Preset(344);
    CosmeticConfigDiff gunDiff = CosmeticConfigDiff.Compute(Configured(), gun);
    Require(gunDiff.Sections.HasFlag(CosmeticChangeSection.Guns) &&
            gunDiff.ChangedGunDefIndexes.SequenceEqual(new ushort[] { 7, 9 }),
        "A gun edit must report exactly the changed DefIndexes so untouched weapons stay untouched.");

    KnifeConfig removed = Configured();
    removed.Loadouts.Ct.GunPresets.Remove(7);
    Require(CosmeticConfigDiff.Compute(Configured(), removed).ChangedGunDefIndexes.Contains((ushort)7),
        "Clearing a preset must count as a change to that weapon.");

    KnifeConfig sticker = Configured();
    sticker.Loadouts.Ct.GunPresets[7].Stickers.Add(new StickerPreset { Id = 1, Slot = 0 });
    Require(CosmeticConfigDiff.Compute(Configured(), sticker).Sections.HasFlag(CosmeticChangeSection.Guns),
        "A decoration change is a cosmetic change.");

    KnifeConfig disabled = Configured();
    disabled.Enabled = false;
    Require((CosmeticApplyPhase)(int)CosmeticConfigDiff.Compute(Configured(), disabled).Sections ==
            CosmeticApplyPhase.All, "Toggling enablement must re-run every region.");
}

// Debouncing must never let a burst of file events become a queue of reloads.
{
    var gate = new ConfigReloadGate(150);
    Require(gate.Signal(), "The first notification of a save must ask for a timer.");
    Require(!gate.Signal() && !gate.Signal(),
        "The duplicate events one atomic replace produces must collapse into the timer that already exists.");
    Require(gate.TryBeginWork(), "An armed timer must hand its accumulated signals to the game thread.");
    Require(!gate.TryBeginWork(), "A timer that nobody signalled must do nothing.");
    Require(gate.Signal() && gate.HasPendingWork(), "A save landing during a reload must stay visible.");
    Require(gate.TryBeginWork(), "The pending save must be picked up by the follow-up pass.");
    gate.Reset();
    Require(!gate.HasPendingWork() && !gate.TryBeginWork(), "Unloading must leave nothing queued.");
}

// The plugin may only remove the search-path lines named in the Panel's marker.
{
    const string dirty = "SearchPaths\r\n{\r\n\tGame\tcsgo/addons/metamod\r\n\tGame\tcsgo\r\n}\r\nNewDepotSetting\t1\r\n";
    const string clean = "SearchPaths\r\n{\r\n\tGame\tcsgo\r\n}\r\nNewDepotSetting\t1\r\n";
    string[] owned = ["csgo/addons/metamod"];
    Require(GameinfoIsolation.StripOwnedPaths(dirty, owned) == clean,
        "Restoring must drop the project line and keep the depot settings and the CRLF style.");
    Require(GameinfoIsolation.StripOwnedPaths(clean, owned) == clean,
        "Restoring an already clean file must report nothing to rewrite.");
    const string foreign = "SearchPaths\n{\n\tGame+Local\tWORKSHOP\n\tGame\tcsgo/addons/someothermod\n\tGame\tcsgo\n}\n";
    Require(GameinfoIsolation.StripOwnedPaths(foreign, owned) == foreign,
        "A search path this project never inserted must survive, even when it loads another Mod.");
    const string lfOnly = "SearchPaths\n{\n Game csgo/addons/metamod\n Game csgo\n}";
    string lfResult = GameinfoIsolation.StripOwnedPaths(lfOnly, owned);
    Require(!lfResult.Contains('\r') && lfResult == "SearchPaths\n{\n Game csgo\n}",
        "A line-feed-only gameinfo must stay line-feed-only, including its missing trailing newline.");
    Require(GameinfoIsolation.StripOwnedPaths(dirty, []) == dirty,
        "A marker that names no owned path authorises no edit at all.");

    Require(PanelIsolationMarker.TryRead(
        "{\"schema_version\":1,\"gameinfo\":\"E:/CS2/game/csgo/gameinfo.gi\",\"search_paths\":[\"csgo/addons/metamod\"],\"ticket\":{\"nonce\":\"x\",\"expires_at_unix\":2000}}",
        out PanelIsolationMarker? marker) && marker is not null,
        "A complete marker must be readable.");
    Require(marker!.GameinfoPath.EndsWith("gameinfo.gi", StringComparison.Ordinal),
        "The marker names the file the plugin is allowed to rewrite.");
    Require(marker.HasLiveTicket(1999) && !marker.HasLiveTicket(2000),
        "A launch ticket must expire instead of authorising every later start.");
    Require(!PanelIsolationMarker.TryRead("{\"gameinfo\":\"\",\"search_paths\":[\"csgo/addons/metamod\"]}", out _),
        "A marker without a target file must be refused.");
    Require(!PanelIsolationMarker.TryRead("{\"gameinfo\":\"a\",\"search_paths\":[]}", out _),
        "A marker naming no search path authorises nothing and must be refused.");
    Require(!PanelIsolationMarker.TryRead("{ not json", out _), "A malformed marker must be refused, not obeyed.");
    Require(PanelIsolationMarker.TryRead("{\"gameinfo\":\"a\",\"search_paths\":[\"csgo/addons/metamod\"]}",
        out PanelIsolationMarker? unticketed) && unticketed is not null && !unticketed.HasLiveTicket(1),
        "A marker carrying no ticket can never authorise a managed session.");
}

// The optional quick-knife rotation only moves which knife is the default.
{
    ushort[] rotation = [507, 515, 508, 500, 525, 512];
    Require(KnifeShortcutPolicy.TryAdvance(true, rotation, 507, out ushort second) && second == 515,
        "Advancing from the first shortcut knife must select the next one in the user's order.");
    Require(KnifeShortcutPolicy.TryAdvance(true, rotation, 512, out ushort wrapped) && wrapped == 507,
        "The rotation must wrap back to the first knife instead of stopping.");
    Require(KnifeShortcutPolicy.TryAdvance(true, rotation, 526, out ushort entered) && entered == 507,
        "A knife outside the rotation must still enter it from the start.");
    Require(!KnifeShortcutPolicy.TryAdvance(false, rotation, 507, out _),
        "A disabled shortcut must never change the player's knife.");
    Require(!KnifeShortcutPolicy.TryAdvance(true, Array.Empty<ushort>(), 507, out _),
        "An empty shortcut list must report that there is nothing to switch to.");

    var shortcutConfig = new KnifeConfig
    {
        ShortcutKnifeDefIndexes = [507, 507, 0, 515, 508, 500, 525, 512, 522, 523, 509, 505, 519, 503, 521, 526, 514, 506],
    };
    shortcutConfig.Normalize();
    Require(shortcutConfig.ShortcutKnifeDefIndexes.Count == KnifeShortcutPolicy.MaxShortcuts,
        "The saved shortcut list must stay bounded.");
    Require(shortcutConfig.ShortcutKnifeDefIndexes[0] == 507 && shortcutConfig.ShortcutKnifeDefIndexes[1] == 515,
        "Normalising must keep the user's order and drop duplicates and empty entries.");
}

// Wear must land inside the band the PaintKit publishes.
{
    var skin = new WeaponSkinEntry { WeaponDefIndex = 7, Paint = 2, MinWear = 0.06f, MaxWear = 0.70f };    KnifePreset tooNew = new() { Paint = 2, Wear = 0.01f };
    Require(PresetWearClamp.Clamp(tooNew, skin) && Math.Abs(tooNew.Wear - 0.06f) < 1e-6f,
        "Wear below the PaintKit minimum must be clamped up instead of failing the whole apply.");
    KnifePreset tooWorn = new() { Paint = 2, Wear = 0.99f };
    Require(PresetWearClamp.Clamp(tooWorn, skin) && Math.Abs(tooWorn.Wear - 0.70f) < 1e-6f,
        "Wear above the PaintKit maximum must be clamped down.");
    KnifePreset inBand = new() { Paint = 2, Wear = 0.30f };
    Require(!PresetWearClamp.Clamp(inBand, skin) && Math.Abs(inBand.Wear - 0.30f) < 1e-6f,
        "A valid wear must be left exactly as the user set it.");
    Require(!PresetWearClamp.Clamp(inBand, null),
        "A paint kit missing from the catalog has no published range, so nothing may be rewritten.");
}

// The CounterStrikeSharp guideline setting is a hard runtime requirement, so the
// plugin has to read it the same way CounterStrikeSharp does.
{
    string directory = Path.Combine(Path.GetTempPath(), $"pkc-guideline-{Guid.NewGuid():N}");
    Directory.CreateDirectory(directory);
    string Core(string text)
    {
        string path = Path.Combine(directory, "core.json");
        File.WriteAllText(path, text);
        return path;
    }

    Require(CosmeticRuntimeRequirement.ReadGuidelineSetting(Core("{\"FollowCS2ServerGuidelines\": true}")) == true,
        "An explicit enabled guideline setting must be read as enabled.");
    Require(CosmeticRuntimeRequirement.ReadGuidelineSetting(Core("{\"FollowCS2ServerGuidelines\": false, \"FutureSetting\": {\"a\": 1}}")) == false,
        "The setting must be read even when the file carries settings this plugin does not know.");
    Require(CosmeticRuntimeRequirement.ReadGuidelineSetting(Core("{\"ServerName\": \"mine\"}")) == null,
        "A configuration without the setting must not be reported as satisfied.");
    Require(CosmeticRuntimeRequirement.ReadGuidelineSetting(Core("{ not json")) == null,
        "An unparsable configuration must be reported as unknown instead of throwing during plugin load.");
    Require(CosmeticRuntimeRequirement.ReadGuidelineSetting(Core("{\"FollowCS2ServerGuidelines\": \"yes\"}")) == null,
        "A non-boolean setting must be reported as unknown, because CounterStrikeSharp will not treat it as disabled.");
    Require(CosmeticRuntimeRequirement.ReadGuidelineSetting(Path.Combine(directory, "absent.json")) == null,
        "A missing core.json must be reported as unknown; CounterStrikeSharp defaults the setting to enabled.");

    Require(CosmeticRuntimeRequirement.AllowsCosmeticWrites(false),
        "Cosmetic writes are only allowed when the guideline setting is explicitly disabled.");
    Require(!CosmeticRuntimeRequirement.AllowsCosmeticWrites(true) && !CosmeticRuntimeRequirement.AllowsCosmeticWrites(null),
        "An enabled or unknown guideline setting must refuse cosmetic writes, which covers knives, gloves and guns alike.");
    Require(CosmeticRuntimeRequirement.BlockReason(true).Contains(CosmeticRuntimeRequirement.GuidelineSettingName)
            && CosmeticRuntimeRequirement.BlockReason(true).Contains("configs/core.json"),
        "The refusal has to name the setting and the file the Panel reconciles.");
    Require(CosmeticRuntimeRequirement.BlockReason(null).Contains("Local Cosmetics Panel"),
        "The unknown-setting refusal must point at the supported way to satisfy the requirement.");

    Directory.Delete(directory, true);
}

// The quick-knife shortcut replaces the knife entity, so it needs the schema name of
// the type it is creating and the current team's own preset layer.
{
    Require(KnifeSchemaNames.GiveName(507, CosmeticTeam.Ct) == "weapon_knife_karambit"
            && KnifeSchemaNames.GiveName(500, CosmeticTeam.T) == "weapon_bayonet",
        "A known knife defindex has to be given by its own schema name so the new entity is created as that type.");
    Require(KnifeSchemaNames.GiveName(511, CosmeticTeam.Ct) == KnifeSchemaNames.CounterTerroristKnife
            && KnifeSchemaNames.GiveName(511, CosmeticTeam.T) == KnifeSchemaNames.TerroristKnife,
        "A defindex outside the table falls back to the team's generic knife, which the swap then subclasses.");

    var ct = new TeamLoadout();
    ct.KnifePresets[507] = new KnifePreset { Paint = 42 };
    var t = new TeamLoadout();
    Require(KnifeShortcutPreset.Resolve(ct, 507)?.Paint == 42,
        "A knife that has a preset for the current team must keep that skin.");
    Require(KnifeShortcutPreset.Resolve(t, 507) == null,
        "A knife without a preset for the current team switches to the vanilla knife rather than borrowing the other side's skin.");
    Require(KnifeShortcutPreset.Resolve(t, 508) == null,
        "A missing preset must never be invented just because the knife is in the shortcut list.");

    ushort[] rotation = [507, 515, 508];
    Require(KnifeShortcutPolicy.TryAdvance(true, rotation, 507, out ushort firstTry) && firstTry == 515
            && KnifeShortcutPolicy.TryAdvance(true, rotation, 507, out ushort retry) && retry == 515,
        "Rotating from the live entity must retry the same target after a failed switch instead of skipping a slot.");
    Require(KnifeShortcutPolicy.TryAdvance(true, new ushort[] { 507 }, 507, out ushort only) && only == 507,
        "A one-knife rotation reports the same defindex, which the command reads as nothing to do.");
}

Console.WriteLine("PlayerKnifeCustomizer resolver, lifecycle, provenance, live-reload, launch-isolation, wear-clamp, runtime-requirement and knife-swap tests passed.");
