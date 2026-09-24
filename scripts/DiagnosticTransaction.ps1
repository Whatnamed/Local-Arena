# Common transaction, snapshot, and runtime helpers for Local Arena diagnostics
$ErrorActionPreference = "Stop"

$Global:DiagnosticRuntimeTrees = @(
    "addons/metamod/bin",
    "addons/counterstrikesharp/api",
    "addons/counterstrikesharp/bin",
    "addons/counterstrikesharp/dotnet",
    "addons/counterstrikesharp/gamedata",
    "addons/counterstrikesharp/lang",
    "addons/counterstrikesharp/source"
)

$Global:DiagnosticTargetComponents = @(
    @{ Name = "BotHider.vdf"; Active = "addons/metamod/BotHider.vdf"; Disabled = "addons/metamod/BotHider.vdf.csbip-disabled" },
    @{ Name = "BotHiderImpl.dll"; Active = "addons/counterstrikesharp/plugins/BotHiderImpl/BotHiderImpl.dll"; Disabled = "addons/counterstrikesharp/plugins/BotHiderImpl/BotHiderImpl.dll.csbip-disabled" },
    @{ Name = "PlayerKnifeCustomizer.dll"; Active = "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/PlayerKnifeCustomizer.dll"; Disabled = "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/PlayerKnifeCustomizer.dll.csbip-disabled" }
)

$Global:DiagnosticPreservedConfigs = @(
    "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/player_knife_presets.json",
    "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/player_gun_presets.json",
    "addons/counterstrikesharp/plugins/BotRandomizer/bot_randomizer_options.json",
    "cfg/my_bot_ffa_config.cfg",
    "cfg/my_bot_normal_config.cfg",
    "overrides/botprofile.vpk"
)

function Find-Cs2Root {
    param([string]$UserPath)
    if ($UserPath) {
        $candidate = (Resolve-Path -LiteralPath $UserPath -ErrorAction Stop).Path
        if (Test-Path -LiteralPath (Join-Path $candidate "gameinfo.gi")) { return $candidate }
        $sub = Join-Path $candidate "game\csgo"
        if (Test-Path -LiteralPath (Join-Path $sub "gameinfo.gi")) { return $sub }
        throw "Specified path is not a CS2 directory (gameinfo.gi missing): $UserPath"
    }
    $panelConfigs = @(
        (Join-Path $HOME ".csbip\config\panel.json"),
        (Join-Path $env:APPDATA "cs2bi\config\panel.json")
    )
    foreach ($cfg in $panelConfigs) {
        if (Test-Path -LiteralPath $cfg) {
            try {
                $json = Get-Content -LiteralPath $cfg -Raw | ConvertFrom-Json
                if ($json.csgo_path -and (Test-Path -LiteralPath (Join-Path $json.csgo_path "gameinfo.gi"))) {
                    return $json.csgo_path
                }
            } catch {}
        }
    }
    $steamPath = (Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -Name "SteamPath" -ErrorAction SilentlyContinue).SteamPath
    if ($steamPath) {
        $stdCsgo = Join-Path $steamPath "steamapps\common\Counter-Strike Global Offensive\game\csgo"
        if (Test-Path -LiteralPath (Join-Path $stdCsgo "gameinfo.gi")) { return $stdCsgo }
        $libFolders = Join-Path $steamPath "steamapps\libraryfolders.vdf"
        if (Test-Path -LiteralPath $libFolders) {
            $content = Get-Content -LiteralPath $libFolders -Raw
            $matches = [regex]::Matches($content, '"path"\s+"([^"]+)"')
            foreach ($m in $matches) {
                $libPath = $m.Groups[1].Value.Replace("\\", "\")
                $cand = Join-Path $libPath "steamapps\common\Counter-Strike Global Offensive\game\csgo"
                if (Test-Path -LiteralPath (Join-Path $cand "gameinfo.gi")) { return $cand }
            }
        }
    }
    throw "Could not locate CS2 game/csgo directory automatically. Pass -Cs2Root <path to game/csgo>."
}

function New-DiagnosticRuntimeManifest {
    param([string]$StageRoot)
    $entries = foreach ($tree in $Global:DiagnosticRuntimeTrees) {
        $fullPath = Join-Path $StageRoot ($tree.Replace("/", "\"))
        if (Test-Path -LiteralPath $fullPath) {
            foreach ($file in Get-ChildItem -LiteralPath $fullPath -File -Recurse) {
                $rel = [IO.Path]::GetRelativePath($StageRoot, $file.FullName).Replace("\", "/")
                [ordered]@{
                    path = $rel
                    size = $file.Length
                    sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                }
            }
        }
    }
    return [ordered]@{
        schema_version = 1
        generated_at = (Get-Date -Format "o")
        trees = $Global:DiagnosticRuntimeTrees
        file_count = $entries.Count
        entries = @($entries | Sort-Object path)
    }
}

function Ensure-DiagnosticSnapshot {
    param([string]$CsgoRoot)

    $snapshotBase = Join-Path $CsgoRoot ".csbip"
    $snapshotDir = Join-Path $snapshotBase "diagnostic-snapshot"
    $snapshotManifest = Join-Path $snapshotDir "snapshot-manifest.json"
    $completionMarker = Join-Path $snapshotDir ".completed"

    if (Test-Path -LiteralPath $snapshotManifest) {
        if (-not (Test-Path -LiteralPath $completionMarker)) {
            throw "Existing diagnostic snapshot at $snapshotDir is incomplete (missing completion marker). Cannot safely proceed."
        }
        try {
            $manifest = Get-Content -LiteralPath $snapshotManifest -Raw | ConvertFrom-Json
        } catch {
            throw "Existing diagnostic snapshot manifest at $snapshotManifest is corrupted ($($_.Exception.Message)). Cannot safely proceed."
        }
        $manifestRoot = $manifest.csgo_root.TrimEnd('\', '/')
        $currentRoot = $CsgoRoot.TrimEnd('\', '/')
        if (-not [string]::Equals($manifestRoot, $currentRoot, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Existing diagnostic snapshot belongs to different root '$($manifest.csgo_root)', expected '$CsgoRoot'. Cannot safely proceed."
        }
        Write-Host "Reusing existing pre-diagnostic snapshot from $($manifest.created_at) ($($manifest.runtime_files.Count) runtime files, $($manifest.component_states.Count) components). Original state preserved." -ForegroundColor Cyan
        return $manifest
    }

    Write-Host "Creating new pre-diagnostic snapshot..."
    $tmpDir = Join-Path $snapshotBase "diagnostic-snapshot.tmp"
    if (Test-Path -LiteralPath $tmpDir) {
        Remove-Item -LiteralPath $tmpDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path (Join-Path $tmpDir "runtime") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tmpDir "components") -Force | Out-Null

    $backedUpRuntimeFiles = [Collections.Generic.List[PSCustomObject]]::new()

    try {
        foreach ($tree in $Global:DiagnosticRuntimeTrees) {
            $treePath = Join-Path $CsgoRoot ($tree.Replace("/", "\"))
            if (Test-Path -LiteralPath $treePath) {
                foreach ($file in Get-ChildItem -LiteralPath $treePath -File -Recurse) {
                    $rel = [IO.Path]::GetRelativePath($CsgoRoot, $file.FullName).Replace("\", "/")
                    $backupRel = "runtime/$rel"
                    $backupDst = Join-Path $tmpDir ($backupRel.Replace("/", "\"))
                    $dstParent = Split-Path -Parent $backupDst
                    if (-not (Test-Path -LiteralPath $dstParent)) {
                        New-Item -ItemType Directory -Path $dstParent -Force | Out-Null
                    }
                    Copy-Item -LiteralPath $file.FullName -Destination $backupDst -Force
                    $originalHash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                    $backupHash = (Get-FileHash -LiteralPath $backupDst -Algorithm SHA256).Hash.ToLowerInvariant()
                    if ($originalHash -ne $backupHash) {
                        throw "Snapshot verification hash mismatch for $rel"
                    }
                    $backedUpRuntimeFiles.Add([PSCustomObject]@{
                        relative_path = $rel
                        backup_path = $backupRel
                        size = $file.Length
                        sha256 = $originalHash
                    })
                }
            }
        }

        $backedUpComponents = [Collections.Generic.List[PSCustomObject]]::new()

        foreach ($comp in $Global:DiagnosticTargetComponents) {
            $activePath = Join-Path $CsgoRoot ($comp.Active.Replace("/", "\"))
            $activeExisted = Test-Path -LiteralPath $activePath
            $activeSha = $null
            $activeSize = $null
            $activeBackup = $null

            if ($activeExisted) {
                $activeFile = Get-Item -LiteralPath $activePath
                $activeSize = $activeFile.Length
                $activeSha = (Get-FileHash -LiteralPath $activePath -Algorithm SHA256).Hash.ToLowerInvariant()
                $activeBackup = "components/$($comp.Active)"
                $dst = Join-Path $tmpDir ($activeBackup.Replace("/", "\"))
                $dstParent = Split-Path -Parent $dst
                if (-not (Test-Path -LiteralPath $dstParent)) { New-Item -ItemType Directory -Path $dstParent -Force | Out-Null }
                Copy-Item -LiteralPath $activePath -Destination $dst -Force
                $dstHash = (Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash.ToLowerInvariant()
                if ($activeSha -ne $dstHash) { throw "Snapshot hash mismatch for $($comp.Active)" }
            }

            $disabledPath = Join-Path $CsgoRoot ($comp.Disabled.Replace("/", "\"))
            $disabledExisted = Test-Path -LiteralPath $disabledPath
            $disabledSha = $null
            $disabledSize = $null
            $disabledBackup = $null

            if ($disabledExisted) {
                $disabledFile = Get-Item -LiteralPath $disabledPath
                $disabledSize = $disabledFile.Length
                $disabledSha = (Get-FileHash -LiteralPath $disabledPath -Algorithm SHA256).Hash.ToLowerInvariant()
                $disabledBackup = "components/$($comp.Disabled)"
                $dst = Join-Path $tmpDir ($disabledBackup.Replace("/", "\"))
                $dstParent = Split-Path -Parent $dst
                if (-not (Test-Path -LiteralPath $dstParent)) { New-Item -ItemType Directory -Path $dstParent -Force | Out-Null }
                Copy-Item -LiteralPath $disabledPath -Destination $dst -Force
                $dstHash = (Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash.ToLowerInvariant()
                if ($disabledSha -ne $dstHash) { throw "Snapshot hash mismatch for $($comp.Disabled)" }
            }

            $backedUpComponents.Add([PSCustomObject]@{
                name = $comp.Name
                active_path = $comp.Active
                active_existed = [bool]$activeExisted
                active_size = $activeSize
                active_sha256 = $activeSha
                active_backup = $activeBackup
                disabled_path = $comp.Disabled
                disabled_existed = [bool]$disabledExisted
                disabled_size = $disabledSize
                disabled_sha256 = $disabledSha
                disabled_backup = $disabledBackup
            })
        }

        $snapshotObj = [ordered]@{
            schema_version = 1
            created_at = (Get-Date -Format "o")
            csgo_root = $CsgoRoot
            runtime_trees = $Global:DiagnosticRuntimeTrees
            runtime_files = @($backedUpRuntimeFiles)
            component_states = @($backedUpComponents)
        }

        $manifestJson = $snapshotObj | ConvertTo-Json -Depth 6
        $manifestJson | Set-Content -LiteralPath (Join-Path $tmpDir "snapshot-manifest.json") -Encoding utf8
        "completed" | Set-Content -LiteralPath (Join-Path $tmpDir ".completed") -Encoding utf8

        if (Test-Path -LiteralPath $snapshotDir) {
            Remove-Item -LiteralPath $snapshotDir -Recurse -Force
        }
        Move-Item -LiteralPath $tmpDir -Destination $snapshotDir -Force
        Write-Host "Snapshot successfully created: $($backedUpRuntimeFiles.Count) runtime files, $($backedUpComponents.Count) components." -ForegroundColor Green
        return $snapshotObj
    }
    catch {
        Write-Warning "Snapshot creation failed: $($_.Exception.Message). Cleaning up temporary files."
        if (Test-Path -LiteralPath $tmpDir) {
            Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        throw
    }
}

function Restore-DiagnosticSnapshot {
    param(
        [string]$CsgoRoot,
        [switch]$RetainSnapshotOnSuccess
    )

    $snapshotDir = Join-Path $CsgoRoot ".csbip\diagnostic-snapshot"
    $snapshotManifestPath = Join-Path $snapshotDir "snapshot-manifest.json"
    $completionMarker = Join-Path $snapshotDir ".completed"

    if (-not (Test-Path -LiteralPath $snapshotManifestPath) -or -not (Test-Path -LiteralPath $completionMarker)) {
        throw "No valid diagnostic snapshot found at $snapshotDir. Cannot perform exact restore."
    }

    $manifest = Get-Content -LiteralPath $snapshotManifestPath -Raw | ConvertFrom-Json
    $manifestRoot = $manifest.csgo_root.TrimEnd('\', '/')
    $currentRoot = $CsgoRoot.TrimEnd('\', '/')
    if (-not [string]::Equals($manifestRoot, $currentRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Snapshot belongs to different root '$($manifest.csgo_root)', expected '$CsgoRoot'."
    }

    Write-Host "Restoring pre-diagnostic state from snapshot created at $($manifest.created_at)..."

    # Step 1: Purge current diagnostic runtime trees
    foreach ($tree in $manifest.runtime_trees) {
        $treePath = Join-Path $CsgoRoot ($tree.Replace("/", "\"))
        if (Test-Path -LiteralPath $treePath) {
            Remove-Item -LiteralPath $treePath -Recurse -Force
        }
    }

    # Step 2: Restore runtime files from snapshot
    foreach ($file in $manifest.runtime_files) {
        $src = Join-Path $snapshotDir ($file.backup_path.Replace("/", "\"))
        $dst = Join-Path $CsgoRoot ($file.relative_path.Replace("/", "\"))
        $parent = Split-Path -Parent $dst
        if (-not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        Copy-Item -LiteralPath $src -Destination $dst -Force
    }

    # Step 3: Remove current active and disabled states for the target components
    foreach ($comp in $Global:DiagnosticTargetComponents) {
        $activeFull = Join-Path $CsgoRoot ($comp.Active.Replace("/", "\"))
        if (Test-Path -LiteralPath $activeFull) { Remove-Item -LiteralPath $activeFull -Force }
        $disabledFull = Join-Path $CsgoRoot ($comp.Disabled.Replace("/", "\"))
        if (Test-Path -LiteralPath $disabledFull) { Remove-Item -LiteralPath $disabledFull -Force }
    }

    # Step 4: Restore components exactly according to snapshot
    foreach ($comp in $manifest.component_states) {
        if ($comp.active_existed) {
            $src = Join-Path $snapshotDir ($comp.active_backup.Replace("/", "\"))
            $dst = Join-Path $CsgoRoot ($comp.active_path.Replace("/", "\"))
            $parent = Split-Path -Parent $dst
            if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            Copy-Item -LiteralPath $src -Destination $dst -Force
        }
        if ($comp.disabled_existed) {
            $src = Join-Path $snapshotDir ($comp.disabled_backup.Replace("/", "\"))
            $dst = Join-Path $CsgoRoot ($comp.disabled_path.Replace("/", "\"))
            $parent = Split-Path -Parent $dst
            if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            Copy-Item -LiteralPath $src -Destination $dst -Force
        }
    }

    # Step 5: Clean diagnostic markers
    $m1 = Join-Path $CsgoRoot "diagnostic-state.json"
    if (Test-Path -LiteralPath $m1) { Remove-Item -LiteralPath $m1 -Force }
    $m2 = Join-Path $CsgoRoot ".csbip\diagnostic-state.json"
    if (Test-Path -LiteralPath $m2) { Remove-Item -LiteralPath $m2 -Force }
    $m3 = Join-Path $CsgoRoot "diagnostic-runtime-manifest.json"
    if (Test-Path -LiteralPath $m3) { Remove-Item -LiteralPath $m3 -Force }

    # Step 6: Verify restored state against snapshot
    Write-Host "Verifying restored state against snapshot..."
    $verifyFailures = [Collections.Generic.List[string]]::new()

    foreach ($file in $manifest.runtime_files) {
        $restored = Join-Path $CsgoRoot ($file.relative_path.Replace("/", "\"))
        if (-not (Test-Path -LiteralPath $restored)) {
            $verifyFailures.Add("Missing restored runtime file: $($file.relative_path)")
        } else {
            $actualHash = (Get-FileHash -LiteralPath $restored -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($actualHash -ne $file.sha256) {
                $verifyFailures.Add("Restored runtime file hash mismatch for $($file.relative_path): expected $($file.sha256), actual $actualHash")
            }
        }
    }

    # Verify no unexpected runtime residue exists in restored trees
    $restoredPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($file in $manifest.runtime_files) {
        $restoredPaths.Add($file.relative_path) | Out-Null
    }
    foreach ($tree in $manifest.runtime_trees) {
        $treePath = Join-Path $CsgoRoot ($tree.Replace("/", "\"))
        if (Test-Path -LiteralPath $treePath) {
            foreach ($actual in Get-ChildItem -LiteralPath $treePath -File -Recurse) {
                $rel = [IO.Path]::GetRelativePath($CsgoRoot, $actual.FullName).Replace("\", "/")
                if (-not $restoredPaths.Contains($rel)) {
                    $verifyFailures.Add("Unexpected runtime residue in restored tree: $rel")
                }
            }
        }
    }

    # Check component states
    foreach ($comp in $manifest.component_states) {
        $activeDst = Join-Path $CsgoRoot ($comp.active_path.Replace("/", "\"))
        $activeActual = Test-Path -LiteralPath $activeDst
        if ($activeActual -ne $comp.active_existed) {
            $verifyFailures.Add("Component $($comp.name) active state mismatch: expected $($comp.active_existed), found $activeActual")
        } elseif ($activeActual) {
            $hash = (Get-FileHash -LiteralPath $activeDst -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($hash -ne $comp.active_sha256) {
                $verifyFailures.Add("Component $($comp.name) active hash mismatch: expected $($comp.active_sha256), actual $hash")
            }
        }

        $disabledDst = Join-Path $CsgoRoot ($comp.disabled_path.Replace("/", "\"))
        $disabledActual = Test-Path -LiteralPath $disabledDst
        if ($disabledActual -ne $comp.disabled_existed) {
            $verifyFailures.Add("Component $($comp.name) disabled state mismatch: expected $($comp.disabled_existed), found $disabledActual")
        } elseif ($disabledActual) {
            $hash = (Get-FileHash -LiteralPath $disabledDst -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($hash -ne $comp.disabled_sha256) {
                $verifyFailures.Add("Component $($comp.name) disabled hash mismatch: expected $($comp.disabled_sha256), actual $hash")
            }
        }
    }

    if ($verifyFailures.Count -gt 0) {
        throw "Restore verification failed:`n$($verifyFailures -join "`n")"
    }

    if (-not $RetainSnapshotOnSuccess) {
        Remove-Item -LiteralPath $snapshotDir -Recurse -Force
        Write-Host "Snapshot successfully cleaned up after verified restore." -ForegroundColor Cyan
    }

    Write-Host "Pre-diagnostic state restored and verified successfully." -ForegroundColor Green
}
