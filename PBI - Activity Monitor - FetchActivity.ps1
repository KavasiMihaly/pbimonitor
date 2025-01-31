#Requires -Modules @{ ModuleName="MicrosoftPowerBIMgmt"; ModuleVersion="1.2.1026" }

param(        
    $outputPath = ".\Data\Activity\{0:yyyy}\{0:MM}",   
    $configFilePath = ".\Config.json"
)

try
{
    Write-Host "Starting Power BI Activity Monitor Activity Fetch"

    $stopwatch = [System.Diagnostics.Stopwatch]::new()
    $stopwatch.Start()   

    $currentPath = (Split-Path $MyInvocation.MyCommand.Definition -Parent)

    Set-Location $currentPath

    if (Test-Path $configFilePath)
    {
        $config = Get-Content $configFilePath | ConvertFrom-Json
    }
    else
    {
        throw "Cannot find config file '$configFilePath'"
    }

    Write-Host "Getting OAuth Token"

    $credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $config.ServicePrincipal.AppId, ($config.ServicePrincipal.AppSecret | ConvertTo-SecureString -AsPlainText -Force)

    Connect-PowerBIServiceAccount -ServicePrincipal -Tenant $config.ServicePrincipal.TenantId -Credential $credential

    if ($config.Activity.LastRun)
    {
        $pivotDate = [datetime]::Parse($config.Activity.LastRun).ToUniversalTime()
    }
    else
    {
        $config | Add-Member -NotePropertyName "Activity" -NotePropertyValue @{"LastRun" = $null } -Force   

        $pivotDate = [datetime]::UtcNow.Date.AddDays(-30)
    }


    # Gets audit data daily

    while($pivotDate -le [datetime]::UtcNow)
    {           
        Write-Host "Getting audit data for: '$($pivotDate.ToString("yyyyMMdd"))'"

        $outputFilePath = ("$outputPath\{0:yyyyMMdd}.json" -f $pivotDate)

        $audits = Get-PowerBIActivityEvent -StartDateTime $pivotDate.ToString("s") -EndDateTime $pivotDate.AddHours(24).AddSeconds(-1).ToString("s") | ConvertFrom-Json

        $audits = @($audits[0])

        if ($audits.Count -gt 0)
        {
            Write-Host "'$($audits.Count)' audits"

            New-Item -Path (Split-Path $outputFilePath -Parent) -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

            ConvertTo-Json $audits -Compress -Depth 5 | Out-File $outputFilePath -force
        }
        else
        {
            Write-Warning "No audit logs for date: '$($pivotDate.ToString("yyyyMMdd"))'"
        }

        $config.Activity.LastRun = $pivotDate.Date.ToString("o")

        $pivotDate = $pivotDate.AddDays(1)

        # Save config 

        ConvertTo-Json $config | Out-File $configFilePath -force
    }

}
catch
{
    $ex = $_.Exception

    if ($ex.ToString().Contains("429 (Too Many Requests)"))
    {
        Write-Host "429 Throthling Error - Need to wait before making another request..." -ForegroundColor Yellow
    }  

    Write-Host $ex.ToString() -ForegroundColor Red

    throw
}
finally
{
    $stopwatch.Stop()

    Write-Host "Ellapsed: $($stopwatch.Elapsed.TotalSeconds)s"
}