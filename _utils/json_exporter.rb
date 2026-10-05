require_relative 'common'
require 'json'
require 'time'
require 'fileutils'

# Collects the structured blocks produced while generating the walkthrough
# markdown and writes them out as JSON:
#   index.json              - chapter/section outline
#   chapters/<id>.json      - sections with prose/image/battle/encounters/... blocks
#   dex.json                - lookup tables for every symbol referenced by blocks
# Heading ids match the anchors kramdown (GFM) generates on the live site.
class JsonExporter
  SOURCE_URLS = {
    'reborn' => 'https://bigjra.github.io/reborn/',
    'rejuv' => 'https://bigjra.github.io/rejuvenation/',
    'deso' => 'https://bigjra.github.io/desolation/'
  }

  attr_reader :chapters

  def initialize(game)
    @game = game
    @chapters = []
    @headingIds = Hash.new(0)
  end

  def attach(func_wrapper)
    @funcWrapper = func_wrapper
  end

  # items: [[:text, line] | [:blocks, [block, ...]], ...] for one raw chapter file
  def add_chapter(slug, items)
    chapter = nil
    section = nil
    prose = []

    flush_prose = lambda do
      markdown = prose.join.gsub(/\A\s*\n/, '').rstrip
      section[:blocks].push({ type: 'prose', markdown: markdown }) unless markdown.empty?
      prose = []
    end

    new_chapter = lambda do |id, title|
      chapter = { id: id, title: title, slug: slug, sections: [] }
      @chapters.push(chapter)
      section = { id: nil, title: nil, blocks: [] }
      chapter[:sections].push(section)
    end

    items.each do |kind, value|
      if kind == :text && (match = value.match(/^(#+)\s+(.*?)\s*$/))
        level = match[1].length
        title = match[2]
        id = heading_id(title)
        if level <= 2
          flush_prose.call if section
          if level == 1
            new_chapter.call(id, title)
          else
            new_chapter.call(slug, slug) unless chapter
            section = { id: id, title: title, blocks: [] }
            chapter[:sections].push(section)
          end
          next
        end
      end

      new_chapter.call(slug, slug) unless chapter
      if kind == :text
        prose.push(value)
      else
        flush_prose.call
        section[:blocks].concat(value)
      end
    end
    flush_prose.call if section

    # Drop empty intro sections
    @chapters.each do |ch|
      ch[:sections].reject! { |sec| sec[:id].nil? && sec[:blocks].empty? }
    end
  end

  # kramdown GFM auto id: lowercase, drop non-word chars except '-' and ' ',
  # spaces to dashes, and suffix -1, -2... for repeats within the document.
  def heading_id(title)
    base = title.downcase.gsub(/[^\p{Word}\- ]/u, '').tr(' ', '-')
    count = @headingIds[base]
    @headingIds[base] += 1
    count > 0 ? "#{base}-#{count}" : base
  end

  def write(json_dir)
    chapters_dir = File.join(json_dir, 'chapters')
    FileUtils.mkdir_p(chapters_dir)

    index = {
      game: @game,
      version: VERSIONS[@game],
      generatedAt: Time.now.utc.iso8601,
      source: SOURCE_URLS[@game],
      chapters: @chapters.map do |ch|
        {
          id: ch[:id],
          title: ch[:title],
          slug: ch[:slug],
          file: "chapters/#{ch[:id]}.json",
          sections: ch[:sections].reject { |sec| sec[:id].nil? }.map { |sec| { id: sec[:id], title: sec[:title] } }
        }
      end
    }
    write_json(File.join(json_dir, 'index.json'), index)

    @chapters.each do |ch|
      write_json(File.join(chapters_dir, "#{ch[:id]}.json"), export_value(ch))
    end

    write_json(File.join(json_dir, 'dex.json'), build_dex)
    write_json(File.join(json_dir, 'pokedex.json'), build_pokedex)
    write_json(File.join(json_dir, 'learnsets.json'), build_learnsets)
  end

  # Removes render-only keys (leading underscore) and converts values for JSON
  def export_value(value)
    case value
    when Hash
      value.each_with_object({}) do |(key, val), res|
        next if key.to_s.start_with?('_')
        res[key.to_s] = export_value(val)
      end
    when Array then value.map { |val| export_value(val) }
    when Symbol then value.to_s
    when Range then value.to_a
    else value
    end
  end

  def build_dex
    refs = { species: Set.new, moves: Set.new, abilities: Set.new, items: Set.new, types: Set.new, fields: Set.new }
    each_block { |block| collect_refs(block, refs) }

    fw = @funcWrapper
    species = {}
    refs[:species].sort_by { |sym| fw.pokemonHash.keys.index(sym) || 0 }.each do |sym|
      entry = species_entry(sym)
      next unless entry
      species[sym] = entry
      entry[:forms].each_value do |form|
        form[:abilities].each { |ab| refs[:abilities].add(ab) }
        refs[:abilities].add(form[:hiddenAbility]) if form[:hiddenAbility]
        form[:types].each { |type| refs[:types].add(type) }
      end
    end

    moves = {}
    refs[:moves].to_a.sort.each do |sym|
      m = fw.moveHash[sym]
      next unless m
      refs[:types].add(m[:type])
      moves[sym] = { name: m[:name], type: m[:type], category: m[:category], power: m[:basedamage],
                     accuracy: m[:accuracy], pp: m[:maxpp], desc: m[:desc] }
      moves[sym][:longName] = m[:longname] if m[:longname]
    end

    abilities = {}
    refs[:abilities].to_a.sort.each do |sym|
      a = fw.abilityHash[sym]
      next unless a
      abilities[sym] = { name: a[:name], desc: a[:fullDesc] || a[:desc] }
    end

    items = {}
    refs[:items].to_a.sort.each do |sym|
      i = fw.itemHash[sym]
      next unless i
      items[sym] = { name: i[:name], desc: i[:desc], price: i[:price] }
    end

    types = {}
    refs[:types].to_a.sort.each do |sym|
      t = fw.typeHash[sym]
      next unless t
      types[sym] = { name: t[:name], weaknesses: t[:weaknesses] || [], resistances: t[:resistances] || [],
                     immunities: t[:immunities] || [] }
    end

    fields = {}
    refs[:fields].to_a.sort.each { |sym| fields[sym] = FIELDS[sym] if FIELDS[sym] }

    export_value({ species: species, moves: moves, abilities: abilities, items: items, types: types, fields: fields })
  end

  # Every species in the game, with evolutions and where the guide lists it as obtainable.
  # Species symbols referenced here (evolution targets) are keys of the same `species` map.
  def build_pokedex
    locations = Hash.new { |h, k| h[k] = [] }
    @chapters.each do |ch|
      ch[:sections].each do |sec|
        sec_id = sec[:id] || ch[:id]
        sec_title = sec[:title] || 'Introduction'
        sec[:blocks].each do |block|
          if block[:type] == 'encounters'
            block[:methods].each do |m|
              m[:rows].each do |row|
                add_location(locations[row[:species]], ch, sec_id, sec_title, block[:mapName] || block[:name],
                             m[:method], row[:levels])
              end
            end
          elsif block[:type] == 'shop'
            block[:items].each do |i|
              add_location(locations[i[:species]], ch, sec_id, sec_title, block[:title], 'Shop', nil) if i[:species]
            end
          end
        end
      end
    end

    species = {}
    @funcWrapper.pokemonHash.each_key do |sym|
      entry = species_entry(sym, full: true)
      next unless entry
      entry[:locations] = locations[sym]
      species[sym] = entry
    end

    fw = @funcWrapper
    abilities = {}
    names = {}
    species.each_value do |entry|
      entry[:forms].each_value do |form|
        (form[:abilities] + [form[:hiddenAbility]]).compact.each do |ab|
          a = fw.abilityHash[ab]
          abilities[ab] ||= { name: a[:name], desc: a[:fullDesc] || a[:desc] } if a
        end
        form[:evolutions].each do |evo|
          param = evo[:parameter]
          next unless param.is_a?(Symbol)
          source = fw.itemHash[param] || fw.moveHash[param] || fw.pokemonHash[param]&.values&.find { |v| v.is_a?(Hash) && v[:name] }
          names[param] ||= source[:name] if source
        end
      end
    end
    export_value({ species: species, abilities: abilities, names: names })
  end

  # Per-form learnsets (no pre-evolution merging) plus full data for every move they reference
  def build_learnsets
    fw = @funcWrapper
    species = {}
    move_syms = Set.new
    fw.pokemonHash.each do |sym, form_hash|
      form_keys = form_hash.keys.select { |key| key.is_a?(String) }
      next if form_keys.empty?
      first = form_hash[form_keys[0]]
      first = form_hash[first[:baseForm]].merge(first.compact) if first[:baseForm] && form_hash[first[:baseForm]]
      forms = {}
      form_keys.each_with_index do |form_key, idx|
        data = idx == 0 ? first : form_hash[form_key]
        level = (data[:Moveset] || first[:Moveset] || []).map { |lvl, move| [lvl, move] }
        machine = data[:compatiblemoves] || first[:compatiblemoves] || []
        egg = data[:EggMoves] || first[:EggMoves] || []
        relearn = data[:RelearnerMoves] || first[:RelearnerMoves] || []
        level.each { |_, move| move_syms.add(move) }
        [machine, egg, relearn].each { |list| list.each { |move| move_syms.add(move) } }
        forms[idx.to_s] = { level: level, machine: machine, egg: egg, relearn: relearn }
      end
      species[sym] = forms
    end

    moves = {}
    move_syms.to_a.sort.each do |sym|
      m = fw.moveHash[sym]
      next unless m
      moves[sym] = { name: m[:name], type: m[:type], category: m[:category], power: m[:basedamage],
                     accuracy: m[:accuracy], pp: m[:maxpp], desc: m[:desc] }
      moves[sym][:longName] = m[:longname] if m[:longname]
    end
    export_value({ species: species, moves: moves })
  end

  private

  def add_location(list, chapter, sec_id, sec_title, place, method, levels)
    loc = list.find { |l| l[:sectionId] == sec_id && l[:place] == place }
    unless loc
      loc = { chapterId: chapter[:id], sectionId: sec_id, sectionTitle: sec_title, place: place, methods: [], levels: [] }
      list.push(loc)
    end
    loc[:methods].push(method) unless loc[:methods].include?(method)
    loc[:levels].push(levels) if levels && !loc[:levels].include?(levels)
  end

  def each_block(&blk)
    @chapters.each do |ch|
      ch[:sections].each { |sec| sec[:blocks].each(&blk) }
    end
  end

  def collect_refs(block, refs)
    case block[:type]
    when 'battle'
      refs[:fields].add(block[:field]) if block[:field]
      block[:items].each { |i| refs[:items].add(i[:item]) }
      block[:party].each do |mon|
        refs[:species].add(mon[:species])
        refs[:items].add(mon[:item]) if mon[:item]
        refs[:abilities].add(mon[:ability]) if mon[:ability]
        (mon[:abilities] || []).each { |ab| refs[:abilities].add(ab) }
        (mon[:types] || []).each { |type| refs[:types].add(type) }
        mon[:moves].each { |move| refs[:moves].add(move) if move.is_a?(Symbol) }
      end
    when 'encounters'
      block[:methods].each { |m| m[:rows].each { |row| refs[:species].add(row[:species]) } }
    when 'shop'
      block[:items].each do |i|
        refs[:items].add(i[:item]) if i[:item]
        refs[:species].add(i[:species]) if i[:species]
      end
    when 'tutor'
      block[:moves].each { |m| refs[:moves].add(m[:move]) if m[:move] }
    when 'mining'
      block[:rows].each { |row| row[:items].each { |item| refs[:items].add(item) } }
    when 'pickup'
      block[:rows].each { |row| refs[:items].add(row[:item]) }
    when 'wildHeld'
      block[:rows].each do |row|
        refs[:items].add(row[:item])
        row[:chances].each { |c| c[:pokemon].each { |mon| refs[:species].add(mon[:species]) } }
      end
    end
  end

  # All forms of a species, keyed by form index; missing fields fall back to the first form
  def species_entry(sym, full: false)
    form_hash = @funcWrapper.pokemonHash[sym]
    return nil unless form_hash
    form_keys = form_hash.keys.select { |key| key.is_a?(String) }
    first = form_hash[form_keys[0]]
    # Minior-style data: the first form points at a later form holding the data
    first = form_hash[first[:baseForm]].merge(first.compact) if first[:baseForm] && form_hash[first[:baseForm]]

    forms = {}
    form_keys.each_with_index do |form_key, idx|
      data = idx == 0 ? first : form_hash[form_key]
      type1 = data[:Type1] || first[:Type1]
      type2 = data[:Type1] ? data[:Type2] : (data[:Type2] || first[:Type2])
      forms[idx.to_s] = {
        name: form_key,
        types: [type1, type2].compact.uniq,
        baseStats: data[:BaseStats] || first[:BaseStats],
        abilities: data[:Abilities] || first[:Abilities] || [],
        hiddenAbility: data[:HiddenAbility] || first[:HiddenAbility]
      }
      if full
        evolutions = data[:evolutions] || first[:evolutions] || []
        forms[idx.to_s][:evolutions] = evolutions.map do |evo|
          { species: evo[:species], method: evo[:method], parameter: evo[:parameter] }
        end
      end
    end
    entry = { name: first[:name], forms: forms }
    entry.merge!(num: first[:dexnum], catchRate: first[:CatchRate], kind: first[:kind]) if full
    entry
  end

  def write_json(path, data)
    File.write(path, JSON.generate(data))
  end
end
