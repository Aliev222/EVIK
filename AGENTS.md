<!-- gitnexus:start -->
# GitNexus — Code Intelligence

This project is indexed by GitNexus as **EVIK** (13928 symbols, 35493 relationships, 358 execution flows).

> Index stale? Run `node .gitnexus/run.cjs analyze --index-only` from the project root — it auto-selects an available runner. No `.gitnexus/run.cjs` yet? Bootstrap with `npx`, `bunx`, or `pnpm dlx` — e.g. `bunx gitnexus@latest analyze` (npm 11 npx crash; #1939).

## Always Do

- **MUST run impact analysis before editing.** Use `impact({target: "symbolName", direction: "upstream"})` (MCP) or `node .gitnexus/run.cjs impact "symbolName" --direction upstream --repo .` (CLI fallback); report callers, processes, and risk. Never substitute grep for graph analysis.
- **MUST analyze graph changes before committing.** Use `detect_changes({scope: "all"})` (MCP) or `node .gitnexus/run.cjs detect-changes --scope all --repo .` (CLI fallback). `partial: true` or `truncated: true` is not a clean check — a zero means unseen, not unaffected; re-run it. For regression review: `detect_changes({scope: "compare", base_ref: "main"})` or `node .gitnexus/run.cjs detect-changes --scope compare --base-ref "main" --repo .`.
- **MUST warn the user** if impact analysis returns HIGH or CRITICAL risk before proceeding with edits.
- **MUST treat `risk: UNKNOWN` as unresolved, not as low.** An empty caller set is not evidence the symbol is unused — it can also mean the callers are not resolvable by the index (plain-object property access, dynamic dispatch, cross-language calls). `impact` pairs `UNKNOWN` with a `riskNote` saying so. Confirm with a text search before treating the symbol as safe to change or delete; do not proceed on the strength of a zero.
- When exploring unfamiliar code, use `query({search_query: "concept"})` to find execution flows instead of grepping. It returns process-grouped results ranked by relevance.
- When you need full context on a specific symbol — callers, callees, which execution flows it participates in — use `context({name: "symbolName"})`.
- For security review, `explain({target: "fileOrSymbol"})` lists taint findings (source→sink flows; needs `analyze --pdg`).

## Never Do

- NEVER edit a function, class, or method before MCP/CLI impact analysis.
- NEVER ignore HIGH or CRITICAL risk warnings from impact analysis, and never read `UNKNOWN` as an all-clear — it means the walk could not answer, which is the one verdict that requires confirming by other means.
- NEVER rename symbols with find-and-replace — use `rename` which understands the call graph.
- NEVER commit before MCP/CLI graph change analysis.

## Resources

| Resource | Use for |
| --- | --- |
| `gitnexus://repo/EVIK/context` | Codebase overview, check index freshness |
| `gitnexus://repo/EVIK/clusters` | All functional areas |
| `gitnexus://repo/EVIK/processes` | All execution flows |
| `gitnexus://repo/EVIK/process/{name}` | Step-by-step execution trace |

## CLI

| Task | Read this skill file |
| --- | --- |
| Understand architecture / "How does X work?" | `.claude/skills/gitnexus-exploring/SKILL.md` |
| Blast radius / "What breaks if I change X?" | `.claude/skills/gitnexus-impact-analysis/SKILL.md` |
| Trace bugs / "Why is X failing?" | `.claude/skills/gitnexus-debugging/SKILL.md` |
| Rename / extract / split / refactor | `.claude/skills/gitnexus-refactoring/SKILL.md` |
| Tools, resources, schema reference | `.claude/skills/gitnexus-guide/SKILL.md` |
| Index, status, clean, wiki CLI commands | `.claude/skills/gitnexus-cli/SKILL.md` |

<!-- gitnexus:end -->

# Авро — правила работы Codex

Ты работаешь над production-приложением «Авро».

Стек:
- Flutter mobile
- Go backend
- PostgreSQL
- realtime / WebSocket
- карты и геолокация
- server-authoritative architecture

Твоя задача — не просто писать код.

Ты должен самостоятельно:
1. Понять реальную проблему.
2. Изучить существующую архитектуру и текущую реализацию.
3. Найти первопричину проблемы.
4. Проверить существующие решения и ограничения.
5. Рассмотреть несколько вариантов решения.
6. Выбрать наиболее надёжный и рациональный вариант.
7. Реализовать решение.
8. Написать или обновить необходимые тесты.
9. Специально попытаться сломать собственное решение.
10. Исправить найденные проблемы.
11. Проверить влияние изменений на остальные части системы.
12. Провести финальный review.
13. Только после этого считать задачу завершённой.

ВАЖНО:

Не переписывай код без необходимости.

Сначала изучай существующий код.

Не предполагай архитектуру — проверь её в репозитории.

Не считай задачу выполненной только потому, что:
- код компилируется;
- тесты проходят;
- проблема исчезла в одном сценарии.

Проверяй:
- edge cases;
- race conditions;
- network failures;
- reconnect;
- плохой интернет;
- повторные запросы;
- duplicate events;
- stale data;
- app background/foreground;
- restart приложения;
- backend failures;
- concurrent operations;
- безопасность;
- производительность.

### Работа с агентами

Не запускай дополнительных агентов без необходимости.

Используй максимум 2–3 специализированных агента одновременно.

Дополнительные агенты должны использоваться только тогда,
когда их независимый анализ реально повышает качество решения.

Предпочтительно:

1. Architect — анализ архитектуры и вариантов решения.
2. QA/Red Team — попытка сломать решение.
3. Security/Performance — только если задача действительно этого требует.

Не заставляй каждого агента перечитывать весь проект.

Каждый агент должен изучать только необходимые файлы.

Агенты должны возвращать короткий структурированный результат:

- Findings
- Risks
- Recommendation
- Files affected

Не создавай бесконечные циклы обсуждения между агентами.

Главный агент принимает финальное решение.

### Принцип работы

Сначала THINK.
Потом PLAN.
Потом IMPLEMENT.
Потом TEST.
Потом BREAK.
Потом FIX.
Потом REVIEW.

Не останавливайся на первом рабочем варианте,
если существуют очевидные способы его сломать.

При этом не усложняй систему без необходимости.

Цель:
надёжное production-решение с минимальным количеством изменений,
а не максимальное количество кода.
