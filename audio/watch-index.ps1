param([switch]$Once)

$ErrorActionPreference = "Stop"

$audioDirectory = $PSScriptRoot
$indexPath = Join-Path $audioDirectory "index.json"
$supportedExtensions = @(".mp3", ".ogg", ".wav", ".m4a", ".aac")
$eventSources = @(
  "AudioIndex.Created",
  "AudioIndex.Changed",
  "AudioIndex.Deleted",
  "AudioIndex.Renamed"
)

function Test-SupportedAudioFile {
  param([string]$Name)

  return $supportedExtensions -contains [System.IO.Path]::GetExtension($Name).ToLowerInvariant()
}

function Update-AudioIndex {
  $files = @(
    Get-ChildItem -LiteralPath $audioDirectory -File |
      Where-Object { Test-SupportedAudioFile $_.Name } |
      Select-Object -ExpandProperty Name |
      Sort-Object
  )
  $json = ConvertTo-Json -InputObject $files
  [System.IO.File]::WriteAllText(
    $indexPath,
    $json + [Environment]::NewLine,
    (New-Object System.Text.UTF8Encoding $false)
  )
  Write-Host "Updated audio/index.json with $($files.Count) audio file(s)."
}

$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = $audioDirectory
$watcher.Filter = "*"
$watcher.IncludeSubdirectories = $false
$watcher.NotifyFilter = [System.IO.NotifyFilters]::FileName -bor [System.IO.NotifyFilters]::LastWrite

foreach ($eventName in @("Created", "Changed", "Deleted", "Renamed")) {
  Register-ObjectEvent -InputObject $watcher -EventName $eventName -SourceIdentifier "AudioIndex.$eventName" | Out-Null
}

try {
  Update-AudioIndex
  if ($Once) {
    return
  }

  $watcher.EnableRaisingEvents = $true
  Write-Host "Watching $audioDirectory for audio file changes."

  while ($true) {
    $notification = Wait-Event -Timeout 1
    if ($null -eq $notification) {
      continue
    }

    Start-Sleep -Milliseconds 250
    $shouldUpdate = $false
    $pendingEvents = @(Get-Event | Where-Object { $eventSources -contains $_.SourceIdentifier })
    foreach ($pendingEvent in $pendingEvents) {
      $eventArgs = $pendingEvent.SourceEventArgs
      $names = @($eventArgs.Name)
      if ($eventArgs -is [System.IO.RenamedEventArgs]) {
        $names += $eventArgs.OldName
      }
      if ($names | Where-Object { $_ -and (Test-SupportedAudioFile $_) } | Select-Object -First 1) {
        $shouldUpdate = $true
      }
      Remove-Event -EventIdentifier $pendingEvent.EventIdentifier
    }

    if ($shouldUpdate) {
      Update-AudioIndex
    }
  }
}
finally {
  $watcher.EnableRaisingEvents = $false
  foreach ($eventSource in $eventSources) {
    Unregister-Event -SourceIdentifier $eventSource -ErrorAction SilentlyContinue
  }
  $watcher.Dispose()
}
