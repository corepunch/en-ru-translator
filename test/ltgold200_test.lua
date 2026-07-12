-- LTGOLD 200-sentence regression suite covering tables T1–T6.
-- Expected outputs captured from LTPRO.EXE via DOSBox-X (LTGOLD/refs200/).
-- Run with --dosbox to re-verify stored expectations against the live binary.
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
  -- T1-CLAUSE — clause connectives: if/when/as/since/during → J/j injection
  { "T1-CLAUSE", "If she leaves, he will follow.",                "Если она оставляет, он последует за." },
  { "T1-CLAUSE", "When the train arrives, we will board.",        "Когда поезд прибывает, мы будем советом{1.доска}." },
  { "T1-CLAUSE", "As he spoke, she listened carefully.",          "Поскольку он говорил, она услышала тщательно{1.осторожно}." },
  { "T1-CLAUSE", "Since he left, nothing has changed.",           "Поскольку Он остался, ничто не изменило." },
  { "T1-CLAUSE", "During the meeting, she took notes.",           "В течение собрания, она брала отмечать." },
  { "T1-CLAUSE", "If the door opens, the alarm sounds.",          "Если дверь{1.вход} открывает, тревога звучит." },
  { "T1-CLAUSE", "When he returns, call me.",                     "Когда он перезвонит мне." },
  { "T1-CLAUSE", "As long as she stays, he will wait.",           "Пока она остается, он будет ожидать." },
  { "T1-CLAUSE", "Since the report arrived, we can proceed.",     "Поскольку сообщение прибыло, мы можем продолжить." },
  { "T1-CLAUSE", "If it rains, they will stay inside.",           "Если он дождь, они останутся в." },
  { "T1-CLAUSE", "When she speaks, everyone listens.",            "Когда она говорит, все слушают." },
  { "T1-CLAUSE", "As he walked in, the room fell silent.",        "Поскольку он прошел в, комната замолкала." },
  { "T1-CLAUSE", "During the war, many cities burned.",           "В течение войны, многие города жеглись{1.гореть;обжигать}." },
  { "T1-CLAUSE", "If he agrees, sign the contract.",              "Если он соглашается, подпишите контракт." },
  { "T1-CLAUSE", "When the light turns red, stop.",               "Когда свет преобразовывает красный, остановите." },
  { "T1-CLAUSE", "Since she arrived, the work has improved.",     "Поскольку Она прибыла, работа{1.труд} улучшила." },
  -- T1-LET — "let us/him/her" imperative constructions
  { "T1-LET",    "Let us begin the meeting now.",                 "Давайте начинать собрание теперь." },
  { "T1-LET",    "Let him speak for himself.",                    "Позвольте ему говорить для себя." },
  { "T1-LET",    "Let us not forget the past.",                   "Давайте не забывать прошлое." },
  { "T1-LET",    "Let her decide for herself.",                   "Позвольте ее решает для себя." },
  -- T1-EXIST — existential "there is/are/was/were/will be" constructions
  { "T1-EXIST",  "There is a cat in the garden.",                 "Есть кошка в сад." },
  { "T1-EXIST",  "There are three boxes on the floor.",           "Есть три ящика{1.бокс;рамка} на поле{2.этаж}." },
  { "T1-EXIST",  "There was a problem with the door.",            "Была проблема с дверью{1.вход}." },
  { "T1-EXIST",  "There were no books on the shelf.",             "Были никакие книги на полке." },
  { "T1-EXIST",  "There will be a meeting tomorrow.",             "Будет собрание завтра." },
  { "T1-EXIST",  "There has been an error in the report.",        "Имеется ошибка в сообщении." },
  -- T1-NEG — "no + NP" negation: no large truck, no valid answer
  { "T1-NEG",    "No large truck passed the gate.",               "Никакой большой грузовик не прошел ворота." },
  { "T1-NEG",    "No valid answer was found.",                    "Неправильный ответ был обнаружен." },
  { "T1-NEG",    "No old man stood there.",                       "Никакой старый человек не стоял там." },
  { "T1-NEG",    "No clear solution exists.",                     "Никакое ясное решение{1.раствор} не существует." },
  -- T1-ASSUM — "assuming" and "let us assume" constructions
  { "T1-ASSUM",  "Assuming he arrives on time, we can start.",    "Допустим он прибывает в время, мы можем начать." },
  { "T1-ASSUM",  "Let us assume the data is correct.",            "Давайте принимать данные правильное." },
  { "T1-ASSUM",  "Assuming the report is true, act now.",         "Принимая сообщение - действительное, действие теперь." },
  -- T2-MODAL — modal + Z→V: can/must/should/will/may/could/would + verb
  { "T2-MODAL",  "He can write in Russian.",                      "Он может записать на Русском." },
  { "T2-MODAL",  "She must leave by noon.",                       "Она должна оставить полднем." },
  { "T2-MODAL",  "They should arrive soon.",                      "Они должны прибыть скоро." },
  { "T2-MODAL",  "He will call her tonight.",                     "Он вызовет{1.называть} ее сегодня вечером." },
  { "T2-MODAL",  "She may know the answer.",                      "Она может узнать ответ." },
  { "T2-MODAL",  "He could see the mountain.",                    "Он мог бы увидеть гору." },
  { "T2-MODAL",  "They would not accept it.",                     "Они не примут{1.мириться} это." },
  { "T2-MODAL",  "She should read the report.",                   "Она должна читать сообщение." },
  -- T2-PROG — X(be) + G(gerund) progressive: is/was running/speaking/building
  { "T2-PROG",   "He is running down the street.",                "Он выполняет улицу." },
  { "T2-PROG",   "She was reading a long letter.",                "Она читала длинное письмо{1.буква}." },
  { "T2-PROG",   "They are building a new bridge.",               "Они строят новый мост{1.бридж}." },
  { "T2-PROG",   "He was sleeping when she called.",              "Он спал, когда она назвала{1.вызывать;созывать}." },
  { "T2-PROG",   "She is learning to speak Russian.",             "Она учится говорить Русского." },
  { "T2-PROG",   "They were waiting at the door.",                "Они ожидали у дверей." },
  -- T2-PERF — Y(have) + E perfect: has/had written/left/found
  { "T2-PERF",   "She has written the report.",                   "Она написала{1.записывать} сообщение." },
  { "T2-PERF",   "He had left before she arrived.",               "Он остался прежде, чем она прибудет." },
  { "T2-PERF",   "They have found the solution.",                 "Они обнаружили решение{1.раствор}." },
  { "T2-PERF",   "She had read the letter twice.",                "Она прочитала письмо{1.буква} дважды." },
  { "T2-PERF",   "He will have finished by then.",                "Он завершит к тому времени." },
  { "T2-PERF",   "They have not seen her since Monday.",          "Они не увидeли ее с Понедельника." },
  -- T2-PASS — N + be + E passive voice: was built/sent/opened/decoded/signed
  { "T2-PASS",   "The bridge was built by workers.",              "Мост{1.бридж} разрабатывался{2.строить} рабочими." },
  { "T2-PASS",   "The report was sent by the director.",          "Сообщение посылалось директором." },
  { "T2-PASS",   "The door was opened by him.",                   "Дверь{1.вход} открывалась ним." },
  { "T2-PASS",   "The message was decoded by them.",              "Сообщение{1.послание} декодировалось ними." },
  { "T2-PASS",   "The contract was signed by them.",              "Контракт был подписанным их." },
  { "T2-PASS",   "The book was stolen from the shelf.",           "Книга красть с полки." },
  -- T2-CHAIN — complex auxiliary chains: must have, could have been, should have been
  { "T2-CHAIN",  "He must have left early.",                      "Он, по-видимому, остался рано." },
  { "T2-CHAIN",  "She could have been seen there.",               "Она была бы увиденной там." },
  { "T2-CHAIN",  "They should have been told sooner.",            "Они должны быть сказанными скорее." },
  { "T2-CHAIN",  "He may have been waiting long.",                "Он может ожидать долго{1.длинно}." },
  { "T2-CHAIN",  "She must have been reading it.",                "Она должна прочитать это." },
  { "T2-CHAIN",  "He would have gone if asked.",                  "Он придет если попрошено." },
  -- T2-REL — relative pronoun who/which in immediate context (T2 handles some before T3)
  { "T2-REL",    "The man who spoke was old.",                    "Человек, который говорил было старым." },
  { "T2-REL",    "The woman which he saw left.",                  "Женщина, которую он видeл оставшийся." },
  -- T2-REFL — reflexive: himself/herself
  { "T2-REFL",   "He saw himself in the mirror.",                 "Он видeл себя в зеркале." },
  { "T2-REFL",   "She hurt herself on the door.",                 "Она ранить себя в дверь{1.вход}." },
  -- T3-REL — relative clauses: that/who/which/whose on preceding noun
  { "T3-REL",    "The book that she found was old.",              "Книга, которую она обнаружила было старым." },
  { "T3-REL",    "The man who came yesterday left early.",        "Человек, который приходил вчера левый рано." },
  { "T3-REL",    "The city which he loved was far away.",         "Город, который он полюбил было далеко." },
  { "T3-REL",    "The woman whose book I read called.",           "Женщина книгу которой Я читаю названный{1.вызывать;созывать}." },
  { "T3-REL",    "The dog that bit him ran away.",                "Собака, которую бит{1.кусочек} его убегать." },
  { "T3-REL",    "The house that burned was rebuilt.",            "Дом, который жег{1.гореть;обжигать} был вновь разработан{2.строить}." },
  { "T3-REL",    "The boy who won the race smiled.",              "Мальчик, который выигрывал улыбаться гонку{1.раса}." },
  { "T3-REL",    "The letter which arrived today was short.",     "Письмо{1.буква}, которое прибывало сегодня было коротким." },
  -- T3-GER — "having + past-participle" → F active perfect participle
  { "T3-GER",    "Having finished the work, he rested.",          "Завершаемый работа{1.труд}, он остался." },
  { "T3-GER",    "Having spoken to her, he left.",                "Говоримый на ее, он остался." },
  { "T3-GER",    "Having read the report, she signed it.",        "Иметь читает сообщение, она подписала{1.отмечать} это." },
  { "T3-GER",    "Having arrived late, he apologized.",           "Прибываемый поздно, он извинился." },
  { "T3-GER",    "Having seen the result, she smiled.",           "Видимый результата, она улыбаться." },
  -- T3-INF — infinitive complement: wants to go, needs to write, decided to leave
  { "T3-INF",    "She wants to go home now.",                     "Она хочет идти домой теперь." },
  { "T3-INF",    "He needs to write the report.",                 "Он имеет необходимость писать{1.записывать} сообщение." },
  { "T3-INF",    "They decided to leave early.",                  "Они решили оставлять рано." },
  { "T3-INF",    "She began to speak slowly.",                    "Она начинала говорить медленно." },
  { "T3-INF",    "He tried to open the door.",                    "Он пытался открывать дверь{1.вход}." },
  { "T3-INF",    "They failed to find the answer.",               "Они не могут найти ответ." },
  { "T3-INF",    "She managed to finish on time.",                "Она удалось конец в времени." },
  { "T3-INF",    "He agreed to sign the contract.",               "Он согласился подписывать контракт." },
  -- T3-PRON — object pronoun case: gave it to him, handed letter to her
  { "T3-PRON",   "She gave it to him directly.",                  "Она давала это ему непосредственно." },
  { "T3-PRON",   "He handed the letter to her.",                  "Он передал письмо к ей." },
  { "T3-PRON",   "They showed the result to us.",                 "Они показали результат нам." },
  { "T3-PRON",   "She asked him about it.",                       "Она спросила его об этом." },
  -- T3-DEM — demonstrative + adj + noun → O (this old book, that large building)
  { "T3-DEM",    "This old book belonged to her.",                "Эта старая книга принадлежала ей." },
  { "T3-DEM",    "That large building was new.",                  "Это большое построение было новым." },
  { "T3-DEM",    "This red door is locked.",                      "Эта красная дверь{1.вход} заблокирована." },
  { "T3-DEM",    "That broken chair needs repair.",               "Это разбивало нужно ремонт стула." },
  -- T3-Z — Z→N final fallback: remaining ambiguous verbs/nouns resolved to N
  { "T3-Z",      "The dog runs fast.",                            "Собака бежит{1.выполнять} быстро." },
  { "T3-Z",      "She speaks three languages.",                   "Она говорит три языка." },
  { "T3-Z",      "He reads every evening.",                       "Он читает каждый вечер." },
  { "T3-Z",      "They work in the city.",                        "Они работают в городе." },
  { "T3-Z",      "She writes very well.",                         "Она пишет{1.записывать} очень хорошо." },
  -- T4-BOTH — both...and correlative: как...так и
  { "T4-BOTH",   "Both the man and the woman spoke.",             "Как человек так и женщина говорили." },
  { "T4-BOTH",   "Both he and she were present.",                 "Оба он и она присутствовала." },
  { "T4-BOTH",   "He both reads and writes well.",                "Он оба читают и пишут{1.записывать} хорошо." },
  -- T4-EITHER — either...or: или...или
  { "T4-EITHER", "Either he goes or she stays.",                  "Или он идет или она остается." },
  { "T4-EITHER", "Either the door or the window was open.",       "Или дверь{1.вход} или окно было открытым." },
  { "T4-EITHER", "Either answer is correct.",                     "Каждый Ответ правильный." },
  -- T4-SOTHAT — so that: так, чтобы
  { "T4-SOTHAT", "He spoke slowly so that she could understand.", "Он говорил медленно так, что она могла бы понять." },
  { "T4-SOTHAT", "She wrote clearly so that he could read it.",   "Она писала{1.записывать} несомненно так, что он мог бы читать это." },
  { "T4-SOTHAT", "He arrived early so that she could leave.",     "Он прибыл рано так, что она могла бы оставить." },
  -- T4-NOTAS — not as X as: не так X как
  { "T4-NOTAS",  "He is not as tall as she is.",                  "Он не так высокий как она -." },
  { "T4-NOTAS",  "This is not as simple as it looks.",            "Это не так простое как он смотрит." },
  { "T4-NOTAS",  "She is not as fast as her sister.",             "Она не - как быстро как ее сестра." },
  -- T4-ASMUCH — as much as: столько же
  { "T4-ASMUCH", "He reads as much as she does.",                 "Он читает столько же она делает." },
  { "T4-ASMUCH", "She earns as much as he does.",                 "Она зарабатывает столько же он делает." },
  -- T4-NEED — "need" → понадобится / needs to
  { "T4-NEED",   "He needs a new computer now.",                  "Ему нужен новый компьютер теперь." },
  { "T4-NEED",   "She needs to find the key.",                    "Она имеет необходимость обнаруживать ключ{1.клавиша}." },
  { "T4-NEED",   "They need more time to finish.",                "Им нужно дополнительное время, чтобы завершить." },
  -- T4-NN — N N → A N (noun used as attributive adjective)
  { "T4-NN",     "The city wall was very old.",                   "Городская стена была очень старой." },
  { "T4-NN",     "The river bank was muddy.",                     "Речной банк был грязным." },
  { "T4-NN",     "The garden gate was closed.",                   "Ворота сад были закрыты." },
  { "T4-NN",     "The stone bridge collapsed at dawn.",           "Каменный мост{1.бридж} рушиться на рассвете." },
  { "T4-NN",     "The glass window shattered loudly.",            "Стеклянное окно разрушило громко{1.шумный}." },
  { "T4-NN",     "The iron gate was locked.",                     "Железные ворота были заблокированы." },
  { "T4-NN",     "The paper report was lost.",                    "Бумажное сообщение было потеряно." },
  -- T4-PCT — percentages
  { "T4-PCT",    "He owns fifty percent of the company.",         "Он обладает пятьдесят процентами компании." },
  { "T4-PCT",    "She completed ninety percent of the work.",     "Она завершила девяносто процентов работы{1.труд}." },
  -- T4-OFWHOM — "of whom" → из которой
  { "T4-OFWHOM", "Three men came, of whom one spoke.",            "Три мужчины приходили, кому один говорило." },
  { "T4-OFWHOM", "Five women arrived, of whom two left.",         "Пять прибывемы женщин, кому два остались." },
  -- T4-SEE — "see" reference → смотри
  { "T4-SEE",    "See page twelve for details.",                  "Смотри страницу двенадцать относительно деталей." },
  -- T4-NO — standalone "no" → нет
  { "T4-NO",     "No, he did not go there.",                      "Нет, он не шел там." },
  { "T4-NO",     "No, she has not seen him.",                     "Нет, она не увидeла его." },
  -- T4-HYPH — hyphenated adjectives: well-known, long-term, low-cost
  { "T4-HYPH",   "He is a well-known author.",                    "Он - известный автор." },
  { "T4-HYPH",   "She is a long-term employee.",                  "Она - долгосрочный служащий." },
  { "T4-HYPH",   "It was a low-cost solution.",                   "Это Был дешевым решением{1.раствор}." },
  -- T5-GENOF — "of"-genitive reorder: NwNw → 34 (студента книга)
  { "T5-GENOF",  "The book of the student was old.",              "Книга студента была старой." },
  { "T5-GENOF",  "The door of the house was broken.",             "Дверь{1.вход} дома была разбита." },
  { "T5-GENOF",  "The car of the director was new.",              "Автомобиль директора был новым." },
  { "T5-GENOF",  "The report of the committee was long.",         "Сообщение комитета было длинным." },
  { "T5-GENOF",  "The son of the king arrived.",                  "Сын прибян короля." },
  { "T5-GENOF",  "The work of the writer was praised.",           "Работа{1.труд} автора была похвалена." },
  { "T5-GENOF",  "The key of the room was lost.",                 "Ключ{1.клавиша} комнаты был потерян." },
  { "T5-GENOF",  "The name of the street was unknown.",           "Имя улицы было неизвестным." },
  { "T5-GENOF",  "The leader of the group spoke.",                "Лидер{1.начало} группы говорил." },
  { "T5-GENOF",  "The top of the mountain was cold.",             "Верх горы был холодным." },
  -- T5-GENNAME — "of [proper noun]" genitive: NwN → 33
  { "T5-GENNAME","The book of John was found.",                   "Книга Джона была обнаружена." },
  { "T5-GENNAME","The car of Maria was stolen.",                  "Автомобиль Мария был красть." },
  { "T5-GENNAME","The house of Peter burned down.",               "Дом Питер жег{1.гореть;обжигать} вниз по." },
  { "T5-GENNAME","The report of Anna was praised.",               "Сообщение Анна было похвалено." },
  -- T5-NNW — apposition "city Moscow" → NNw reorder (город Москва)
  { "T5-NNW",    "The city Moscow is very large.",                "Городская Москва очень большая." },
  { "T5-NNW",    "The river Volga flows south.",                  "Речной Волга юг потоков." },
  { "T5-NNW",    "The lake Baikal is very deep.",                 "Озеро Baikal очень глубоко." },
  { "T5-NNW",    "The street Arbat was crowded.",                 "Уличный Арбат был собраран." },
  -- T5-ADJ-GENOF — adj + "of"-genitive: NANw → 234 (старая книга студента)
  { "T5-ADJ-GENOF","The old book of the student was lost.",       "Старая книга студента была потеряна." },
  { "T5-ADJ-GENOF","The long report of the director arrived.",    "Длинное сообщение прибян директора." },
  { "T5-ADJ-GENOF","The broken door of the house was repaired.",  "Разбитая дверь{1.вход} дома была исправлена." },
  { "T5-ADJ-GENOF","The second report of the year was complete.", "Второе сообщение года было полным." },
  { "T5-ADJ-GENOF","The new car of the manager was fast.",        "Новый автомобиль менеджера был быстрым." },
  { "T5-ADJ-GENOF","The large house of the family stood there.",  "Большой дом семейства стоял там." },
  { "T5-ADJ-GENOF","The open window of the room let in air.",     "Открытое окно комнаты позволило в воздух{1.эфир;вид}." },
  { "T5-ADJ-GENOF","The wooden door of the barn was old.",        "Деревянная дверь{1.вход} амбара была старой." },
  { "T5-ADJ-GENOF","The white wall of the building was clean.",   "Белая стена построения была чистой{1.проверенный}." },
  { "T5-ADJ-GENOF","The heavy box of the worker was dropped.",    "Тяжелый ящик{1.бокс;рамка} рабочего был упаден." },
  -- T5-POSS — possessive apostrophe-s: student's book
  { "T5-POSS",   "The student's book was on the desk.",           "Студенческая книга была на столе{1.пульт}." },
  { "T5-POSS",   "The director's report was very clear.",         "Сообщение директора было очень ясным." },
  { "T5-POSS",   "The manager's car was very new.",               "Автомобиль менеджера был очень новым." },
  -- T6-NUM — cardinal numbers + nouns
  { "T6-NUM",    "He bought five kilograms of flour.",            "Он купил пять килограммов муки." },
  { "T6-NUM",    "She ordered ten liters of water.",              "Она упорядочивала{1.приказывать;заказывать} десять литров воды." },
  { "T6-NUM",    "They produced three hundred units last year.",  "Они произвели триста устройства в прошлом году." },
  { "T6-NUM",    "He walked twenty kilometers on foot.",          "Он прошел двадцать километр пешком." },
  { "T6-NUM",    "She read forty pages in one hour.",             "Она читает сорок страниц на одном часе." },
  { "T6-NUM",    "They built six new houses last year.",          "Они разработали{1.строить} шесть новых домов в прошлом году." },
  { "T6-NUM",    "He spent two thousand rubles.",                 "Он затратил два тысяча рублей." },
  { "T6-NUM",    "She counted twelve boxes in the room.",         "Она считала двенадцать ящиков{1.бокс;рамка} в комнате." },
  { "T6-NUM",    "Two hundred soldiers crossed the river.",       "Двести солдата пересекли реку." },
  { "T6-NUM",    "He found seven gold coins in the chest.",       "Он обнаружил семь золотой монет в ящике{1.грудь}." },
  { "T6-NUM",    "She wrote fifteen letters that week.",          "Она писала{1.записывать} пятнадцать писем{2.буква}, которые неделя." },
  -- T6-ORD — ordinal numbers: first/third/1st/2nd/etc.
  { "T6-ORD",    "He finished in first place.",                   "Он завершил на первом месте." },
  { "T6-ORD",    "She came in third place.",                      "Она входила третье место." },
  { "T6-ORD",    "The 1st chapter was very short.",               "1 глава{1.отделение} была очень короткой." },
  { "T6-ORD",    "The 2nd report was much better.",               "2 сообщение было значительно лучше." },
  { "T6-ORD",    "The 3rd door on the left was open.",            "3 дверь{1.вход} слева было открытым." },
  { "T6-ORD",    "He won the 4th prize.",                         "Он выиграл 4 премию{1.награда}." },
  { "T6-ORD",    "She read the 5th chapter last night.",          "Она читает 5 главу{1.отделение} вчера вечером." },
  -- T6-PCT — percentages
  { "T6-PCT",    "The price rose by ten percent.",                "Цена поднималась десятью процентами." },
  { "T6-PCT",    "He completed eighty percent of the task.",      "Он завершил восемьдесят процентов задания." },
  { "T6-PCT",    "The report covered fifty percent of cases.",    "Сообщение покрыло пятьдесят процентов случаев{1.дело;ящик;падеж}." },
  -- T6-MEAS — measurements: kilograms, meters, degrees, km/h
  { "T6-MEAS",   "The box weighs five kilograms.",                "Взвешивать ящика{1.бокс;рамка} пять килограммов." },
  { "T6-MEAS",   "She ran one hundred meters in twelve seconds.", "Она выполнила сто метра{1.измеритель} в двенадцать секундах." },
  { "T6-MEAS",   "The room is six meters long.",                  "Комната - шесть метров{1.измеритель} долго{2.длинно}." },
  { "T6-MEAS",   "He drove at ninety kilometers per hour.",       "Он поехал{1.управлять} в девяносто километр на час." },
  { "T6-MEAS",   "The temperature was minus ten degrees.",        "Температура была минус десять градусов{1.степень}." },
  { "T6-MEAS",   "The building stands forty meters tall.",        "Построение стенд сорок метров{1.измеритель} высокие." },
  { "T6-MEAS",   "He paid three hundred dollars for it.",         "Он уплатил триста доллара для это." },
  -- T6-RANGE — numeric ranges: five through ten, 1990 through 2000
  { "T6-RANGE",  "Pages five through ten were missing.",          "Страницы пять через десять пропускали." },
  { "T6-RANGE",  "The years 1990 through 2000 were studied.",     "Годы 1990 через 2000 были изучены." },
  { "T6-RANGE",  "He worked from nine to five daily.",            "Он работал от девяти до пяти ежедневно." },
  { "T6-RANGE",  "She read chapters three through seven.",        "Она читает главы{1.отделение} три через семь." },
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
  if got ~= expected then
    fail = fail + 1
    group_fail[group] = (group_fail[group] or 0) + 1
    io.stderr:write(string.format(
      "FAIL [%s] %s\n  expected: %s\n  got:      %s\n", group, input, expected, got))
  end
end

local groups = {
  "T1-CLAUSE","T1-LET","T1-EXIST","T1-NEG","T1-ASSUM",
  "T2-MODAL","T2-PROG","T2-PERF","T2-PASS","T2-CHAIN","T2-REL","T2-REFL",
  "T3-REL","T3-GER","T3-INF","T3-PRON","T3-DEM","T3-Z",
  "T4-BOTH","T4-EITHER","T4-SOTHAT","T4-NOTAS","T4-ASMUCH",
  "T4-NEED","T4-NN","T4-PCT","T4-OFWHOM","T4-SEE","T4-NO","T4-HYPH",
  "T5-GENOF","T5-GENNAME","T5-NNW","T5-ADJ-GENOF","T5-POSS",
  "T6-NUM","T6-ORD","T6-PCT","T6-MEAS","T6-RANGE",
}
for _, g in ipairs(groups) do
  local t = group_total[g] or 0
  local f = group_fail[g] or 0
  if t > 0 then
    print(string.format("  %-14s  %d/%d", g, t - f, t))
  end
end
print(string.format("ltgold200: %d/%d passed", total - fail, total))
if fail > 0 then os.exit(1) end
