local engine = require "en_ru.engine"
local count, reads = 0, 0
local function disk(path)
    assert(path:match("^dictionary/[-a-z0-9]+%.tsv$"), path)
    reads = reads + 1
    local file = assert(io.open(path,"rb"))
    local value = file:read("a")
    file:close()
    return value
end
local options={lexicon=engine.load({read_file=disk})}
local loads=reads
local function check(en,ru)
    local got=engine.translate(en,options)
    assert(got==ru, ("%s\n  want %s\n  got  %s"):format(en,ru,got))
    count=count+1
end

-- Positive and neighboring negative controls for the same constructions.
check("I fly home.", "Я лечу домой.")
check("I go home.", "Я иду домой.")
check("I am home.", "Я дома.")
check("I work from home.", "Я работаю из дома.")
check("The dog ran outside.", "Собака бежала наружу.")
check("We were inside.", "Мы были внутри.")
check("There was no answer.", "Не было ответа.")
check("There were no new reports.", "Не было новых отчётов.")
check("There will be no meeting.", "Не будет встречи.")
check("There was nothing good.", "Не было ничего хорошего.")
check("There are three books.", "Есть три книги.")
check("She has no new books.", "У неё нет новых книг.")
check("They did not buy the red house.", "Они не купили красный дом.")
check("She sent him the new letter.", "Она отправила ему новое письмо.")
check("The book she was reading fell.", "Книга, которую она читала, упала.")
check("The news she resigned surprised them.", "Новость о том, что она уволилась, удивила их.")
check("I saw the book her sister was reading.", "Я увидел книгу, которую её сестра читала.")
check("She can speak Russian.", "Она может говорить по-русски.")
check("I’m flying home.", "Я лечу домой.")
check("Xyzzy.", "Xyzzy.")
check("  1. I am home.\n\n  2. I fly home.\n", "  1. Я дома.\n\n  2. Я лечу домой.\n")
options.formal=true
check("You are working here.", "Вы работаете здесь.")
assert(reads==loads and loads>4, "one load, no IO during translation")

local _, state=engine.translate("See Fig. 3. 2 copies are required. Read 2.5.",options)
assert(#state.sentences==3, "figure reference, numeric start and decimal")
local loaded, err=pcall(engine.load,{read_file=function() return nil,"missing fixture" end})
assert(not loaded and err:find("vocabulary.tsv",1,true), "missing asset is explicit")
print(("%d translation assertions plus data IO and boundary checks"):format(count))

-- Directional complements vs locations, particles vs overt prepositions,
-- and fronted copulas vs ordinary existential or noun uses.
options.formal=nil
check("I paddle home.", "Я гребу домой.")
check("She rode back.", "Она ехала обратно.")
check("They hurried right home.", "Они поспешили прямо домой.")
check("You ran slowly upstairs.", "Ты бежал медленно наверх.")
check("She stayed downstairs.", "Она оставалась внизу.")
check("We went ashore.", "Мы шли на берег.")
check("They are ashore.", "Они на берегу.")
check("I paddle forward.", "Я гребу вперёд.")
check("Are the boys and girls home?", "Мальчики и девочки дома?")
check("Is the child inside the house?", "Ребёнок в доме?")
check("I bought a home.", "Я купил дом.")
check("They waited inside the house.", "Они ждали в доме.")
check("He sat outside the house.", "Он сидел за пределами дома.")
check("She worked at home.", "Она работала дома.")
assert(not engine.translate("He drove home the point.", options):find("домой",1,true))
print("Locative transfer and nominal controls passed")
