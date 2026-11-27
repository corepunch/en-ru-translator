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
local link = {label="small mailbox",command="small mailbox",objectId=37}
local translated=locale.choice(link)
check(translated.label,"Небольшой почтовый ящик")
assert(translated.command==link.command and translated.objectId==link.objectId and
    link.label=="small mailbox" and translated~=link, "display-only projection")
assert(engine.translate("I go home.")=="Я иду домой.", "locale does not change global mode")
print(count.." Zork/transfer assertions plus verb, link and locale isolation controls")
