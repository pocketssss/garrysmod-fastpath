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
$lines = [Collections.Generic.List[string]]::new()
$lines.Add('<!-- FASTPATH_BENCH_START -->')
$lines.Add('## Реальные замеры в Garry''s Mod — 8 октября 2026')
$lines.Add('')
$lines.Add('Измерено в установленной игре, отдельно в server/client Lua realms. FastPath загружался в приватное окружение: глобальный hook игры не заменялся. Это сравнение функций и синтетической нагрузки, а не обещание прироста FPS на любом сервере.')
$lines.Add('')
$lines.Add("Окружение: Windows, Intel Core i5-10600KF, GTX 1060 3 GB; GMod $($server.version), $($server.branch), Sandbox, gm_construct, 1280×720, локальный singleplayer/listen server, tick interval $(N ($server.workload.tick_interval * 1000)) мс. JIT: server=$($server.jit[0]), client=$($client.jit[0]); режим JIT не менялся. Workshop отключён (`-noworkshop`); локальные arcane, core, gmodhau_melee_sword_combat_wip, other_sweather, pockets_horse_rdr, rp_anvil, tools оставались включены. Это не чистый dedicated server.")
$lines.Add('')
$lines.Add('Методика: SysTime, 10 000 вызовов прогрева, 9 повторов по 100 000 вызовов (Add+Remove — 10 000 пар). Для каждой функции и стороны компилируется отдельный цикл, чтобы не делить JIT trace между разными callbacks. Порядок stock/FastPath чередуется, перед парой выполняется полный GC; GC во время измерений не отключается. Таблицы Color и новые Vector сохраняются в кольцевом буфере, чтобы JIT не исключил создание результата. Указана медиана, наносекунды на вызов, включая цикл и сохранение результата; накладные расходы не вычитаются. Разброс и все отдельные повторы — в JSON. Разница на уровне нескольких наносекунд чувствительна к JIT и обвязке.')
$lines.Add('')
$lines.Add('Коэффициент = stock / FastPath: больше 1 — FastPath быстрее, меньше 1 — медленнее.')
$lines.Add('')
$lines.Add('| Функция / сценарий | Stock server, нс | FastPath server, нс | × server | Stock client, нс | FastPath client, нс | × client |')
$lines.Add('|---|---:|---:|---:|---:|---:|---:|')
foreach ($row in $server.rows) {
    $other = $client.rows | Where-Object name -eq $row.name
    if (!$other) { throw "Missing client row $($row.name)" }
    $label = $row.name.Replace('|', '\|')
    $lines.Add("| $label | $(N $row.stock.median) | $(N $row.fast.median) | $(N $row.ratio) | $(N $other.stock.median) | $(N $other.fast.median) | $(N $other.ratio) |")
}
$lines.Add('')
$lines.Add('Vector clamp сравнивает GetClamped с эквивалентом Vector(math.Clamp(x), math.Clamp(y), math.Clamp(z)). Vector lerp сравнивает LerpTo с Set(LerpVector(...)); исходный вектор сбрасывается одинаково, stock создаёт временный Vector. Это композиции API, а не замена одноимённых нативных методов. Hook: строковые идентификаторы, callbacks без return; update — замена существующей функции, Add+Remove — пара операций при указанном числе постоянных callbacks. Loop control и hook.Call 0 могут почти полностью оптимизироваться JIT, их коэффициенты не доказывают практической пользы.')
$lines.Add('')
$lines.Add('### Нагрузка на кадр и тик')
$lines.Add('')
$lines.Add('На каждом клиентском Think / серверном Tick: 1000 dispatch × 100 callbacks = 100 000 вызовов callbacks. Фазы: idle → stock → FastPath → FastPath → stock → idle; каждая — 2 с прогрева + 5 с записи, камера фиксирована. CPU ниже — время только тестовой Lua-нагрузки, не CPU% всего процесса. FPS/частота тиков рассчитаны по среднему интервалу; p95 — худший p95 из двух фаз. Серверные Tick в singleplayer могут идти пачками, поэтому средняя частота информативнее медианы интервала.')
$lines.Add('')
$lines.Add('| Realm | Режим | CPU нагрузки, среднее мс | CPU нагрузки, макс p95 мс | Средний интервал, мс | FPS / тиков в секунду |')
$lines.Add('|---|---|---:|---:|---:|---:|')
foreach ($report in @($server, $client)) {
    foreach ($mode in @('idle', 'stock', 'fast')) {
        $phases = @($report.workload.phases | Where-Object mode -eq $mode)
        $count = 0; $cpuSum = 0; $intervalSum = 0
        foreach ($phase in $phases) {
            $count += $phase.interval.count
            $cpuSum += $phase.cpu.mean_ms * $phase.cpu.count
            $intervalSum += $phase.interval.mean_ms * $phase.interval.count
        }
        $interval = $intervalSum / $count
        $p95 = ($phases.cpu.p95_ms | Measure-Object -Maximum).Maximum
        $lines.Add("| $($report.realm) | $mode | $(N ($cpuSum / $count) 4) | $(N $p95 4) | $(N $interval) | $(N (1000 / $interval)) |")
    }
}
$lines.Add('')
$lines.Add("Клиент: fps_max=$($client.workload.cvars.fps_max), mat_vsync=$($client.workload.cvars.mat_vsync), fps_max_nofocus=$($client.workload.cvars.fps_max_nofocus), fps_max_menu=$($client.workload.cvars.fps_max_menu). Меню проверялось в каждом образце; видимых кадров меню: $(($client.workload.phases.menu_frames | Measure-Object -Sum).Sum). Кадров с фокусом окна: $(($client.workload.phases.focus_frames | Measure-Object -Sum).Sum) из $(($client.workload.phases | ForEach-Object { $_.interval.count } | Measure-Object -Sum).Sum). Даже этот тест не заменяет A/B-профилирование полного игрового сервера с реальными игроками, физикой и сетевым трафиком.")
$lines.Add('')
$lines.Add('### Что ускорять по результатам')
$lines.Add('')
$lines.Add('- Использовать быстрый hook dispatch там, где много стабильно зарегистрированных callbacks. Регистрацию делать при загрузке, а не каждый Think: Add/Remove копирует массивы и при 100 callbacks существенно проигрывает stock.')
$lines.Add('- Не считать Max2/Min3, Clamp или Color гарантированно быстрее stock: смотреть столбец нужного realm. Для часто используемых постоянных цветов лучше заранее создать Color и переиспользовать его, чем выбирать новый конструктор каждый кадр.')
$lines.Add('- Использовать Unpack/SetUnpacked и методы Vector без Get в горячих путях, где допустимо менять существующий вектор; избегать лишних временных Vector. Нативные Length/Distance/Dot/Cross не заменять без отдельных замеров.')
$lines.Add('- Не вызывать hook.GetTable в каждом кадре: FastPath создаёт новый снимок таблиц. Stock возвращает внутреннюю таблицу, поэтому изменение результата GetTable имеет другую семантику.')
$lines.Add('- qsin/qcos/sincos применять только при допустимой погрешности; SharedRandomFast — другой генератор с общим состоянием, не эквивалент util.SharedRandom или math.random.')
$lines.Add('')
$lines.Add("Максимальная абсолютная ошибка на 20 001 точке [-π, π]: qsin=$(N $server.accuracy.qsin 8), qcos=$(N $server.accuracy.qcos 8), sincos sin=$(N $server.accuracy.sincos_sin 8), sincos cos=$(N $server.accuracy.sincos_cos 8). Это ошибка на проверенной сетке, не математическая верхняя граница для любых входов.")
$lines.Add('')
$lines.Add('Исправлены обнаруженные ошибки совместимости: загрузчик переносит уже зарегистрированные hooks и не переисполняет успешно загруженные библиотеки; Color/ColorAlpha трактуют alpha=false как 255, как stock. Проверки false return + 6 значений, fallback gamemode, 360 HSV/HSL входов и повторной загрузки прошли в обоих realms. Это ограниченный набор проверок, не доказательство совместимости со всеми аддонами.')
$lines.Add('')
$lines.Add('### Повторить замеры')
$lines.Add('')
$lines.Add('Бенчмарк рассчитан на checkout addons/garrysmod-fastpath с корневыми lua/ и вложенной glibus/. Он не подключает FastPath к обычной игре. Для обычной установки библиотеки по-прежнему копировать glibus/ как отдельный аддон.')
$lines.Add('')
$lines.Add('1. Создать пустой файл benchmarks/RUN_ONCE в checkout.')
$lines.Add('2. Запустить GMod: -windowed -w 1280 -h 720 -novid -noworkshop -condebug +fps_max 300 +fps_max_nofocus 300 +fps_max_menu 300 +mat_vsync 0 +sv_lan 1 +map gm_construct.')
$lines.Add('3. Не открывать меню и не перемещать камеру до COMPLETE client в console.log. Server тестируется первым, затем client; JSON лежат в garrysmod/data/fastpath_bench/.')
$lines.Add('4. Удалить RUN_ONCE, чтобы следующий запуск игры не запускал тест. Альтернатива на загруженной карте: lua_run include("fastpath/benchmark.lua") из консоли локального сервера; client запускается после server автоматически.')
$lines.Add('5. Скопировать server.json/client.json в benchmarks/2026-10-08/ и выполнить powershell -NoProfile -ExecutionPolicy Bypass -File benchmarks/update-readme.ps1. Скрипт откажется публиковать незавершённые результаты, проваленные проверки или фазы с открытым меню.')
$lines.Add('')
$lines.Add('Данные: [server.json](benchmarks/2026-10-08/server.json), [client.json](benchmarks/2026-10-08/client.json), [сцена](benchmarks/2026-10-08/scene.png). [Прогон до исправлений](benchmarks/2026-10-08-before-fixes/server.json) сохранён только как воспроизведение ошибок; его FPS ограничены меню и не используются в итоговой таблице.')
$lines.Add('')
$lines.Add('Документация Facepunch: [SysTime для бенчмарков](https://wiki.facepunch.com/gmod/Global.SysTime), [параметры запуска](https://wiki.facepunch.com/gmod/Command_Line_Parameters), [jit.status](https://wiki.facepunch.com/gmod/jit.status). Для фонового теста отдельно задан [fps_max_nofocus](https://commits.facepunch.com/598794). CRC исходников записаны в JSON для сопоставления результатов с кодом.')
$lines.Add('<!-- FASTPATH_BENCH_END -->')
$path = Join-Path $PSScriptRoot '../README.md'
$readme = [IO.File]::ReadAllText($path)
$section = ($lines -join "`n") + "`n`n"
if ($readme.Contains('<!-- FASTPATH_BENCH_START -->')) {
    $readme = [regex]::Replace($readme, '(?s)<!-- FASTPATH_BENCH_START -->.*?<!-- FASTPATH_BENCH_END -->\s*', [Text.RegularExpressions.MatchEvaluator]{ param($m) $section })
} else {
    $readme = $readme.Replace('## Credits', $section + '## Credits')
}
[IO.File]::WriteAllText($path, $readme, [Text.UTF8Encoding]::new($false))
