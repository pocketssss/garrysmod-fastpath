# FastPath API

## Hook API
### Базовое использование

```lua
hook.Add("Think", "FastPathExample", function()
    local frameTime = FrameTime()
end)

hook.Remove("Think", "FastPathExample")
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

`hook.Debug("Think")` выводит зарегистрированные callbacks, приоритеты и внутренние позиции события.

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
