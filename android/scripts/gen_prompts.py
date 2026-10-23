"""android/app/src/main/java/com/pufy/app/ai/Prompts.kt'yi iOS kaynağından üretir.
Yönerge TEK yerde yazılır (Swift); Android aynı metni kullanır.
Çalıştır (proje kökünden): python3 android/scripts/gen_prompts.py"""
import re
from pathlib import Path

root = Path(__file__).resolve().parents[2]
src = lambda name: (root / name).read_text(encoding='utf-8')


def swift_literal(text, start):
    """text[start] bir '\"\"\"' satırının başlangıcı olmalı → içerik (girinti kapanış satırına göre atılır)"""
    j = text.index('"""', start) + 3
    k = text.index('"""', j)
    close_line_start = text.rfind('\n', 0, k) + 1
    indent = k - close_line_start
    lines = text[j:k].split('\n')[1:]
    body = '\n'.join(l[indent:] if len(l) >= indent else l.strip() for l in lines)
    if body.endswith('\n'):
        body = body[:-1]
    body = re.sub(r'\\\n', '', body)      # satır devamı
    return body


def to_kotlin(body, mapping, name):
    # Önce Swift kaçışlarını işaretle, sonra Kotlin'e çevir
    out = []
    i = 0
    while i < len(body):
        c = body[i]
        if c == '\\' and i + 1 < len(body):
            n = body[i + 1]
            if n == '(':
                depth, j = 1, i + 2
                while depth:
                    if body[j] == '(':
                        depth += 1
                    elif body[j] == ')':
                        depth -= 1
                    j += 1
                expr = body[i + 2:j - 1]
                assert expr in mapping, f'{name}: eşlenmemiş Swift değişkeni: {expr}'
                out.append('${' + mapping[expr] + '}')
                i = j
                continue
            if n == '\\':
                out.append('\\'); i += 2; continue
            if n == '"':
                out.append('"'); i += 2; continue
            if n == 'n':
                out.append('\n'); i += 2; continue
            if n == 't':
                out.append('\t'); i += 2; continue
        if c == '$':
            out.append("${'$'}"); i += 1; continue
        out.append(c)
        i += 1
    s = ''.join(out)
    assert '"""' not in s
    return s


def literal_after(text, marker):
    i = text.index(marker)
    return swift_literal(text, i)


cvm = src('ChatViewModel.swift')
drm = src('DeepResearchManager.swift')
qr = src('QueryRouter.swift')
cards = src('InteractiveCards.swift')

# 1) Ana sohbet yönergesi
a = cvm.index('        return """\n        \\(Self.answerLanguageRule)\n        Sen Pufy\'sin')
main = swift_literal(cvm, a + len('        return '))
main_map = {
    'turkishNow': 'p.turkishNow',
    'currentISODateTime': 'p.iso',
    'userName': 'p.userName',
    'Self.timeZoneGuide(now: now)': 'timeZoneGuide()',
    'memoryPromptText(for: memoryQuery)': 'p.memory',
    'remindersListText': 'p.reminders',
    'pastText': 'p.past',
    'taskRules': 'p.taskRules',
    'notesSection': 'p.notesSection',
    'reminderMode ? "\\nÖNEMLİ: Kullanıcı şu an özellikle hatırlatıcı kurmak istiyor. Hatırlatıcıyı mutlaka [REMINDER:] etiketiyle kur." : ""':
        'if (p.reminderMode) "\\nÖNEMLİ: Kullanıcı şu an özellikle hatırlatıcı kurmak istiyor. Hatırlatıcıyı mutlaka [REMINDER:] etiketiyle kur." else ""',
    'isSpaceChat ? "\\nZAMANLANMIŞ GÖREV SOHBETİ: Bu, zamanlanmış bir AI görevidir. Görevi verilen araştırma sonuçlarıyla eksiksiz yerine getir; [CHOICES] kullanma." : ""':
        'if (p.isSpaceChat) "\\nZAMANLANMIŞ GÖREV SOHBETİ: Bu, zamanlanmış bir AI görevidir. Görevi verilen araştırma sonuçlarıyla eksiksiz yerine getir; [CHOICES] kullanma." else ""',
    'deviceContextLine': 'p.deviceContextLine',
    'Self.answerLanguageRule': 'if (com.pufy.app.core.AppLocales.isEnglish()) "\\nANSWER LANGUAGE: Always reply in the language of the user\'s latest message (English message → English, Turkish → Turkish), even though these instructions are written in Turkish. If unclear, reply in English." else "\\nCEVAP DİLİ: Her zaman kullanıcının son mesajının dilinde cevap ver (İngilizce yazarsa İngilizce, Türkçe yazarsa Türkçe). Belirsizse Türkçe."',
}
main_kt = to_kotlin(main, main_map, 'ana yönerge')

# 2) Görev kuralları ve not bölümü (koşullu parçalar)
t = cvm.index('let taskRules = scheduling ? """')
task_full = to_kotlin(swift_literal(cvm, t + len('let taskRules = scheduling ? ')), {}, 'görev kuralları')
task_short = re.search(r'""" : "(.*?)"\n', cvm[t:]).group(1).replace('\\\'', "'")
n = cvm.index('let notesSection = noteRelated ? """')
notes_full = to_kotlin(swift_literal(cvm, n + len('let notesSection = noteRelated ? ')),
                       {'NoteStore.shared.promptText()': 'notesText'}, 'not bölümü')
n2 = cvm.index('""" : """', n)
notes_short = to_kotlin(swift_literal(cvm, n2 + len('""" : ')), {'NoteStore.shared.titlesText()': 'titles'}, 'kısa not')

# 3) Yazar talimatları ve görsel kuralları
def directive(marker):
    return to_kotlin(literal_after(drm, marker), {'escalationToken': 'ESCALATION', 'Self.escalationToken': 'ESCALATION'}, marker)

dirs = {k: directive(m) for k, m in [('mustSearch', 'case .mustSearch:'), ('maySearch', 'case .maySearch:'),
                                     ('noSearch', 'case .noSearch:'), ('deviceAction', 'case .deviceAction:')]}
draw = to_kotlin(literal_after(drm, 'static let drawRules ='), {}, 'görsel kuralları')

# 4) Hakemin "arama gerekir mi" yönergesi
judge_i = qr.index('let system = """')
judge = to_kotlin(swift_literal(qr, judge_i + len('let system = ')), {'f.string(from: Date())': 'today'}, 'hakem')

# 5) Sunum yönergesi
slides = to_kotlin(literal_after(cards, 'static let system = """'), {}, 'sunum')


# 5b) Kişisel Ağ hafıza motoru
mem = src('MemoryStore.swift')
mem_i = mem.index('let system = """\n        Sen Pufy\'nin kişisel hafıza motorusun')
memory_rules = to_kotlin(swift_literal(mem, mem_i + len('let system = ')), {}, 'hafıza')

# 5c) Uygulama ustası (AppBuilder) + planlayıcı ve inceleyici (AppAgent)
ab = src('AppBuilder.swift')
builder = to_kotlin(literal_after(ab, 'static let systemPrompt = """'), {}, 'uygulama ustası')
ag = src('AppAgent.swift')
plan_i = ag.index('let system = """\n        Sen üst düzey bir mobil ürün tasarımcısı')
planner = to_kotlin(swift_literal(ag, plan_i + len('let system = ')), {'existing': 'existing', 'assets.isEmpty ? "yok" : assets': 'assets.ifEmpty { "yok" }'}, 'planlayıcı')
rev_i = ag.index('let system = """\n        Sen titiz bir App Store inceleme ekibisin')
reviewer = to_kotlin(swift_literal(ag, rev_i + len('let system = ')), {}, 'inceleyici')

# 6) Hakem ipuçları ve zaman kalıpları (iOS QueryRouter / DeepResearchManager / WeatherService ile birebir aynı listeler)
def swift_array(text, name):
    m = re.search(r'static let ' + name + r' = (?:regexes\()?\[(.*?)\n\s*\]', text, re.S)
    assert m, name
    block = re.sub(r'^\s*//.*$', '', m.group(1), flags=re.M)     # yorum satırlarındaki örnekler liste değil
    items = re.findall(r'"((?:[^"\\]|\\.)*)"', block)
    return [i.replace('\\\\', '\\') for i in items]

weather = src('WeatherService.swift')
cue_lists = {name: swift_array(qr, name) for name in ['schedulingCues', 'deepResearchCues', 'freshCues', 'noteCues', 'personalCues',
             'topicFreshCues', 'explicitSearchCues', 'challengeCues', 'staticCues', 'imageStaticCues', 'deepCues']}
cue_lists['weatherCues'] = swift_array(weather, 'weatherCues')
cue_lists['notWeatherCues'] = swift_array(weather, 'notWeatherCues')
patterns = {name: swift_array(drm, name) for name in ['timedPatterns', 'eventPatterns']}


def kt_list(items):
    return 'listOf(' + ', '.join('"' + i.replace('\\', '\\\\').replace('"', '\\"').replace('$', '\\$') + '"' for i in items) + ')'


def kt(s):
    return '"""' + s + '"""'


out = f'''// OTOMATİK ÜRETİLDİ — kaynak: iOS ChatViewModel.buildAgentSystemPrompt, DeepResearchManager, QueryRouter, InteractiveCards.
// Yönerge değişirse: python3 android/scripts/gen_prompts.py (iOS ile Android aynı yönergeyi kullansın). ELLE DÜZENLEME.
@file:Suppress("all")
package com.pufy.app.ai

object Prompts {{
    const val ESCALATION = "[ARA]"

    class Params(
        val turkishNow: String, val iso: String, val userName: String, val memory: String, val reminders: String,
        val past: String, val taskRules: String, val notesSection: String,
        val reminderMode: Boolean = false, val isSpaceChat: Boolean = false,
        val deviceContextLine: String = "Bu cihaz: Android.",
    )

    fun agent(p: Params, timeZoneGuide: () -> String): String = {kt(main_kt)}

    val TASK_RULES_FULL = {kt(task_full)}
    val TASK_RULES_SHORT = {kt(task_short)}

    fun notesFull(notesText: String): String = {kt(notes_full)}
    fun notesShort(titles: String): String = {kt(notes_short)}

    val MUST_SEARCH = {kt(dirs['mustSearch'])}
    val MAY_SEARCH = {kt(dirs['maySearch'])}
    val NO_SEARCH = {kt(dirs['noSearch'])}
    val DEVICE_ACTION = {kt(dirs['deviceAction'])}
    val DRAW_RULES = {kt(draw)}

    fun searchJudge(today: String): String = {kt(judge)}

    val SLIDES = {kt(slides)}

    val MEMORY_EXTRACTOR = {kt(memory_rules)}

    val APP_BUILDER = {kt(builder)}
    fun appPlanner(existing: String, assets: String): String = {kt(planner)}
    val APP_REVIEWER = {kt(reviewer)}
}}

object Cues {{
{{CUES}}
}}
'''
cue_lines = [f'    val {k} = {kt_list(v)}' for k, v in cue_lists.items()]
cue_lines += [f'    val {k} = {kt_list(v)}.map {{ Regex(it, RegexOption.IGNORE_CASE) }}' for k, v in patterns.items()]
out = out.replace('{CUES}', '\n'.join(cue_lines))
target = root / 'android/app/src/main/java/com/pufy/app/ai/Prompts.kt'
target.write_text(out, encoding='utf-8')
print('üretildi:', target.relative_to(root), len(out), 'karakter')
