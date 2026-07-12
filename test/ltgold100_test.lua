-- LTGOLD 100-sentence regression suite.
-- Expected outputs captured from LTPRO.EXE via DOSBox-X (LTGOLD/refs100/).
-- Each case is annotated with the T7/T8 rule group it primarily exercises.
-- Run with --dosbox to re-verify against the live LTPRO.EXE binary.
local utils = require "core.utils"
local parser = require "core.parser"
local compiler = require "core.compiler"
local load = require "core.load"

local verify_dosbox = false
for _, v in ipairs(arg or {}) do
  if v == "--dosbox" then verify_dosbox = true end
end

local file = assert(io.open("data/BASE.DIC", "r"))
local file2 = assert(io.open("data/BASE.RUS", "r"))
local en_ru = {}
compiler.base = {}
for line in file:lines() do
  load.lingua(en_ru, line:gsub("%b{}", ""):gsub("%.", ""):gsub("%*([A-Z])%1W", "*W"))
end
for line in file2:lines() do
  local w, code = line:match("^(.-)\x2a(.*)$")
  if code then compiler.base[utils.decode(w)] = code end
end
file:close(); file2:close()

-- {group, input, expected_ltgold_output}
local cases = {
  -- BASELINE — 10 existing regression sentences
  { "BASELINE", "He is in the house.",                                    "Он - в доме." },
  { "BASELINE", "She sat on the chair.",                                  "Она посидeла на стуле." },
  { "BASELINE", "She can speak Russian.",                                 "Она может сказать Русского." },
  { "BASELINE", "He must not go.",                                        "Он не должен придти." },
  { "BASELINE", "The dog that I saw ran away.",                           "Собака, которую Я видeл убегать." },
  { "BASELINE", "He was arrested by the police.",                         "Он арестовывался полицией." },
  { "BASELINE", "You are standing in an open field.",                     "Вы стоите в открытой области." },
  { "BASELINE", "The house door is open.",                                "Дверь{1.вход} дома открыта." },
  { "BASELINE", "He cannot go.",                                          "Он не может придти." },
  { "BASELINE", "She has been seen.",                                     "Она была увидена." },
  -- T7-PP — prepositional phrase guards (T7[0] P<$>N, T7[5,6] P<AOdD>[IH], T7[34] PM)
  { "T7-PP",   "He walked into the dark room.",                           "Он прошел в темную комнату." },
  { "T7-PP",   "She lives in a small village.",                           "Она живет в небольшой деревне." },
  { "T7-PP",   "They met at the old station.",                            "Они встретились на старой станции." },
  { "T7-PP",   "He put it on the table.",                                 "Он устанавливает это на стол{1.таблица}." },
  { "T7-PP",   "She sat under the big tree.",                             "Она посидeла под большим деревом." },
  { "T7-PP",   "He stood near the open door.",                            "Он стоял около открытой двери{1.вход}." },
  { "T7-PP",   "She looked at the white wall.",                           "Она смотрела на белую стену." },
  { "T7-PP",   "He ran from the burning house.",                          "Он побежал{1.выполнять} из горящего дома." },
  { "T7-PP",   "They came from a distant city.",                          "Они исходили из отдаленного города." },
  { "T7-PP",   "She handed it to him.",                                   "Она передала это ему." },
  -- T7-NP — noun phrase guards (T7[10] N<AOD>N, T7[11] i<AOD>N numerals, T7[25] I<AO>N)
  { "T7-NP",   "The old man walked slowly.",                              "Старый человек прошел медленно." },
  { "T7-NP",   "A small red ball fell down.",                             "Небольшой красный шар падал." },
  { "T7-NP",   "The three old wooden chairs broke.",                      "Три старых деревянных стула разрушили." },
  { "T7-NP",   "Five metric tons arrived.",                               "Пять метрических тонн прибыли." },
  { "T7-NP",   "Two large black dogs barked.",                            "Две большие черные собаки лаяли." },
  { "T7-NP",   "The long legal agreement was signed.",                    "Длинное юридическое соглашение было подписано{1.отмечать}." },
  { "T7-NP",   "His important new contract expired.",                     "Его важный новый контракт истек." },
  { "T7-NP",   "Several large trucks passed.",                            "Различные большие грузовики прошли." },
  { "T7-NP",   "The first annual report was ready.",                      "Первый годовой отчет был готовым." },
  { "T7-NP",   "Three big red boxes were delivered.",                     "Три больших красных ящика{1.бокс;рамка} были поставлены." },
  -- T7-AP — adjectival/participial phrase guards (T7[3] O<A>N, T7[4] Q<AO>N, T7[23,24,27,29])
  { "T7-AP",   "This agreement is final.",                                "Это соглашение конечно." },
  { "T7-AP",   "That old house burned.",                                  "Этот старый дом жегся{1.гореть;обжигать}." },
  { "T7-AP",   "What big dog bit him.",                                   "Какой большой собачий бит{1.кусочек} его." },
  { "T7-AP",   "The broken window needs repair.",                         "Разбитому окну нужен ремонт." },
  { "T7-AP",   "The written report was clear.",                           "Письменное сообщение было ясным." },
  { "T7-AP",   "The running water was cold.",                             "Водопровод был холодным." },
  { "T7-AP",   "He saw a moving truck.",                                  "Он видeл движущийся грузовик." },
  { "T7-AP",   "The stolen car was found.",                               "Украденный автомобиль был обнаружен." },
  { "T7-AP",   "The painted wall dried quickly.",                         "Закрашенная стена высушила быстро." },
  { "T7-AP",   "A known fact emerged.",                                   "Известный факт возник." },
  -- T7-VP — verbal phrase guards (T7[31] U<KD>[VX], T7[28] [GE]M, T7[32] VM, T7[33] V[,C]<C>V)
  { "T7-VP",   "He must go now.",                                         "Он должен придти теперь." },
  { "T7-VP",   "She must not stop.",                                      "Она не должна остановить." },
  { "T7-VP",   "He can speak and write.",                                 "Он может сказать и написать{1.записывать}." },
  { "T7-VP",   "She ran and jumped.",                                     "Она побежала{1.выполнять} и прыгнула." },
  { "T7-VP",   "He should not wait.",                                     "Он не должен ожидать." },
  { "T7-VP",   "They may come or go.",                                    "Они могут приходить или идти." },
  { "T7-VP",   "She told him.",                                           "Она сказала его." },
  { "T7-VP",   "He showed her.",                                          "Он показал ее." },
  { "T7-VP",   "They gave it to us.",                                     "Они давали это нам." },
  { "T7-VP",   "She asked him to go.",                                    "Она спросила его, чтобы придти." },
  -- T8-ESS — T8 essential records [0-12]: clause heads, existentials, relative clause boundary
  { "T8-ESS",  "He said that she could speak Russian.",                   "Он сказал, что она могла бы сказать Русского." },
  { "T8-ESS",  "The man who I saw ran away.",                             "Человек, который Я видeл убегать." },
  { "T8-ESS",  "She said that he must not go.",                           "Она сказала, что он не должен придти." },
  { "T8-ESS",  "He knew that it was done.",                               "Он знал, что он был сделан." },
  { "T8-ESS",  "The woman that he loved left.",                           "Женщина, которую он полюбил оставшийся." },
  { "T8-ESS",  "He can speak and she can write.",                         "Он может сказать и она может написать{1.записывать}." },
  { "T8-ESS",  "There is a problem here.",                                "Есть проблема здесь." },
  { "T8-ESS",  "There are many people outside.",                          "Есть многие люди за." },
  { "T8-ESS",  "He spoke about it to her.",                               "Он говорил о нем на ее." },
  { "T8-ESS",  "The report that he wrote was long.",                      "Сообщать Что он писал{1.записывать} было долго{2.длинно}." },
  -- T8-VERB — T8 verb-frame records [13-40]: finite/infinitive, perfect, progressive, conditional
  { "T8-VERB", "He can flob speak Russian.",                              "Он может flob говорит Русского." },
  { "T8-VERB", "She will speak Russian tomorrow.",                        "Она скажет Русского завтра." },
  { "T8-VERB", "He has spoken to her.",                                   "Он сказал на ее." },
  { "T8-VERB", "She had been waiting long.",                              "Она ожидала долго{1.длинно}." },
  { "T8-VERB", "He is speaking now.",                                     "Он говорит теперь." },
  { "T8-VERB", "She was writing a letter.",                               "Она писала письмо." },
  { "T8-VERB", "He would go if she asked.",                               "Он придет если она попросила." },
  { "T8-VERB", "She could have gone earlier.",                            "Она шла бы раньше." },
  { "T8-VERB", "He must have known it.",                                  "Он должен иметь известный это." },
  { "T8-VERB", "She may have seen him.",                                  "Она, возможно, увидeла его." },
  -- T8-COORD — T8 coordination records [64-73]: V and V, Y and Y, U and V
  { "T8-COORD","He came and she left.",                                   "Он приходил и она осталась." },
  { "T8-COORD","She spoke and he listened.",                              "Она говорила и он услышал." },
  { "T8-COORD","He stopped and she continued.",                           "Он остановил и она продолжила." },
  { "T8-COORD","She sat down and he stood up.",                           "Она села и он встал." },
  { "T8-COORD","He can speak and write Russian.",                         "Он может сказать и написать{1.записывать} Русского." },
  { "T8-COORD","She can read and understand it.",                         "Она может читать и понимать это." },
  { "T8-COORD","He went to the city and came back.",                      "Он шел в город и возвращатсья." },
  { "T8-COORD","She read the book and returned it.",                      "Она читает книгу и возвращенные это." },
  { "T8-COORD","He bought bread and she bought milk.",                    "Он купил хлеб и она купила молоко." },
  { "T8-COORD","She opened the door and he entered.",                     "Она открыла дверь{1.вход} и он ввел." },
  -- T8-REL — T8 relative clause records [39-44,58-63,77-82]: whose, which, of-whom, in-which
  { "T8-REL",  "The book whose cover I saw was old.",                     "Книга покрытие{1.кожух} которой Я видeл было старым." },
  { "T8-REL",  "The man whose car broke down called.",                    "Человек автомобиль которого сломало называло{1.вызывать;созывать}." },
  { "T8-REL",  "The city in which he lived was large.",                   "Город в   котором он жил было большим." },
  { "T8-REL",  "The woman of whom he spoke arrived.",                     "Женщина из   которой он говорил прибытый." },
  { "T8-REL",  "The house in which she grew up burned.",                  "Дом в   котором она стала взрослым жечь{1.гореть;обжигать}." },
  { "T8-REL",  "The contract which he signed expired.",                   "Контракт, который он подписал{1.отмечать} истеченный." },
  { "T8-REL",  "The letter that she wrote arrived.",                      "Письмо{1.буква}, которое она писала{2.записывать} прибытую." },
  { "T8-REL",  "The girl whom he loved left him.",                        "Девушка кому он полюбил оставшийся его." },
  { "T8-REL",  "The problem which arose was solved.",                     "Проблема, которая возникала был решен." },
  { "T8-REL",  "The report which he sent was lost.",                      "Сообщение, которое он послал был потерян." },
  -- T8-NEG — T8 negation records [32,33,48,51]: cannot, does-not, not-in, no-N
  { "T8-NEG",  "He cannot speak Russian.",                                "Он не может сказать Русского." },
  { "T8-NEG",  "She does not know him.",                                  "Она не знает его." },
  { "T8-NEG",  "He will not go there.",                                   "Он не придет там." },
  { "T8-NEG",  "She has not seen him.",                                   "Она не увидeла его." },
  { "T8-NEG",  "He did not write the report.",                            "Он не писал{1.записывать} сообщение." },
  { "T8-NEG",  "There is no problem here.",                               "Нет проблемы здесь." },
  { "T8-NEG",  "He is not in the house.",                                 "Он не - в доме." },
  { "T8-NEG",  "She must not leave now.",                                 "Она не должна оставить теперь." },
  -- T8-PASS — passive voice
  { "T8-PASS", "The window was broken by him.",                           "Окно разбивалось ним." },
  { "T8-PASS", "The letter was written by her.",                          "Письмо{1.буква} писалось{2.записывать} нею." },
}

local function translate(sentence)
  local ts = utils.tokenize(sentence, en_ru)
  parser.collect(en_ru, ts)
  local out = compiler.compile(ts, { quiet = true }) or ""
  return (out:match("^%s*(.-)%s*$") or out)
end

local function run_ltpro(sentence)
  local pipe = assert(io.popen(
    string.format("./LTGOLD/run_test.sh %q 2>/dev/null", sentence), "r"))
  local raw = pipe:read("*all"):gsub("\r", "")
  pipe:close()
  -- LTPRO output: first paragraph before the blank line that precedes MULTIPLE MEANINGS
  local first = raw:match("^(.-)\n%s*\n") or raw
  return (first:match("^%s*(.-)%s*$") or first)
end

local fail, total = 0, 0
local group_fail, group_total = {}, {}

for _, case in ipairs(cases) do
  local group, input, expected = table.unpack(case)
  total = total + 1
  group_total[group] = (group_total[group] or 0) + 1

  if verify_dosbox then
    local live = run_ltpro(input)
    if live ~= expected then
      io.stderr:write(string.format(
        "DOSBOX MISMATCH [%s]\n  stored:  %s\n  live:    %s\n", input, expected, live))
    end
  end

  local got = translate(input)
  if got == expected then
    -- pass
  else
    fail = fail + 1
    group_fail[group] = (group_fail[group] or 0) + 1
    io.stderr:write(string.format(
      "FAIL [%s] %s\n  expected: %s\n  got:      %s\n", group, input, expected, got))
  end
end

-- Per-group summary
local groups = { "BASELINE","T7-PP","T7-NP","T7-AP","T7-VP",
                 "T8-ESS","T8-VERB","T8-COORD","T8-REL","T8-NEG","T8-PASS" }
for _, g in ipairs(groups) do
  local t = group_total[g] or 0
  local f = group_fail[g] or 0
  print(string.format("  %-10s  %d/%d", g, t - f, t))
end
print(string.format("ltgold100: %d/%d passed", total - fail, total))
if fail > 0 then os.exit(1) end
