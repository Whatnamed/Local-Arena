[CmdletBinding()]
param(
    [string]$PackageRoot,
    [string]$ExpectedPackageVersion = "1.4.3.3"
)

# Cosmetics-only workspace and release audit.
#
# In workspace mode this checks that the Bot / match / update surface really is
# gone from the source tree and that the shipped cosmetic catalogs still agree
# with their generators. With -PackageRoot it additionally audits a staged
# release against scripts/release-inventory.json, which is the same list
# scripts/package.ps1 assembled the package from.

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot "dependencies.json") -Raw | ConvertFrom-Json
$inventory = Get-Content -LiteralPath (Join-Path $PSScriptRoot "release-inventory.json") -Raw | ConvertFrom-Json
$failures = [Collections.Generic.List[string]]::new()

function Add-Failure([string]$Message) {
    $failures.Add($Message)
}

function Assert-File([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Add-Failure "Missing $Label`: $Path"
    }
}

function Test-ForbiddenReleasePath([string]$Relative) {
    $segments = $Relative -split "/"
    $leaf = $segments[-1]
    $hit = @($segments | Where-Object { $inventory.forbidden_segments -contains $_ })
    if ($inventory.forbidden_file_names -contains $leaf) { $hit += $leaf }
    if ($leaf -match '(?i)^(?:bot|my_bot)' -or $leaf -match '(?i)botprofile') { $hit += $leaf }
    if ($inventory.forbidden_extensions -contains [IO.Path]::GetExtension($leaf)) { $hit += $leaf }
    return $hit
}

function Get-RelativePaths([string]$Root) {
    @(Get-ChildItem -LiteralPath $Root -Recurse -Force | ForEach-Object {
        if ($_.PSIsContainer) { return }
        [IO.Path]::GetRelativePath($Root, $_.FullName).Replace("\", "/")
    } | Sort-Object)
}

function Get-JsonCount([string]$RelativePath) {
    $path = Join-Path $repo $RelativePath
    try {
        $document = [System.Text.Json.JsonDocument]::Parse([IO.File]::ReadAllText($path))
        try {
            if ($document.RootElement.ValueKind -eq [System.Text.Json.JsonValueKind]::Array) {
                return $document.RootElement.GetArrayLength()
            }
            if ($document.RootElement.ValueKind -eq [System.Text.Json.JsonValueKind]::Object) {
                $count = 0
                foreach ($property in $document.RootElement.EnumerateObject()) { $count++ }
                return $count
            }
            return 1
        }
        finally {
            $document.Dispose()
        }
    }
    catch {
        Add-Failure "Invalid JSON $RelativePath`: $($_.Exception.Message)"
        return -1
    }
}

function Get-SourceText([string]$RelativePath) {
    $path = Join-Path $repo $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Failure "Missing source file $RelativePath"
        return ""
    }
    Get-Content -LiteralPath $path -Raw
}

$localBuildConfig = Join-Path $repo ".local-build.ps1"
if ($env:GITHUB_ACTIONS -ne "true" -and -not (Test-Path -LiteralPath $localBuildConfig -PathType Leaf)) {
    Add-Failure "Local build configuration is missing; run the workspace setup before building."
}
foreach ($script in @("build.ps1", "package.ps1")) {
    $text = Get-SourceText "scripts/$script"
    if ($text -match 'portable' + '-toolchain') {
        Add-Failure "scripts/$script must not expose the local tool directory name."
    }
}

# The product boundary: no enhanced-bot, match or game-mode runtime in the tree.
foreach ($removed in @("cfg", "overrides", "addons/BotHider", "addons/RayTrace", "addons/metamod")) {
    if (Test-Path -LiteralPath (Join-Path $repo $removed)) {
        Add-Failure "The Cosmetics-only product must not carry a $removed directory."
    }
}
$pluginDirectories = @(Get-ChildItem -LiteralPath (Join-Path $repo "addons/counterstrikesharp/plugins") -Directory |
    ForEach-Object Name)
foreach ($plugin in @($pluginDirectories | Where-Object { $_ -notin @("PlayerKnifeCustomizer", "PlayerKnifeCustomizer.Tests") })) {
    Add-Failure "Unexpected plugin project remains: $plugin"
}
if ($pluginDirectories -notcontains "PlayerKnifeCustomizer") {
    Add-Failure "The cosmetics plugin project is missing."
}
foreach ($removed in @(
    "Panel/src-tauri/src/mode_files.rs",
    "Panel/src-tauri/src/mode_layout.rs",
    "Panel/src-tauri/src/cs2ss_bridge.rs",
    "Panel/src-tauri/src/match_system.rs",
    "Panel/src-tauri/src/online_update.rs",
    "Panel/src-tauri/src/update_core.rs"
)) {
    if (Test-Path -LiteralPath (Join-Path $repo $removed)) {
        Add-Failure "Removed Panel backend module is back: $removed"
    }
}
$panelSources = @(Get-ChildItem -LiteralPath (Join-Path $repo "Panel/src") -Recurse -File -Include *.ts, *.tsx |
    ForEach-Object { [IO.Path]::GetRelativePath((Join-Path $repo "Panel/src"), $_.FullName).Replace("\", "/") })
foreach ($stale in @($panelSources | Where-Object {
    $_ -match '(?i)(match|nade|bot|lineup|telemetry|rating|demo|mode)[^/]*\.(ts|tsx)$' -and
    $_ -notin @("lib/modeLayout.ts")
})) {
    Add-Failure "Unexpected Bot-era Panel source is back: $stale"
}

$playerCosmetics = Get-SourceText "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/PlayerKnifeCustomizer.cs"
if ($playerCosmetics -notmatch "RetryDelays = \[0\.10f, 0\.25f, 0\.50f, 0\.90f\]") {
    Add-Failure "The cosmetics apply pipeline no longer has its bounded retry schedule."
}
if ($playerCosmetics -notmatch "FileSystemWatcher" -or $playerCosmetics -notmatch "ConfigReloadGate") {
    Add-Failure "Live preset reload must stay event-driven through a watcher and a debounce gate."
}
if ($playerCosmetics -notmatch "WeaponProvenance") {
    Add-Failure "Weapon presets must be gated by entity provenance."
}
if ($playerCosmetics -match "ItemPickup|OnEntitySpawned|NextWorldUpdate|TryApplyDroppedKnife") {
    Add-Failure "The plugin must not reskin picked-up or foreign weapon entities."
}
if ($playerCosmetics -notmatch "GameinfoIsolation|PanelIsolationMarker") {
    Add-Failure "The plugin must keep healing the launch-isolation window it was started in."
}
$panelBackend = Get-SourceText "Panel/src-tauri/src/lib.rs"
if ($panelBackend -notmatch "launch_isolation::prepare_local_launch" -or
    $panelBackend -notmatch "fn spawn_local_launch") {
    Add-Failure "The Panel must keep launching local cosmetics through the transactional isolation module."
}

$requiredSources = @(
    "Panel/src-tauri/src/launch_isolation.rs",
    "Panel/src-tauri/src/install_checks.rs",
    "Panel/src-tauri/src/installer.rs",
    "Panel/src/lib/launchGate.ts",
    "Panel/src/panels/LaunchCard.tsx",
    "Panel/src/panels/WeaponPresetsPanel.tsx",
    "Panel/src/panels/KnifePresetModal.tsx",
    "Panel/src/panels/GlovePresetModal.tsx",
    "Panel/src/panels/MusicKitPresetModal.tsx",
    "Panel/src/panels/StickersPanel.tsx",
    "Panel/src/data/cosmeticOrder.ts",
    "Panel/src/data/gloveFinishNames.json",
    "Panel/src/data/stickerCatalog.json",
    "Panel/src/data/stickerCatalog.source.json",
    "Panel/src/data/stickerWeaponIds.json",
    "Panel/src/data/cosmeticPlacements.json",
    "Panel/src/data/charmCatalog.json",
    "Panel/src/data/agentCatalog.json",
    "Panel/src/lib/stickerEditor.ts",
    "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/WeaponProvenance.cs",
    "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/CosmeticConfigChange.cs",
    "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/LaunchIsolation.cs",
    "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/sticker_weapon_ids.json",
    "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/player_cosmetic_catalog.json",
    "scripts/generate-sticker-catalog.mjs",
    "scripts/generate-player-cosmetic-placements.mjs",
    "scripts/test-sticker-editor.mjs",
    "scripts/test-cosmetic-order.mjs",
    "scripts/release-inventory.json",
    "docs/PRODUCT-SCOPE.md",
    "docs/MANUAL-ACCEPTANCE.md",
    "docs/UPSTREAM.md",
    "LICENSE"
)
foreach ($relative in $requiredSources) {
    Assert-File (Join-Path $repo $relative) $relative
}

$jsonFiles = @(
    "Panel/src/data/gloveSkins.json",
    "Panel/src/data/musicKits.json",
    "Panel/src/data/skinImages.json",
    "Panel/src/data/skinNames.json",
    "Panel/src/data/weaponSkins.json",
    "Panel/src/data/stickerCatalog.json",
    "Panel/src/data/stickerWeaponIds.json",
    "Panel/src/data/cosmeticPlacements.json",
    "Panel/src/data/charmCatalog.json",
    "Panel/src/data/agentCatalog.json",
    "Panel/src/data/gloveFinishNames.json",
    "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/sticker_ids.json",
    "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/sticker_weapon_ids.json",
    "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/player_cosmetic_catalog.json",
    "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/skins_en.json",
    "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/weapon_skins.json"
)
$counts = @{}
foreach ($relative in $jsonFiles) {
    $counts[$relative] = Get-JsonCount $relative
}

$catalogA = Join-Path $repo "Panel/src/data/weaponSkins.json"
$catalogB = Join-Path $repo "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/weapon_skins.json"
if ((Get-FileHash -LiteralPath $catalogA -Algorithm SHA256).Hash -ne
    (Get-FileHash -LiteralPath $catalogB -Algorithm SHA256).Hash) {
    Add-Failure "Panel and plugin weapon catalogs are not identical."
}

try {
    $stickerSource = Get-Content -LiteralPath (Join-Path $repo "Panel/src/data/stickerCatalog.source.json") -Raw | ConvertFrom-Json
    $stickerGenerator = Get-SourceText "scripts/generate-sticker-catalog.mjs"
    $panelHash = (Get-FileHash -LiteralPath (Join-Path $repo "Panel/src/data/stickerCatalog.json") -Algorithm SHA256).Hash.ToLowerInvariant()
    $pluginHash = (Get-FileHash -LiteralPath (Join-Path $repo "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/sticker_ids.json") -Algorithm SHA256).Hash.ToLowerInvariant()
    $weaponPanelHash = (Get-FileHash -LiteralPath (Join-Path $repo "Panel/src/data/stickerWeaponIds.json") -Algorithm SHA256).Hash.ToLowerInvariant()
    $weaponPluginHash = (Get-FileHash -LiteralPath (Join-Path $repo "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/sticker_weapon_ids.json") -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($stickerSource.schema_version -ne 1 -or
        $stickerSource.outputs.count -ne $counts["Panel/src/data/stickerCatalog.json"] -or
        $counts["Panel/src/data/stickerCatalog.json"] -ne $counts["addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/sticker_ids.json"] -or
        $panelHash -ne [string]$stickerSource.outputs.panel_sha256 -or
        $pluginHash -ne [string]$stickerSource.outputs.plugin_ids_sha256 -or
        $counts["Panel/src/data/stickerWeaponIds.json"] -ne $stickerSource.capabilities.supported_weapon_count -or
        $counts["Panel/src/data/stickerWeaponIds.json"] -ne $counts["addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/sticker_weapon_ids.json"] -or
        $weaponPanelHash -ne [string]$stickerSource.outputs.weapon_ids_sha256 -or
        $weaponPluginHash -ne [string]$stickerSource.outputs.weapon_ids_sha256 -or
        $stickerGenerator -notmatch [regex]::Escape([string]$stickerSource.commit) -or
        $stickerGenerator -notmatch [regex]::Escape([string]$stickerSource.capabilities.commit)) {
        Add-Failure "Sticker catalog source commits, counts, capabilities, or deterministic hashes do not match generated outputs."
    }
}
catch {
    Add-Failure "Sticker catalog metadata is invalid: $($_.Exception.Message)"
}

try {
    $panelPlacements = Get-Content -LiteralPath (Join-Path $repo "Panel/src/data/cosmeticPlacements.json") -Raw | ConvertFrom-Json
    $panelCharms = @(Get-Content -LiteralPath (Join-Path $repo "Panel/src/data/charmCatalog.json") -Raw | ConvertFrom-Json)
    $panelAgents = @(Get-Content -LiteralPath (Join-Path $repo "Panel/src/data/agentCatalog.json") -Raw | ConvertFrom-Json)
    $pluginCosmetics = Get-Content -LiteralPath (Join-Path $repo "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/player_cosmetic_catalog.json") -Raw | ConvertFrom-Json
    $placementGenerator = Get-SourceText "scripts/generate-player-cosmetic-placements.mjs"
    if ($pluginCosmetics.schema_version -ne 1 -or
        $counts["Panel/src/data/cosmeticPlacements.json"] -ne 35 -or
        $panelCharms.Count -ne 81 -or
        @($panelAgents | Where-Object team -eq "ct").Count -ne 35 -or
        @($panelAgents | Where-Object team -eq "t").Count -ne 44 -or
        @($pluginCosmetics.charm_ids).Count -ne $panelCharms.Count -or
        @($pluginCosmetics.agent_models.ct).Count -ne 35 -or
        @($pluginCosmetics.agent_models.t).Count -ne 44 -or
        @($panelCharms | Where-Object { -not [string]::IsNullOrWhiteSpace($_.image) }).Count -ne 78 -or
        @($panelAgents | Where-Object { -not [string]::IsNullOrWhiteSpace($_.image) }).Count -ne 63 -or
        [string]::IsNullOrWhiteSpace($pluginCosmetics.inventory_images.commit) -or
        @($pluginCosmetics.weapons.PSObject.Properties).Count -ne 35 -or
        $placementGenerator -notmatch "charmAnchors" -or
        $placementGenerator -notmatch "source_sha256" -or
        $placementGenerator -notmatch [regex]::Escape([string]$pluginCosmetics.inventory_images.commit)) {
        Add-Failure "Player cosmetic placement, charm, or agent outputs have unexpected counts."
    }
}
catch {
    Add-Failure "Player cosmetic placement metadata is invalid: $($_.Exception.Message)"
}

$trackedGenerated = @(& git -C $repo ls-files | Where-Object {
    $_ -match '(^|/)(bin|obj|node_modules|dist|target|artifacts|\.cache)/'
})
if ($trackedGenerated.Count -gt 0) {
    Add-Failure "Generated paths are tracked: $($trackedGenerated -join ', ')"
}

if ($PackageRoot) {
    $package = [IO.Path]::GetFullPath($PackageRoot)
    if (-not (Test-Path -LiteralPath $package -PathType Container)) {
        Add-Failure "Package root does not exist: $package"
        $packageFiles = @()
    }
    else {
        $packageFiles = @(Get-RelativePaths $package)
    }
    foreach ($relative in $inventory.required_payload_files) {
        if ($relative -eq "plus-payload-manifest.json") { continue }
        if ($packageFiles -notcontains $relative) {
            Add-Failure "Package is missing a required file: $relative"
        }
    }

    $pluginDirectory = Join-Path $package "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer"
    if (Test-Path -LiteralPath $pluginDirectory -PathType Container) {
        $packagedPluginFiles = @(Get-RelativePaths $pluginDirectory | ForEach-Object { Split-Path -Leaf $_ })
        $pluginDifference = @(Compare-Object ($inventory.cosmetics_plugin_files | Sort-Object) ($packagedPluginFiles | Sort-Object))
        if ($pluginDifference.Count -gt 0) {
            Add-Failure "Packaged cosmetics plugin does not match its pinned build allowlist: $(($pluginDifference | ForEach-Object InputObject) -join ', ')"
        }
    }
    else {
        Add-Failure "Package has no cosmetics plugin directory: $pluginDirectory"
    }

    foreach ($relative in $packageFiles) {
        $hit = Test-ForbiddenReleasePath $relative
        if ($hit.Count -gt 0) {
            Add-Failure "Forbidden component reached the release package: $relative (matched: $($hit -join ', '))"
        }
    }

    $previewNotice = Join-Path $package "PREVIEW-NOTICE.txt"
    if ($ExpectedPackageVersion -match '-Preview\.\d+$') {
        Assert-File $previewNotice "package preview notice"
    }
    elseif (Test-Path -LiteralPath $previewNotice) {
        Add-Failure "Official package must not contain PREVIEW-NOTICE.txt."
    }

    $pinnedRuntimes = @(
        @{ Relative = "addons/metamod/bin/win64/server.dll"; Hash = $manifest.metamod.windowsLoaderSha256; Label = "Metamod" },
        @{ Relative = "addons/counterstrikesharp/bin/win64/counterstrikesharp.dll"; Hash = $manifest.counterStrikeSharp.windowsCoreSha256; Label = "CounterStrikeSharp" }
    )
    foreach ($runtime in $pinnedRuntimes) {
        $runtimePath = Join-Path $package $runtime.Relative
        if (Test-Path -LiteralPath $runtimePath) {
            $runtimeHash = (Get-FileHash -LiteralPath $runtimePath -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($runtimeHash -ne ([string]$runtime.Hash).ToLowerInvariant()) {
                Add-Failure "$($runtime.Label) does not match the pinned runtime: $runtimeHash"
            }
        }
    }

    $packagedPanel = Join-Path $package "cs2-bot-improver-plus-panel.exe"
    $builtPanel = Join-Path $repo "Panel/src-tauri/target/release/cs2-bot-improver-plus-panel.exe"
    if ((Test-Path -LiteralPath $packagedPanel) -and (Test-Path -LiteralPath $builtPanel) -and
        ((Get-FileHash -LiteralPath $packagedPanel -Algorithm SHA256).Hash -ne
            (Get-FileHash -LiteralPath $builtPanel -Algorithm SHA256).Hash)) {
        Add-Failure "Packaged Panel is not the current production Release build."
    }
    $packagedPluginDll = Join-Path $pluginDirectory "PlayerKnifeCustomizer.dll"
    $builtPluginDll = Join-Path $repo "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/bin/Release/net10.0/PlayerKnifeCustomizer.dll"
    if ((Test-Path -LiteralPath $packagedPluginDll) -and (Test-Path -LiteralPath $builtPluginDll) -and
        ((Get-FileHash -LiteralPath $packagedPluginDll -Algorithm SHA256).Hash -ne
            (Get-FileHash -LiteralPath $builtPluginDll -Algorithm SHA256).Hash)) {
        Add-Failure "Packaged cosmetics plugin is not the current source build."
    }

    $payloadManifestPath = Join-Path $package "plus-payload-manifest.json"
    if (Test-Path -LiteralPath $payloadManifestPath) {
        try {
            $payloadManifest = Get-Content -LiteralPath $payloadManifestPath -Raw | ConvertFrom-Json
            if ($payloadManifest.schema_version -ne 1 -or $payloadManifest.package_version -ne $ExpectedPackageVersion) {
                Add-Failure "Package payload manifest has an unexpected schema or version."
            }
            $manifestPaths = @{}
            foreach ($entry in $payloadManifest.entries) {
                $relative = [string]$entry.path
                if ($manifestPaths.ContainsKey($relative)) {
                    Add-Failure "Package payload manifest contains a duplicate path: $relative"
                    continue
                }
                $manifestPaths[$relative] = $entry
                if ($relative -notmatch '^addons/' -or $relative -match '(^|/)\.\.(/|$)') {
                    Add-Failure "Package payload manifest contains an unsafe path: $relative"
                    continue
                }
                $file = Join-Path $package $relative
                if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
                    Add-Failure "Package payload manifest references a missing file: $relative"
                    continue
                }
                $actualSize = (Get-Item -LiteralPath $file).Length
                $actualHash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
                if ($actualSize -ne [long]$entry.size -or $actualHash -ne ([string]$entry.sha256).ToLowerInvariant()) {
                    Add-Failure "Package payload manifest verification failed: $relative"
                }

                $owned = @($inventory.panel_owned_paths | Where-Object { $relative -like "$_/*" }).Count -gt 0
                $expectedOwnership = if ($owned) { "plus" } else { "shared" }
                if ([string]$entry.ownership -ne $expectedOwnership) {
                    Add-Failure "Unexpected ownership for $relative`: expected $expectedOwnership, found $($entry.ownership)"
                }
                $expectedPolicy = if ($inventory.preserve_config_paths -contains $relative) { "preserve-config" } else { "restore" }
                if ([string]$entry.restore_policy -ne $expectedPolicy) {
                    Add-Failure "Unexpected restore policy for $relative`: expected $expectedPolicy, found $($entry.restore_policy)"
                }
            }
            foreach ($relative in ($packageFiles | Where-Object { $_ -like "addons/*" })) {
                if (-not $manifestPaths.ContainsKey($relative)) {
                    Add-Failure "Package payload file is not tracked by the manifest: $relative"
                }
            }
            foreach ($relative in $inventory.preserve_config_paths) {
                if ([string]$manifestPaths[$relative].restore_policy -ne "preserve-config") {
                    Add-Failure "Mutable player configuration is not protected by preserve-config: $relative"
                }
            }
        }
        catch {
            Add-Failure "Package payload manifest is invalid: $($_.Exception.Message)"
        }
    }
    else {
        Add-Failure "Package has no plus-payload-manifest.json."
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    exit 1
}

Write-Host "Workspace verification passed."
Write-Host "Weapon skins: $($counts['Panel/src/data/weaponSkins.json'])"
Write-Host "Glove finishes: $($counts['Panel/src/data/gloveSkins.json'])"
Write-Host "Glove finish names localised: $($counts['Panel/src/data/gloveFinishNames.json'])"
Write-Host "Music kits: $($counts['Panel/src/data/musicKits.json'])"
Write-Host "Stickers: $($counts['Panel/src/data/stickerCatalog.json'])"
if ($PackageRoot) { Write-Host "Package layout verified: $([IO.Path]::GetFullPath($PackageRoot))" }
