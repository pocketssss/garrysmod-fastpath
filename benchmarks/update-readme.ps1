param([string]$Results = "$PSScriptRoot/2026-10-08")
$ErrorActionPreference = 'Stop'
$culture = [Globalization.CultureInfo]::InvariantCulture
function N($value, $digits = 2) { ([double]$value).ToString("F$digits", $culture) }
$server = Get-Content "$Results/server.json" -Raw -Encoding UTF8 | ConvertFrom-Json
$client = Get-Content "$Results/client.json" -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($report in @($server, $client)) {
    if (!$report.completed) { throw 'Incomplete benchmark' }
    if (@($report.compatibility | Where-Object { !$_.passed }).Count) { throw 'Compatibility checks failed' }
    if (@($report.workload.phases).Count -ne 6) { throw 'Missing workload phase' }
    foreach ($phase in $report.workload.phases) {
        if ($phase.interval.count -lt 30) { throw 'Insufficient workload samples' }
        if ($phase.menu_frames -gt 0) { throw 'Game menu affected workload' }
    }
}
function Average($report, $mode, $metric) {
    $total = 0; $count = 0
    foreach ($phase in @($report.workload.phases | Where-Object mode -eq $mode)) {
        $count += $phase.$metric.count
        $total += $phase.$metric.mean_ms * $phase.$metric.count
    }
    return $total / $count
}
$stockFps = 1000 / (Average $client 'stock' 'interval')
$fastFps = 1000 / (Average $client 'fast' 'interval')
$stockCpu = Average $server 'stock' 'cpu'
$fastCpu = Average $server 'fast' 'cpu'
$lines = [Collections.Generic.List[string]]::new()
$lines.Add('<!-- FASTPATH_BENCH_START -->')
$lines.Add('## Сравнение со стандартными функциями')
$lines.Add('')
$lines.Add('Замеры в GMod от 8 октября 2026. Коэффициент = время стандартной функции / время FastPath: **больше 1 — быстрее, меньше 1 — медленнее**. Server и client измерены отдельно; небольшие различия чувствительны к JIT.')
$lines.Add('')
$lines.Add('| Функция / сценарий | × Server | × Client |')
$lines.Add('|---|---:|---:|')
foreach ($row in $server.rows) {
    if ($row.name -in @('loop control', 'hook.Call 0')) { continue }
    $other = $client.rows | Where-Object name -eq $row.name
    if (!$other) { throw "Missing client row $($row.name)" }
    $label = $row.name.Replace('|', '\|')
    $lines.Add("| $label | $(N $row.ratio) | $(N $other.ratio) |")
}
$lines.Add('')
$lines.Add('Число у hook — количество callbacks. Update заменяет существующую функцию, Add+Remove измеряет пару операций. Vector clamp/lerp сравниваются с эквивалентами через стандартный API; тригонометрия и random имеют другую точность или семантику.')
$lines.Add('')
$lines.Add('### FPS и время Lua на сервере')
$lines.Add('')
$lines.Add('Синтетическая нагрузка: 1000 вызовов события с 100 callbacks на каждый кадр/тик. Это результат данного теста, а не ожидаемый прирост на любом сервере.')
$lines.Add('')
$lines.Add('| Показатель | Стандартные hooks | FastPath | Изменение |')
$lines.Add('|---|---:|---:|---:|')
$lines.Add("| Средний FPS | $(N $stockFps) | $(N $fastFps) | +$(N (($fastFps / $stockFps - 1) * 100) 1)% |")
$lines.Add("| Время тестовой Lua-нагрузки, мс/тик | $(N $stockCpu) | $(N $fastCpu) | −$(N ((1 - $fastCpu / $stockCpu) * 100) 1)% |")
$lines.Add('')
$lines.Add('Тест выполнен на локальном сервере с другими аддонами. Клиентское окно было без фокуса, с повышенным лимитом фонового FPS; меню закрыто. Сервер сохранил заданную частоту тиков. Измерено время тестового Lua-кода, а не загрузка процессора всего сервера.')
$lines.Add('')
$lines.Add('Практический вывод: FastPath полезнее для вызова стабильных списков hooks и работы с Vector. Max2/Min3, Color и частая регистрация hooks не дают универсального выигрыша.')
$lines.Add('')
$lines.Add('[Методика, исходные результаты и повторение теста](benchmarks/README.md).')
$lines.Add('<!-- FASTPATH_BENCH_END -->')
$path = Join-Path $PSScriptRoot '../README.md'
$readme = [IO.File]::ReadAllText($path)
$section = ($lines -join "`n") + "`n`n"
if (!$readme.Contains('<!-- FASTPATH_BENCH_START -->')) { throw 'Benchmark section marker missing' }
$readme = [regex]::Replace($readme, '(?s)<!-- FASTPATH_BENCH_START -->.*?<!-- FASTPATH_BENCH_END -->\s*', [Text.RegularExpressions.MatchEvaluator]{ param($m) $section })
[IO.File]::WriteAllText($path, $readme, [Text.UTF8Encoding]::new($false))
