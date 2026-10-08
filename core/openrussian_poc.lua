-- Small adapter for the OpenRussian noun/verb/adjective CSV exports.
-- OpenRussian already lists full forms; there are no LTGOLD table IDs here.
local provider = {}

local function split_tsv(line)
  local fields, value, quoted, index = {}, {}, false, 1
  while index <= #line do
    local char = line:sub(index, index)
    if quoted then
      if char == '"' and line:sub(index + 1, index + 1) == '"' then
        value[#value + 1] = '"'
        index = index + 1
      elseif char == '"' then
        quoted = false
      else
        value[#value + 1] = char
      end
    elseif char == '"' and #value == 0 then
      quoted = true
    elseif char == '\t' then
      fields[#fields + 1] = table.concat(value)
      value = {}
    else
      value[#value + 1] = char
    end
    index = index + 1
  end
  assert(not quoted, 'unterminated quoted TSV field')
  fields[#fields + 1] = table.concat(value)
  return fields
end

local function read_dictionary(path, expected_format)
  local file = assert(io.open(path, 'r'), 'cannot open ' .. path)
  local metadata, header, rows = {}, nil, {}
  for line in file:lines() do
    if line:sub(1, 1) == '#' then
      local key, value = line:match('^# ([^\t]+)\t(.+)$')
      if key then metadata[key] = value end
      local format, version = line:match('^# format\ten%-ru%-([%w_]+)\t(%d+)$')
      if format then
        assert(format == expected_format and version == '1', 'unsupported dictionary format in ' .. path)
      end
    elseif not header then
      header = split_tsv(line)
    else
      local values = split_tsv(line)
      local row = {}
      for index, name in ipairs(header) do row[name] = values[index] or '' end
      rows[#rows + 1] = row
    end
  end
  file:close()
  assert(header, 'missing TSV header in ' .. path)
  return metadata, rows
end

local function as_number(value)
  return tonumber(value) or value
end

function provider.load(dic_path, rus_path)
  local dic_meta, entries = read_dictionary(dic_path, 'dic')
  local rus_meta, rows = read_dictionary(rus_path, 'rus')
  assert(dic_meta.source_commit == rus_meta.source_commit, 'DIC/RUS source commits differ')
  local lexemes, by_id = {}, {}
  for _, row in ipairs(rows) do
    local lexeme = by_id[row.id]
    if not lexeme then
      lexeme = {id=row.id, pos=row.pos, lemma=row.lemma, accented_lemma=row.accented_lemma,
        forms={}, source_file=row.source_file, source_row=as_number(row.source_row)}
      for _, key in ipairs({'gender', 'animate', 'indeclinable', 'sg_only', 'pl_only', 'aspect', 'partner'}) do
        if row[key] ~= '' then lexeme[key] = row[key] end
      end
      by_id[row.id] = lexeme
      lexemes[#lexemes + 1] = lexeme
    end
    lexeme.forms[row.slot] = lexeme.forms[row.slot] or {}
    lexeme.forms[row.slot][#lexeme.forms[row.slot] + 1] = {
      form=row.form, source_form=row.source_form, variant=as_number(row.variant)}
  end
  for _, entry in ipairs(entries) do entry.sense_index = as_number(entry.sense_index) end
  return provider.new({source=dic_meta.source, source_commit=dic_meta.source_commit,
    data_license=dic_meta.license, entries=entries}, {source=rus_meta.source,
    source_commit=rus_meta.source_commit, data_license=rus_meta.license, lexemes=lexemes})
end

local function form_slot(pos, request, aspect)
  if pos == 'noun' then
    local numbers = {singular='sg', plural='pl'}
    local cases = {nominative='nom', genitive='gen', dative='dat',
      accusative='acc', instrumental='inst', prepositional='prep'}
    local number, case = numbers[request.number], cases[request.case]
    return number and case and number .. '_' .. case
  elseif pos == 'verb' then
    if request.mood == 'imperative' then
      return request.number == 'plural' and 'imperative_pl' or 'imperative_sg'
    end
    if request.tense == 'past' then
      if request.number == 'plural' then return 'past_pl' end
      local genders = {masculine='m', feminine='f', neuter='n'}
      local gender = genders[request.gender]
      return gender and ('past_' .. gender)
    end
    if request.tense == 'present' or request.tense == 'future' then
      local numbers = {singular='sg', plural='pl'}
      local persons = {first='1', second='2', third='3'}
      local number, person = numbers[request.number], persons[request.person]
      if not number or not person then return nil end
      if aspect == 'perfective' and request.tense == 'present' then return nil end
      if aspect == 'imperfective' and request.tense == 'future' then return nil end
      return 'presfut_' .. number .. person
    end
  elseif pos == 'adjective' then
    if request.form == 'short' then
      local genders = {masculine='m', feminine='f', neuter='n', plural='pl'}
      local gender = genders[request.gender]
      return gender and ('short_' .. gender)
    end
    local numbers = {singular='m', plural='pl'}
    local genders = {masculine='m', feminine='f', neuter='n'}
    local number = numbers[request.number]
    local gender = number == 'pl' and 'pl' or genders[request.gender]
    local cases = {nominative='nom', genitive='gen', dative='dat',
      accusative='acc', instrumental='inst', prepositional='prep'}
    local case = cases[request.case]
    return gender and case and ('decl_' .. gender .. '_' .. case)
  end
end

local function has_grammeme(lexeme, request)
  if request.pos and lexeme.pos ~= request.pos then return false end
  if request.tense == 'present' and lexeme.aspect == 'perfective' then return false end
  if request.tense == 'future' and lexeme.aspect == 'imperfective' then return false end
  return true
end

function provider.new(dic, rus)
  assert(type(dic) == 'table' and type(dic.entries) == 'table', 'invalid DIC data')
  assert(type(rus) == 'table' and type(rus.lexemes) == 'table', 'invalid RUS data')
  local by_id = {}
  for _, lexeme in ipairs(rus.lexemes) do
    assert(type(lexeme.id) == 'string' and type(lexeme.forms) == 'table', 'invalid RUS lexeme')
    by_id[lexeme.id] = lexeme
  end
  local by_english = {}
  for _, entry in ipairs(dic.entries) do
    assert(by_id[entry.russian_id], 'DIC references missing RUS lexeme')
    by_english[entry.english] = by_english[entry.english] or {}
    by_english[entry.english][#by_english[entry.english] + 1] = entry
  end

  local api = {source=dic.source, source_commit=dic.source_commit,
    data_license=dic.data_license}
  function api.forms(english, request)
    assert(type(english) == 'string' and type(request) == 'table', 'invalid form request')
    local results, seen = {}, {}
    for _, entry in ipairs(by_english[english:lower()] or {}) do
      local lexeme = by_id[entry.russian_id]
      if has_grammeme(lexeme, request) then
        local slot = form_slot(lexeme.pos, request, lexeme.aspect)
        local forms = slot and lexeme.forms[slot] or nil
        for _, source_form in ipairs(forms or {}) do
          local value = source_form.form
          if not seen[lexeme.id .. '\0' .. value] then
            seen[lexeme.id .. '\0' .. value] = true
            results[#results + 1] = {lemma=lexeme.lemma, form=value,
              source_form=source_form.source_form,
              pos=lexeme.pos, lexeme_id=lexeme.id, slot=slot,
              sense=entry.sense}
          end
        end
      end
    end
    return #results > 0 and results or nil
  end
  return api
end

return provider
