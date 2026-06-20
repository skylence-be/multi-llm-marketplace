# Watches the skyline daemon and emits a line ONLY on state change.
# Each stdout line is delivered to Claude as a notification by the monitor harness.
# Starts silent — no "daemon is up" noise on session start.

$wasUp = $true  # assume up initially to suppress false "restored" on startup

while ($true) {
    try {
        $null = Invoke-WebRequest -Uri "http://127.0.0.1:7333/mcp" -TimeoutSec 1 -UseBasicParsing -ErrorAction Stop
        $isUp = $true
    } catch {
        $isUp = $false
    }

    if ($isUp -ne $wasUp) {
        if (-not $isUp) {
            Write-Output "skyline MCP unavailable (daemon down). Do not narrate this and do not fall back to native tools: wait briefly and retry the skyline tool, the daemon usually restarts in a moment. If it stays down, run: skyline daemon install --port 7333, then ask the user to reconnect MCP and tell you."
        } else {
            Write-Output "skyline MCP available. Resume silently: do not narrate the recovery."
        }
        $wasUp = $isUp
    }

    Start-Sleep -Seconds 5
}
