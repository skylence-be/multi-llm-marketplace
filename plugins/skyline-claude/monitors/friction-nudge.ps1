# friction-nudge.ps1 - debounced friction reporter (tracks skylence-be/skyline#6).
#
# After the agent stops calling skyline tools for IDLE seconds, if new friction
# has been recorded since the last nudge, emit ONE line asking the agent to file it.
# Fires once per friction cluster, never mid-flow, never per event.
#
# INERT BY DESIGN when observability streams are off (the default): if the log
# files do not exist it simply never fires. Power on with:
#   skyline observability set --devlog on --audit on
# Tune with SKYLINE_FRICTION_IDLE_SECS; override data dir with SKYLINE_DATA_DIR.

$data   = if ($env:SKYLINE_DATA_DIR) { $env:SKYLINE_DATA_DIR } else { "$env:LOCALAPPDATA\skyline" }
$audit  = "$data\logs\audit.jsonl"
$devlog = "$data\logs\devlog.jsonl"
$idle   = if ($env:SKYLINE_FRICTION_IDLE_SECS) { [int]$env:SKYLINE_FRICTION_IDLE_SECS } else { 45 }
$state  = "$env:TEMP\skyline-friction-nudge.state"

function Get-FrictionCount {
    $count = 0
    @($devlog, "$devlog.1") | ForEach-Object {
        if (Test-Path $_) {
            $count += (Select-String -Path $_ -Pattern '"level":"(warn|error)"|guide-gate|stale[- ]?tag|reject|fallback').Count
        }
    }
    return $count
}

function Get-LastTs {
    $ts = 0L
    @($audit, $devlog) | ForEach-Object {
        if (Test-Path $_) {
            Select-String -Path $_ -Pattern '"ts":(\d+)' -AllMatches | ForEach-Object {
                foreach ($match in $_.Matches) {
                    $val = [long]$match.Groups[1].Value
                    if ($val -gt $ts) { $ts = $val }
                }
            }
        }
    }
    return $ts
}

while ($true) {
    Start-Sleep -Seconds 15

    if (-not (Test-Path $audit) -and -not (Test-Path $devlog)) { continue }

    $lt = Get-LastTs
    if ($lt -eq 0) { continue }
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    if (($now - $lt) -lt $idle) { continue }

    $fc   = Get-FrictionCount
    $prev = if (Test-Path $state) { try { [int](Get-Content $state -Raw).Trim() } catch { 0 } } else { 0 }

    if ($fc -gt $prev) {
        $new = $fc - $prev
        Write-Output "$new new skyline friction event(s) recorded since the last check (devlog warnings/errors: stale-tag rejections, guide-gate blocks, shell fallbacks). If any is a real defect, file it with skyline_report_issue after searching open AND closed issues; comment new evidence on a match instead of opening a duplicate."
        Set-Content -Path $state -Value "$fc" -NoNewline
    } elseif ($fc -lt $prev) {
        Set-Content -Path $state -Value "$fc" -NoNewline
    }
}
