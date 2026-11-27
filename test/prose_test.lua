local engine=require "en_ru.engine"
local tokenize=require "en_ru.tokenize"
local options={lexicon=engine.load()}
local function check(en,ru)
    local actual=engine.translate(en,options)
    assert(actual==ru, ("%s: expected %s; got %s"):format(en,ru,actual))
end

check("There was nothing remarkable.", "Не было ничего замечательного.")
check("There was no one in the room.", "В комнате не было никого.")
check("There is nobody.", "Нет никого.")
check("If there was no guard, we waited.", "Если не было охранника, мы ждали.")
check("I knew that there was no guard.", "Я знал, что не было охранника.")
check("There were no empty seats.", "Не было пустых мест.")
check("There will be no empty seats.", "Не будет пустых мест.")
check("There were no cats or dogs.", "Не было кошек или собак.")
check("There were no cats, but there was a dog.", "Не было кошек, но была собака.")
check("That morning there was no guard.", "Тем утром не было охранника.")
check("After dinner there was no music.", "После ужина не было музыки.")
check("Before breakfast there was no noise.", "Перед завтраком не было шума.")
check("There were no lamps and no candles.", "Не было ламп и свечей.")
check("We hope there will be no delay.", "Мы надеемся, что не будет задержки.")
check("She was there.", "Она была там.")
check("There was a man in the room.", "В комнате был мужчина.")
assert(not engine.translate("The guard there was no fool.",options):find("не было",1,true))
local actual=engine.translate("I saw the book her sister was reading.",options)
check("I saw the book which her sister was reading.",actual)
assert(actual:find("книгу, которую",1,true))

local attached=engine.translate("I said--rather loudly--that he could leave.",options)
check("I said—rather loudly—that he could leave.",attached)
check("I said – rather loudly – that he could leave.",attached)
assert(attached:find("довольно громко",1,true))
assert(attached:find("—",1,true))
check('“I am home,” she said.',engine.translate('"I am home," she said.',options))
local tokens=tokenize.words("battery-powered--lamp… here now.")
assert(#tokens==9 and tokens[1].word=="battery-powered" and tokens[2].word=="—"
    and tokens[3].word=="lamp" and tokens[7].word=="here" and tokens[8].word=="now")
print("Prose punctuation, existential and relative-clause assertions passed")
