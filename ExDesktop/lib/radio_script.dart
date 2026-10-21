// The PowerShell helper that asks Windows about its own radios.
//
// Windows exposes exactly one user-level API for switching Wi-Fi and
// Bluetooth: Windows.Devices.Radios.Radio — the same one the taskbar's
// quick-settings panel uses, so it needs no elevation and no UAC prompt.
// PowerShell is the shortest bridge to it from Dart: the WinRT types are
// reachable through the ContentType=WindowsRuntime type resolver, and the
// script runs through the hidden process runner, so nothing appears on
// screen.
//
// The script speaks a tiny line protocol on stdout:
//
//   access=<Allowed|NotAllowed|...>
//   radio|<Kind>|<device name>|<State>
//   adapter|<adapter name>|<Status>|<MediaConnectionState>
//   ok|<RadioAccess>            (set mode)
//   err|<message>                (any failure)
//
// Placeholders __MODE__, __KIND__ and __STATE__ are filled in by the caller;
// the values are internal constants, never raw user input.

const String radioScriptTemplate = r'''
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$mode = '__MODE__'
$kind = '__KIND__'
$want = '__STATE__'

Add-Type -AssemblyName System.Runtime.WindowsRuntime | Out-Null

$radioType = [Type]::GetType('Windows.Devices.Radios.Radio, Windows.Devices.Radios, ContentType=WindowsRuntime')
if ($null -eq $radioType) { Write-Output 'err|no radio api'; exit 2 }

$asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
    $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]

function Await($op, $resultType) {
    $task = $asTask.MakeGenericMethod($resultType).Invoke($null, @($op))
    if (-not $task.Wait(8000)) { throw 'timeout' }
    $task.Result
}

function Get-Radios {
    $m = $radioType.GetMethod('GetRadiosAsync')
    Await ($radioType::GetRadiosAsync()) ($m.ReturnType.GetGenericArguments()[0])
}

function Get-WifiAdapter {
    try {
        Get-NetAdapter -ErrorAction Stop |
            Where-Object { $_.NdisPhysicalMedium -eq 1 } |
            Select-Object -First 1
    } catch { $null }
}

try {
    $accessOp = $radioType::RequestAccessAsync()
    $accessType = ($radioType.GetMethod('RequestAccessAsync').ReturnType.GetGenericArguments()[0])
    $access = Await $accessOp $accessType
    Write-Output ('access=' + $access.ToString())

    if ($mode -eq 'set') {
        $setMethod = $radioType.GetMethod('SetStateAsync')
        $stateType = $setMethod.GetParameters()[0].ParameterType
        $resultType = $setMethod.ReturnType.GetGenericArguments()[0]
        $value = [Enum]::Parse($stateType, $want)
        foreach ($r in @(Get-Radios)) {
            if ($r.Kind.ToString() -eq $kind) {
                $res = Await ($r.SetStateAsync($value)) $resultType
                Write-Output ('ok|' + $res.ToString())
                exit 0
            }
        }
        Write-Output ('err|no ' + $kind + ' radio')
        exit 3
    }

    $radios = @(Get-Radios)
    Write-Output ('count=' + $radios.Count)
    foreach ($r in $radios) {
        Write-Output ('radio|' + $r.Kind.ToString() + '|' + $r.Name + '|' + $r.State.ToString())
    }

    $wifi = Get-WifiAdapter
    if ($null -ne $wifi) {
        Write-Output ('adapter|' + $wifi.Name + '|' + $wifi.Status + '|' + $wifi.MediaConnectionState)
    }
} catch {
    Write-Output ('err|' + $_.Exception.Message)
    exit 4
}
''';

/// Script that reports the state of every radio and of the Wi-Fi adapter.
String buildRadioStateScript() => radioScriptTemplate
    .replaceAll('__MODE__', 'state')
    .replaceAll('__KIND__', '')
    .replaceAll('__STATE__', '');

/// Script that switches one radio on or off.
///
/// [kind] is the WinRT radio kind ('WiFi' or 'Bluetooth'), [on] the wanted
/// power state ('On' or 'Off').
String buildRadioSetScript({required String kind, required bool on}) =>
    radioScriptTemplate
        .replaceAll('__MODE__', 'set')
        .replaceAll('__KIND__', kind)
        .replaceAll('__STATE__', on ? 'On' : 'Off');
