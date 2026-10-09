<img src="assets/icon.png" width="128" alt="ClaudeStatus icon">

# ClaudeStatus

A traffic light for [Claude Code](https://code.claude.com) in the macOS menu bar. One dot shows how all your Claude Code sessions are doing:

| Dot | Meaning |
|---|---|
| grey | idle: nothing running, or Claude finished and has nothing to ask |
| green | working |
| yellow, blinking | Claude is waiting for you: a permission prompt, a question dialog, a plan to approve, or a reply that ends with a question |
| red, blinking | the turn failed (API error, rate limit…) |

With several sessions the worst one wins. Click the dot to see every session, its project folder and how long it has been in that state.

Works with everything that runs Claude Code hooks: the `claude` CLI, the **Code** tab of the Claude desktop app, and the VS Code / JetBrains extensions. Plain chats on claude.ai don't run hooks and aren't shown.

*Unofficial: not made or endorsed by Anthropic. Built with the help of an AI assistant (Claude).*

[Русская версия ниже](#по-русски)

## Install

**Requires macOS 13 or newer.**

### Option A: download

1. Download `ClaudeStatus.zip` from Releases, unzip it, move `ClaudeStatus.app` to `/Applications` (or `~/Applications`).
2. The app is not notarized by Apple, so the first launch is blocked. Either right-click the app → **Open** → **Open**, or (macOS 15+) try to open it once, then go to **System Settings → Privacy & Security** and click **Open Anyway**. Or in Terminal:
   ```bash
   xattr -d com.apple.quarantine /Applications/ClaudeStatus.app
   ```

### Option B: build from source (no Gatekeeper warning)

Needs Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone <this repo> && cd claude-status-light && app/build.sh
```

The app lands in `build/ClaudeStatus.app`.

### Connect to Claude Code

On first launch the app offers to connect; later it's in the menu: **Connect to Claude Code…**. It shows exactly what it adds to `~/.claude/settings.json`, saves a backup next to it (`settings.json.bak-claudestatus-…`) and keeps your other settings and hooks. **Disconnect from Claude Code…** removes only its own hooks. Running sessions pick the change up on their next event.

Turn on **Open at Login** in the menu to start it automatically.

## Privacy and footprint

- The hook script (`report.sh`, plain bash, no python/jq) writes one line per session to `~/.claude-status/<session id>`: state, project folder name, event name. Your prompts and Claude's replies are not stored; the end of the last reply is only checked for a question mark and then discarded.
- No network access, no telemetry, no analytics.
- No polling: the app sleeps until a status file changes (FSEvents). The blink timer exists only while the dot is yellow or red. About 0.1% CPU and ~20 MB of memory.
- Hooks run with `"async": true`, so Claude never waits for them.

## Uninstall

Menu → **Disconnect from Claude Code…**, turn off **Open at Login**, quit, then delete the app, `~/.claude-status` and `~/Library/Application Support/ClaudeStatus`.

## License

MIT, see [LICENSE](LICENSE).

---

## По-русски

Светофор для [Claude Code](https://code.claude.com) в строке меню macOS. Одна точка показывает состояние всех сессий Claude Code:

| Точка | Значение |
|---|---|
| серая | ничего не происходит или Claude закончил и ни о чём не спрашивает |
| зелёная | Claude работает |
| жёлтая, мигает | Claude ждёт вас: разрешение, вопрос с вариантами, план на одобрение или ответ с вопросом в конце |
| красная, мигает | ход завершился ошибкой (ошибка API, лимит…) |

Если сессий несколько, показывается самая тревожная. По клику видно все сессии, папку проекта и сколько времени сессия в этом состоянии.

Работает со всем, что запускает хуки Claude Code: CLI `claude`, вкладка **Code** в приложении Claude для компьютера, расширения для VS Code и JetBrains. Обычные чаты на claude.ai хуки не запускают и не отображаются.

*Неофициальное приложение, Anthropic к нему отношения не имеет. Сделано с помощью ИИ-ассистента (Claude).*

### Установка

Нужна macOS 13 или новее.

**Скачать.** Скачайте `ClaudeStatus.zip` из Releases, распакуйте, перенесите `ClaudeStatus.app` в «Программы». Приложение не нотаризовано Apple, поэтому первый запуск заблокирован: правый клик по приложению → **Открыть** → **Открыть**, либо (macOS 15+) попробуйте открыть, затем **Системные настройки → Конфиденциальность и безопасность → Всё равно открыть**. Или в Терминале:

```bash
xattr -d com.apple.quarantine /Applications/ClaudeStatus.app
```

**Собрать из исходников** (без предупреждения): нужны Command Line Tools (`xcode-select --install`), затем `app/build.sh`, приложение появится в `build/ClaudeStatus.app`.

**Подключение.** При первом запуске приложение само предложит подключиться, потом это пункт меню **Connect to Claude Code…**. Оно покажет, что именно добавит в `~/.claude/settings.json`, сохранит рядом резервную копию и не тронет ваши остальные настройки и хуки. **Disconnect from Claude Code…** убирает только свои хуки. Пункт **Open at Login** включает автозапуск.

### Приватность

Хук пишет только состояние, имя папки проекта и имя события в `~/.claude-status`. Тексты запросов и ответов не сохраняются: конец последнего ответа только проверяется на знак вопроса. Никакой сети и телеметрии. Без опроса: приложение спит, пока не изменится файл состояния; около 0.1% CPU и ~20 МБ памяти.

### Удаление

Меню → **Disconnect from Claude Code…**, выключить **Open at Login**, выйти, удалить приложение, `~/.claude-status` и `~/Library/Application Support/ClaudeStatus`.
