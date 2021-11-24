
# input from exported CSV export of Windows Performance Counters
#   Get-Counter -Counter '\Process(*)\Working Set','\Process(*)\% Processor Time' `
#      -SampleInterval 10 -Continuous -ErrorAction SilentlyContinue `
#      | Export-Counter -Path perf.csv -FileFormat csv

# output to InfluxDV line protocol
#   https://docs.influxdata.com/influxdb/v1.8/write_protocols/line_protocol_tutorial/

# usage
#   . ./tools/convert-perf-csv.ps1
#   convertPerfCsv ../epperf/perf100.csv | Out-File ../perf.line
#   gc ../perf.line -First 5

# import (check filename in ./config/telegraf-import.conf)
#   telegraf --debug --config ./config/telegraf-import.conf 

function Parse-CounterName {
    param(
        [String]$name
    )
    $matchGroupValues = $name | Select-String "\\\\([^\\]+)\\([^(]+)\(([^)]+)\)\\(.+)" `
    | ForEach-Object { $_.Matches.groups } `
    | ForEach-Object { $_.Value }

    return [PSCustomObject]@{
        host     = $matchGroupValues[1];
        object   = $matchGroupValues[2];
        instance = $matchGroupValues[3];
        field    = $matchGroupValues[4];
    }
}

filter isNumeric() {
    return $_ -is [byte] -or $_ -is [int16] -or $_ -is [int32] -or $_ -is [int64]  `
        -or $_ -is [sbyte] -or $_ -is [uint16] -or $_ -is [uint32] -or $_ -is [uint64] `
        -or $_ -is [float] -or $_ -is [double] -or $_ -is [decimal]
}

function mapFieldName($field) {
    $fieldMap = @{
        "% processor time" = "Percent_Processor_Time";
        "working set"      = "Working_Set"
    }
    $mappedField = $fieldMap[$field]
    if ($mappedField) { return $mappedField }
    return $field
}

function ConvertFrom-PerformanceCounterCsvObject {
    param(
        [pscustomobject]$line
    )
    $ts = get-date ([datetime](($line.PSObject.Properties | Select-Object -First 1).value)) -UFormat %s
    return $line.PSObject.Properties | Select-Object -Skip 1 | foreach-object {
        $name = $_.Name
        $value = $_.value
        # "$name = $value"
        $c = Parse-CounterName $name
        $c | Add-Member -MemberType NoteProperty -Name ts -Value $ts
        $c | Add-Member -MemberType NoteProperty -Name value -Value $value
        $c
    } | Where-Object { $_.value -ne ' ' } `
    | Where-Object { $_.instance -notin "_total", "idle" } `
    | ForEach-Object { $_.value = [long]$_.value ; $_ }
}

function normalizeInstance($val) {
    $val.replace(' ','_').replace('#','_')
}

function convertPerfCsv($csvFilename) {
    Get-Content $csvFilename | ConvertFrom-Csv | ForEach-Object { 
        ConvertFrom-PerformanceCounterCsvObject $_ | Group-Object host, object, instance, ts
    } | ForEach-Object { 
        $fieldSet = ($_.Group | ForEach-Object { "$(mapFieldName $_.field)=$($_.value)" }) -join "," 
        "win_proc,host=$($_.Group[0].host),instance=$(normalizeInstance($_.Group[0].instance)),objectname=$($_.Group[0].object) $($fieldSet) $(($_.Group[0].ts))000000000"
    }
}

function importLineFile($filename) {
    $template = @"
[[outputs.influxdb]]
  urls = ["http://localhost:8086"]
  database = "telegraf"
  username = "telegraf"
  password = ""

[[inputs.tail]]
  files = ["$filename"]
  from_beginning = true
  data_format = "influx"
"@
    $tmpConfig = New-TemporaryFile
    $template | Out-File $tmpConfig

    Write-Host "using telegraf config $tmpConfig"
    & telegraf --debug --config $tmpConfig
}

function importCsvFile($filename) {
    $tmpLineFile = New-TemporaryFile
    Write-Host "Exporting CSV to line file $tmpLineFile"
    convertPerfCsv $filename | Out-File $tmpLineFile
    Write-Host "Importing line file $tmpLineFile"
    importLineFile $tmpLineFile
}

