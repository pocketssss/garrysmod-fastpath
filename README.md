# GLua FastPath

Набор низкоуровневых оптимизаций для **Garry's Mod / LuaJIT**.

GLua FastPath не является универсальным «FPS booster». Проект заменяет стандартную систему `hook` собственной реализацией и добавляет функции для `math`, `Vector` и `Color`.

Основная цель - уменьшить накладные расходы в горячих Lua-путях, не заменяя быстрые нативные методы движка более медленным Lua-кодом.

> [!WARNING]
> Библиотека находится в экспериментальном состоянии. Замена глобального модуля `hook` влияет на весь сервер и клиентские аддоны. Перед использованием на сервере проверьте совместимость со своим набором аддонов.

## Возможности

### Оптимизированная система hooks

- плоские массивы callbacks в горячем пути;
- copy-on-write перестроение списков при добавлении и удалении hooks;
- обновление функции существующего hook за `O(1)`, если приоритет не изменился;
- приоритеты выполнения;
- pre/post hooks;
- автоматическое удаление hook, привязанного к невалидной Entity;
- кэширование текущего gamemode;
- совместимый интерфейс `hook.Add`, `hook.Remove`, `hook.Run`, `hook.Call` и `hook.GetTable`;
- частичная совместимость с ULib;
- предупреждение о конфликте с DLib.

### Математические функции

- `math.NormalizeAngleRad`;
- `math.Max2`, `math.Min2`;
- `math.Max3`, `math.Min3`;
- `math.MaxT`, `math.MinT`;
- `math.sincos`;
- приближённые `math.qsin` и `math.qcos`;
- детерминированный shared random generator.

### Расширения Vector

- `Vector:Clamp` и `Vector:GetClamped`;
- `Vector:Min`, `Vector:Max`;
- `Vector:GetMin`, `Vector:GetMax`;
- `Vector:ClampLength` и `Vector:GetClampedLength`;
- `Vector:LerpTo`.

Нативные методы вроде `Length`, `Distance`, `Dot`, `Cross`, `Normalize` и `DistToSqr` намеренно не переопределяются: реализации движка на C++ быстрее Lua-кода.

## Установка

Скопируйте каталог `glibus` в папку аддонов Garry's Mod:

```text
garrysmod/
└── addons/
    └── fastpath/
        └── lua/
            ├── autorun/
            │   └── libs_init.lua
            └── libs/
                ├── hook.lua
                ├── math.lua
                ├── vector.lua
                └── color.lua
```

После запуска `libs_init.lua` загрузчик автоматически подключит библиотеки в server/client realms и выведет результат загрузки в консоль:

```text
[lib] loaded 4/4 in 0.0 ms
```

Отдельная конфигурация не требуется.

## Hook API
### Базовое использование

```lua
hook.Add("Think", "GlibusExample", function()
    local frameTime = FrameTime()
end)

hook.Remove("Think", "GlibusExample")
```

### Приоритеты
Числовые приоритеты ограничиваются диапазоном от `-2` до `2`:

```lua
hook.Add("PlayerSpawn", "BeforeMostHooks", function(ply)
end, HOOK_HIGH)

hook.Add("PlayerSpawn", "AfterMostHooks", function(ply)
end, HOOK_LOW)
```

| Константа | Значение | Поведение |
|---|---:|---|
| `HOOK_MONITOR_HIGH` | `-2` | Выполняется рано, return игнорируется |
| `HOOK_HIGH` | `-1` | Высокий приоритет |
| `HOOK_NORMAL` | `0` | Обычный приоритет |
| `HOOK_LOW` | `1` | Низкий приоритет |
| `HOOK_MONITOR_LOW` | `2` | Выполняется поздно, return игнорируется |

Дополнительные режимы:

| Константа | Поведение |
|---|---|
| `PRE_HOOK` | Выполняется до обычных hooks, return игнорируется |
| `PRE_HOOK_RETURN` | Выполняется до обычных hooks и может вернуть результат |
| `NORMAL_HOOK` | Обычный hook |
| `POST_HOOK_RETURN` | Получает результат dispatch и может заменить его |
| `POST_HOOK` | Выполняется после dispatch, return игнорируется |

### Post hook
Первым аргументом post hook получает таблицу результата:

```lua
hook.Add("PlayerCanHearPlayersVoice", "InspectVoiceResult", function(result, listener, talker)
    local source = result[1]
    local canHear = result[2]
    local is3D = result[3]
end, POST_HOOK)
```

Для `POST_HOOK_RETURN` callback может вернуть новое значение события.

Функция выводит зарегистрированные callbacks, приоритеты и внутренние позиции.

## Math API
```lua
local normalized = math.NormalizeAngleRad(math.pi * 3)
local minimum = math.Min3(10, 5, 20)
local sine, cosine = math.sincos(1.25)
```

### Быстрые приближения

```lua
local approximateSine = math.qsin(angle)
local approximateCosine = math.qcos(angle)
```

`qsin`, `qcos` и `sincos` обменивают точность на скорость. Не используйте их там, где ошибка вычисления влияет на физику, сетевую синхронизацию или security checks.

### Детерминированный random

```lua
math.SharedRandomSeed(1337)

local integer = math.SharedRandom(1, 100)
local fastInteger = math.SharedRandomFast(1, 100)
local fraction = math.SharedRandomFloat()
```

Генератор имеет общее состояние внутри realm. Повторная установка одинакового seed воспроизводит последовательность только при одинаковом порядке вызовов.

## Vector API
Методы без префикса `Get` изменяют исходный Vector. Методы с `Get` создают новый Vector.

```lua
local position = Vector(150, -20, 500)
position:Clamp(Vector(0, 0, 0), Vector(100, 100, 100))

local direction = Vector(100, 50, 25)
direction:ClampLength(32)

local interpolated = Vector(0, 0, 0)
interpolated:LerpTo(Vector(100, 100, 100), 0.5)
```

## Совместимость
- Garry's Mod LuaJIT;
- server и client realms;
- ULib: FastPath пытается предотвратить загрузку hook-библиотеки ULib;
- DLib: обнаруживается как потенциальный конфликт, но автоматически не отключается.


## Структура проекта
```text
glibus/
├── lua/
│   ├── autorun/
│   │   └── libs_init.lua
│   └── libs/
│       ├── hook.lua
│       ├── math.lua
│       ├── vector.lua
│       └── color.lua
└── README.md
```

<!-- FASTPATH_BENCH_START -->
## Реальные замеры в Garry's Mod — 8 октября 2026

Измерено в установленной игре, отдельно в server/client Lua realms. FastPath загружался в приватное окружение: глобальный hook игры не заменялся. Это сравнение функций и синтетической нагрузки, а не обещание прироста FPS на любом сервере.

Коэффициент = stock / FastPath: больше 1 — FastPath быстрее, меньше 1 — медленнее.

| Функция / сценарий | Stock server, нс | FastPath server, нс | × server | Stock client, нс | FastPath client, нс | × client |
|---|---:|---:|---:|---:|---:|---:|
| loop control | 1.06 | 1.06 | 1.00 | 1.07 | 1.07 | 1.01 |
| math.Clamp | 4.94 | 10.59 | 0.47 | 47.86 | 7.66 | 6.25 |
| math.max / Max2 | 8.11 | 12.43 | 0.65 | 8.00 | 12.55 | 0.64 |
| math.min / Min3 | 11.57 | 15.11 | 0.77 | 11.87 | 15.79 | 0.75 |
| math.sin / qsin | 6.67 | 3.74 | 1.78 | 6.76 | 3.87 | 1.74 |
| math.cos / qcos | 6.79 | 4.12 | 1.65 | 6.64 | 4.09 | 1.62 |
| sin+cos / sincos | 13.25 | 8.10 | 1.64 | 12.96 | 12.05 | 1.08 |
| math.random / SharedRandomFast | 5.08 | 7.76 | 0.65 | 5.09 | 7.74 | 0.66 |
| Color | 130.15 | 118.46 | 1.10 | 45.94 | 122.51 | 0.37 |
| ColorAlpha | 95.07 | 124.81 | 0.76 | 41.80 | 123.07 | 0.34 |
| HSVToColor | 127.79 | 134.34 | 0.95 | 380.03 | 139.23 | 2.73 |
| HSLToColor | 130.86 | 131.43 | 1.00 | 401.97 | 142.60 | 2.82 |
| Vector clamp (new) | 879.01 | 261.85 | 3.36 | 829.66 | 217.20 | 3.82 |
| Vector lerp (in place) | 341.73 | 295.09 | 1.16 | 328.25 | 295.49 | 1.11 |
| hook.Call 0 | 8.10 | 7.89 | 1.03 | 8.37 | 8.27 | 1.01 |
| hook.Call 1 | 107.56 | 21.65 | 4.97 | 100.57 | 22.27 | 4.52 |
| hook.Call 10 | 540.98 | 303.42 | 1.78 | 479.65 | 32.00 | 14.99 |
| hook.Call 100 | 4442.47 | 1897.23 | 2.34 | 4106.75 | 2023.28 | 2.03 |
| hook.Add update 1 | 108.05 | 114.47 | 0.94 | 127.13 | 132.04 | 0.96 |
| hook.Add+Remove 1 | 195.19 | 1127.14 | 0.17 | 209.83 | 701.14 | 0.30 |
| hook.Add update 100 | 108.72 | 140.96 | 0.77 | 117.63 | 141.88 | 0.83 |
| hook.Add+Remove 100 | 201.72 | 11332.10 | 0.02 | 225.24 | 11506.08 | 0.02 |

Vector clamp сравнивает GetClamped с эквивалентом Vector(math.Clamp(x), math.Clamp(y), math.Clamp(z)). Vector lerp сравнивает LerpTo с Set(LerpVector(...)); исходный вектор сбрасывается одинаково, stock создаёт временный Vector. Это композиции API, а не замена одноимённых нативных методов. Hook: строковые идентификаторы, callbacks без return; update — замена существующей функции, Add+Remove — пара операций при указанном числе постоянных callbacks. Loop control и hook.Call 0 могут почти полностью оптимизироваться JIT, их коэффициенты не доказывают практической пользы.

### Нагрузка на кадр и тик

На каждом клиентском Think / серверном Tick: 1000 dispatch × 100 callbacks = 100 000 вызовов callbacks. Фазы: idle → stock → FastPath → FastPath → stock → idle; каждая — 2 с прогрева + 5 с записи, камера фиксирована. CPU ниже — время только тестовой Lua-нагрузки, не CPU% всего процесса. FPS/частота тиков рассчитаны по среднему интервалу; p95 — худший p95 из двух фаз. Серверные Tick в singleplayer могут идти пачками, поэтому средняя частота информативнее медианы интервала.

| Realm | Режим | CPU нагрузки, среднее мс | CPU нагрузки, макс p95 мс | Средний интервал, мс | FPS / тиков в секунду |
|---|---|---:|---:|---:|---:|
| server | idle | 0.0008 | 0.0012 | 15.00 | 66.67 |
| server | stock | 4.6978 | 6.2164 | 15.00 | 66.66 |
| server | fast | 1.9765 | 2.7810 | 15.00 | 66.68 |
| client | idle | 0.0005 | 0.0010 | 4.39 | 227.66 |
| client | stock | 4.2608 | 5.6259 | 7.61 | 131.34 |
| client | fast | 2.0950 | 2.8079 | 5.15 | 194.02 |

Клиент: fps_max=300, mat_vsync=0, fps_max_nofocus=300, fps_max_menu=300. Меню проверялось в каждом образце; видимых кадров меню: 0. Кадров с фокусом окна: 0 из 5530. Даже этот тест не заменяет A/B-профилирование полного игрового сервера с реальными игроками, физикой и сетевым трафиком.

### Что ускорять по результатам

- Использовать быстрый hook dispatch там, где много стабильно зарегистрированных callbacks. Регистрацию делать при загрузке, а не каждый Think: Add/Remove копирует массивы и при 100 callbacks существенно проигрывает stock.
- Не считать Max2/Min3, Clamp или Color гарантированно быстрее stock: смотреть столбец нужного realm. Для часто используемых постоянных цветов лучше заранее создать Color и переиспользовать его, чем выбирать новый конструктор каждый кадр.
- Использовать Unpack/SetUnpacked и методы Vector без Get в горячих путях, где допустимо менять существующий вектор; избегать лишних временных Vector. Нативные Length/Distance/Dot/Cross не заменять без отдельных замеров.
- Не вызывать hook.GetTable в каждом кадре: FastPath создаёт новый снимок таблиц. Stock возвращает внутреннюю таблицу, поэтому изменение результата GetTable имеет другую семантику.
- qsin/qcos/sincos применять только при допустимой погрешности; SharedRandomFast — другой генератор с общим состоянием, не эквивалент util.SharedRandom или math.random.

Максимальная абсолютная ошибка на 20 001 точке [-π, π]: qsin=0.00109031, qcos=0.00109031, sincos sin=0.00449169, sincos cos=0.01996916. Это ошибка на проверенной сетке, не математическая верхняя граница для любых входов.

Исправлены обнаруженные ошибки совместимости: загрузчик переносит уже зарегистрированные hooks и не переисполняет успешно загруженные библиотеки; Color/ColorAlpha трактуют alpha=false как 255, как stock. Проверки false return + 6 значений, fallback gamemode, 360 HSV/HSL входов и повторной загрузки прошли в обоих realms. Это ограниченный набор проверок, не доказательство совместимости со всеми аддонами.

### Повторить замеры

Бенчмарк рассчитан на checkout addons/garrysmod-fastpath с корневыми lua/ и вложенной glibus/. Он не подключает FastPath к обычной игре. Для обычной установки библиотеки по-прежнему копировать glibus/ как отдельный аддон.

1. Создать пустой файл benchmarks/RUN_ONCE в checkout.
2. Запустить GMod: -windowed -w 1280 -h 720 -novid -noworkshop -condebug +fps_max 300 +fps_max_nofocus 300 +fps_max_menu 300 +mat_vsync 0 +sv_lan 1 +map gm_construct.
3. Не открывать меню и не перемещать камеру до COMPLETE client в console.log. Server тестируется первым, затем client; JSON лежат в garrysmod/data/fastpath_bench/.
4. Удалить RUN_ONCE, чтобы следующий запуск игры не запускал тест. Альтернатива на загруженной карте: lua_run include("fastpath/benchmark.lua") из консоли локального сервера; client запускается после server автоматически.
5. Скопировать server.json/client.json в benchmarks/2026-10-08/ и выполнить powershell -NoProfile -ExecutionPolicy Bypass -File benchmarks/update-readme.ps1. Скрипт откажется публиковать незавершённые результаты, проваленные проверки или фазы с открытым меню.

Данные: [server.json](benchmarks/2026-10-08/server.json), [client.json](benchmarks/2026-10-08/client.json), [сцена](benchmarks/2026-10-08/scene.png). [Прогон до исправлений](benchmarks/2026-10-08-before-fixes/server.json) сохранён только как воспроизведение ошибок; его FPS ограничены меню и не используются в итоговой таблице.

Документация Facepunch: [SysTime для бенчмарков](https://wiki.facepunch.com/gmod/Global.SysTime), [параметры запуска](https://wiki.facepunch.com/gmod/Command_Line_Parameters), [jit.status](https://wiki.facepunch.com/gmod/jit.status). Для фонового теста отдельно задан [fps_max_nofocus](https://commits.facepunch.com/598794). CRC исходников записаны в JSON для сопоставления результатов с кодом.
<!-- FASTPATH_BENCH_END -->

## Credits
Основные части проекта основаны на работе других разработчиков:

- **Hook system:** [Srlion](https://github.com/Srlion) — исходная архитектура и семантика priority hooks. Текущая версия переработана под flat arrays, segmented dispatch и copy-on-write обновление списков.
- **Math library:** [trojanhoes](https://github.com/trojanhoes) — основа математических helpers и быстрых приближений.

Все последующие изменения, интеграция и оптимизации должны сохранять эти attribution notices.
