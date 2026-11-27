local engine = require "en_ru.engine"
local locale = require("en_ru.adventure").new()
local count=0
local function check(actual,expected)
    assert(actual==expected, ("wanted %s\ngot    %s"):format(expected,actual))
    count=count+1
end
for line in io.lines("test/fixtures/zork-i.tsv") do
    if not line:match("^#") then
        local kind,source,expected=line:match("^([^\t]+)\t([^\t]+)\t(.*)$")
        check(locale[kind](source),expected)
    end
end
-- Check the same constructions off the route and contrast genuine commands.
check(locale.prose("There is a red book here."),"Здесь есть красная книга.")
check(locale.prose("There is a dark room behind the house."),"За домом есть тёмная комната.")
check(locale.prose("There is no chair beside the door."),"Рядом с дверью нет стула.")
check(locale.prose("The soldier is sitting on the chair."),"Солдат сидит на стуле.")
check(locale.prose("Above the table hangs a lantern."),"Над столом висит фонарь.")
check(locale.prose("Above the window is a rope."),"Над окном верёвка.")
check(locale.prose("There is a window which is ajar."),"Есть окно, которое приоткрыто.")
check(locale.prose("Open the report."),"Открывайте отчёт.")
check(locale.heading("Behind the window"),"За окном")
check(locale.heading("A bloody axe"),"Окровавленный топор")
check(locale.heading("North of the forest"),"К северу от леса")
check(locale.heading("Blackout at Meridian"),"Отключение света в Меридиане")
check(locale.heading("Original superhero prototype"),"Оригинальный супергеройский прототип")
check(locale.heading("Release 1"),"Версия 1")
check(locale.prose("You are in a dispatch office. Rain draws silver lines on the window."),
    "Вы в диспетчерской. Дождь рисует серебристые линии на окне.")
check(locale.prose("The city has lost power, and a tram is hanging over the river."),
    "Город лишился электричества, и трамвай висит над рекой.")
check(locale.prose("Choose your profile: Bulwark, Arc or Lens. Name your hero using the character sheet."),
    "Выберите свой профиль: Бастион, Дуга или Линза. Назовите своего героя с помощью листа персонажа.")
check(locale.prose("Profile registered. The bridge is to the north."),"Профиль зарегистрирован. Мост к северу.")
check(locale.prose("Drone integrity: 40. Health: 120/120."),"Целостность дрона: 40. Здоровье: 120/120.")
check(locale.prose("Power: 30. Rank 40; d100 100; exceptional success."),
    "Мощь: 30. Ранг 40; d100 100; исключительный успех.")

-- The same constructions with other subjects, nouns and verbs.
check(locale.prose("The building lost power."),"Здание лишилось электричества.")
check(locale.prose("The minister lost power."),"Министр лишился власти.")
check(locale.prose("The lamp hangs over the door."),"Лампа висит над дверью.")
check(locale.prose("Mark the paper using a pencil."),"Отметьте бумагу с помощью карандаша.")
check(locale.prose("She is using the key."),"Она пользуется ключом.")
check(locale.prose("She opened the door and took the book."),"Она открыла дверь и взяла книгу.")
check(locale.prose("The girl's book is on the table."),"Книга девочки на столе.")
check(locale.prose("She's going home."),"Она идёт домой.")
check(locale.prose("The profile is already registered."),"Профиль уже зарегистрирован.")
check(locale.prose("Character sheets are ready."),"Листы персонажа готовы.")
local forms=locale.labelForms("character sheet")
check(forms[1],"Лист персонажа")
check(forms[2],"Листа персонажа")
local link = {label="small mailbox",command="small mailbox",objectId=37}
local translated=locale.choice(link)
check(translated.label,"Небольшой почтовый ящик")
assert(translated.command==link.command and translated.objectId==link.objectId and
    link.label=="small mailbox" and translated~=link, "display-only projection")
assert(engine.translate("I go home.")=="Я иду домой.", "locale does not change global mode")
print(count.." Zork/transfer assertions plus verb, link and locale isolation controls")
