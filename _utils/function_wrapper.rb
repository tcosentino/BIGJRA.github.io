require_relative 'common'
require_relative 'encounter_getter'
require_relative 'shop_getter'
require_relative 'trainer_getter'

# This is the magic class of the rewrite.
# Each function should return a string of some kind (can be multiline)
class FunctionWrapper

  def initialize(game, scripts_dir)
    # I need to pass in game to basically all of the potential functions, so
    # here we stick it in as as an argument. Anything that is consistent
    # across the whole document (ie. Version) should be used here:
    @cache = {}
    @game = game
    @scriptsDir = scripts_dir

    @mapHash = load_maps_hash(game, @scriptsDir)
    @encHash = load_enc_hash(game, @scriptsDir)
    @itemHash = load_item_hash(game, @scriptsDir)
    @trainerHash = load_trainer_hash(game, @scriptsDir)
    @bossHash = load_boss_hash(game, @scriptsDir)
    @shopHash = load_shop_hash(game, @scriptsDir)
    @trainerTypeHash = load_trainer_type_hash(game, @scriptsDir)
    @typeHash = load_type_hash(game, @scriptsDir)
    @moveHash = load_move_hash(game, @scriptsDir)
    @abilityHash = load_ability_hash(game, @scriptsDir)
    @pokemonHash = load_pokemon_hash(game, @scriptsDir)
    @raidDenHash = load_raid_den_hash(game, @scriptsDir)
    @encMapWrapper = EncounterMapWrapper.new(game, @scriptsDir)

    @encGetter = EncounterGetter.new(game, @scriptsDir, @encHash, @mapHash, @encMapWrapper, @pokemonHash)
    @shopGetter = ShopGetter.new(game, @scriptsDir, @itemHash, @moveHash, @pokemonHash)
    @trainerGetter = TrainerGetter.new(game, @scriptsDir, @trainerHash, @bossHash, @trainerTypeHash, @itemHash, @moveHash, @abilityHash,
                                       @pokemonHash, @typeHash)

    @shortNames = {
      'img' => 'generate_image_markdown',
      'enc' => 'generate_encounter_markdown',
      'shop' => 'generate_shop_markdown',
      'cshop' => 'generate_cshop_markdown',
      'battle' => 'generate_trainer_markdown',
      'btsinglesboss' => 'generate_battle_tower_singles_bosses_markdown',
      'btdoublesboss' => 'generate_battle_tower_doubles_bosses_markdown',
      'ttbattles' => 'generate_theme_teams_markdown',
      'dbattle' => 'generate_double_markdown',
      'mine' => 'generate_mining_markdown',
      'wildheld' => 'generate_wild_held_markdown',
      'tutor' => 'generate_tutor_markdown',
      'partner' => 'generate_partner_markdown',
      'newself' => 'generate_newself_markdown',
      'pickup' => 'generate_pickup_markdown',
      'boss' => 'generate_boss_markdown',
      'move' => 'generate_move_markdown',
      'raid' => 'generate_raid_den_markdown'
    }

    # Data builders for each shortname. Each returns a block Hash (or an Array of
    # them) that render_block turns back into the HTML the generate_* methods return.
    @blockBuilders = {
      'img' => 'build_image_block',
      'enc' => 'build_encounter_block',
      'shop' => 'build_shop_block',
      'cshop' => 'build_cshop_block',
      'battle' => 'build_trainer_block',
      'btsinglesboss' => 'build_battle_tower_singles_bosses_blocks',
      'btdoublesboss' => 'build_battle_tower_doubles_bosses_blocks',
      'ttbattles' => 'build_theme_teams_blocks',
      'dbattle' => 'build_double_block',
      'mine' => 'build_mining_block',
      'wildheld' => 'build_wild_held_block',
      'tutor' => 'build_tutor_block',
      'partner' => 'build_partner_block',
      'newself' => 'build_newself_block',
      'pickup' => 'build_pickup_block',
      'boss' => 'build_boss_block',
      'move' => 'build_move_block',
      'raid' => 'build_raid_den_block'
    }
  end

  attr_reader :game, :itemHash, :moveHash, :abilityHash, :pokemonHash, :typeHash

  def evaluate_function_from_string(s)
    evaluate_blocks_from_string(s)[:html]
  end

  # Evaluates a line beginning with ! and returns { html:, blocks: } where blocks
  # is the structured data the html was rendered from. Results are cached per call.
  def evaluate_blocks_from_string(s)
    s = s.strip[1..-2]
    func_shortname, args = s.split('(', 2)
    raise "#{func_shortname} not found in list of shortnames." unless @shortNames[func_shortname]
      
    func = @blockBuilders[func_shortname]
    run_str = "#{func}(#{args})"
    # puts run_str
    if @cache.include?(run_str)
      return @cache[run_str]
    end
    blocks = eval(run_str) # evaluates function
    blocks = [blocks] unless blocks.is_a?(Array)
    blocks.each { |block| block[:macro] = func_shortname }
    html = blocks.map { |block| render_block(block) }.join("\n\n") + "\n" # preserves its newline
    res = { html: html, blocks: blocks }
    @cache[run_str] = res
    return res
  end

  def render_block(block)
    case block[:type]
    when 'image' then render_image_html(block)
    when 'encounters' then @encGetter.render_encounter_html(block)
    when 'shop' then @shopGetter.render_shop_html(block)
    when 'battle' then @trainerGetter.render_trainer_html(block)
    when 'tutor' then render_tutor_html(block)
    when 'mining' then render_mining_html(block)
    when 'wildHeld' then render_wild_held_html(block)
    when 'pickup' then render_pickup_html(block)
    when 'html' then block[:html]
    else raise "Unknown block type #{block[:type]}"
    end
  end

  def generate_image_markdown(filename)
    render_block(build_image_block(filename))
  end

  def build_image_block(filename)
    { type: 'image', file: filename, src: "/assets/images/#{@game}/#{filename}" }
  end

  def render_image_html(block)
    "<img class=\"tabImage\" src=\"#{block[:src]}\"/>"
  end

  def generate_mining_markdown
    render_block(build_mining_block)
  end

  def build_mining_block
    mining_hash = load_mining_hash(@game, @scriptsDir)
    rows = mining_hash.map { |prob, item_list| { items: item_list, probability: prob } }
    { type: 'mining', title: 'Mining Probabilities', rows: rows }
  end

  def render_mining_html(block)
    # Creates nokogiri HTML
    doc = Nokogiri::HTML::Document.new
    div = doc.create_element('div', class: 'mining_table')
    doc.add_child(div)

    table = doc.create_element('table')
    div.add_child(table)

    # Creates the header for the table
    thead = doc.create_element('thead')
    table.add_child(thead)

    table_header = doc.create_element('th', colspan: 2)
    thead.add_child(table_header)

    bold = doc.create_element('strong')
    bold.content = block[:title]
    table_header.add_child(bold)
    table_header['class'] = 'table-header'
    table_header['style'] = 'text-align: center;'

    block[:rows].each do |row|
      prob, item_list = row[:probability], row[:items]
      content_row = doc.create_element('tr')
      table.add_child(content_row)

      # Column 1: Item Name (italicized)
      item_str = item_list.map { |sym| @itemHash[sym][:name] }.join(', ')
      td_item = doc.create_element('td', style: 'text-align: center')
      td_item.add_child(doc.create_element('em', content = item_str))
      content_row.add_child(td_item)

      # Column 2: Probability
      td_price = doc.create_element('td', style: 'text-align: center')
      td_price.content = "#{prob}%"
      content_row.add_child(td_price)
    end

    html_output = doc.to_html
    html_output.split("\n")[1..].join("\n")
  end

  def generate_wild_held_markdown
    render_block(build_wild_held_block)
  end

  def build_wild_held_block
    # Create the main hash with default value as a proc
    lookup_hash = Hash.new { |hash, key| hash[key] = { 'common' => [], 'uncommon' => [], 'rare' => [] } }

    @pokemonHash.each do |mon_symbol, form_hash|
      f = form_hash.reject { |key| !key.is_a?(String) }.compact
      next unless f

      f.each do |form, data|
        lookup_hash[data[:WildItemCommon]]['common'] << [mon_symbol, form] if data[:WildItemCommon]
        lookup_hash[data[:WildItemUncommon]]['uncommon'] << [mon_symbol, form] if data[:WildItemUncommon]
        lookup_hash[data[:WildItemRare]]['rare'] << [mon_symbol, form] if data[:WildItemRare]
      end
    end

    rows = []
    # Sorts items by order in item hash

    lookup_hash.map do |item, mon_hash|
      [item, mon_hash]
    end.sort_by { |a, _| @itemHash.keys.index(a) }.each do |item, mon_hash|
      next unless mon_hash

      chances = []
      mon_hash.each do |rarity, pokemon_list|
        next if pokemon_list.empty?

        # Transform each Pokemon entry into the desired format
        pokemon_entries = pokemon_list.map do |pokemon, form|
          form_1_key = @pokemonHash[pokemon].keys.find_all { |key| key.is_a?(String) }[0]
          form_1_data = @pokemonHash[pokemon][form_1_key]
          pokemon_name = "#{@pokemonHash[pokemon][form_1_key][:name]}"
          if pokemon_name == 'Minior'
            pokemon_name.to_s
          elsif form != 'Normal Form' && form != form_1_key
            "#{pokemon_name} (#{form.sub(' Form', '')})"
          else
            pokemon_name.to_s
          end
        end.zip(pokemon_list).map { |name, (species, form)| { species: species, form: form, displayName: name } }

        chances.push({ rarity: rarity, percent: { 'common' => 50, 'uncommon' => 5, 'rare' => 1 }[rarity], pokemon: pokemon_entries })
      end
      rows.push({ item: item, chances: chances })
    end

    { type: 'wildHeld', title: 'Wild Pokemon Held Item Chances', rows: rows }
  end

  def render_wild_held_html(block)
    # Creates nokogiri HTML
    doc = Nokogiri::HTML::Document.new
    div = doc.create_element('div', class: 'mining_table')
    doc.add_child(div)

    table = doc.create_element('table')
    div.add_child(table)

    # Creates the header for the table
    thead = doc.create_element('thead')
    table.add_child(thead)

    table_header = doc.create_element('th', colspan: 2)
    thead.add_child(table_header)

    bold = doc.create_element('strong')
    bold.content = block[:title]
    table_header.add_child(bold)
    table_header['class'] = 'table-header'
    table_header['style'] = 'text-align: center;'

    block[:rows].each do |row|
      item = row[:item]
      result = ''
      row[:chances].each do |chance|
        pokemon_string = chance[:pokemon].map { |mon| mon[:displayName] }.uniq.join(', ')

        # Concatenate the rarity and Pokemon string
        result << "- #{chance[:rarity].capitalize} (#{chance[:percent]}%): #{pokemon_string}\n"
      end
      result = result.chomp

      content_row = doc.create_element('tr')
      table.add_child(content_row)

      # Column 1: Item Name (italicized)
      td_item = doc.create_element('td', style: 'text-align: center')
      td_item.add_child(doc.create_element('em', content = @itemHash[item][:name]))
      content_row.add_child(td_item)

      # Column 2: Mon List With Prob
      td_price = doc.create_element('td')
      td_price.content = "#{result}"
      content_row.add_child(td_price)
    end

    html_output = doc.to_html
    html_output.split("\n")[1..].join("\n")
  end

  def generate_pickup_markdown
    render_block(build_pickup_block)
  end

  def build_pickup_block
    pickup_data = load_pickup_data(@game, @scriptsDir)

    # Sort entries by the order in item hash
    sorted_pickup_data = pickup_data.sort_by { |item, _| @itemHash.keys.index(item) }
    rows = sorted_pickup_data.map do |item, odds_hash|
      { item: item, odds: odds_hash.map { |odds, range| { percent: odds, minLevel: range[0], maxLevel: range[1] } } }
    end
    { type: 'pickup', title: 'Pickup Odds', rows: rows }
  end

  def render_pickup_html(block)
    doc = Nokogiri::HTML::Document.new
    div = doc.create_element('div', class: 'pickup_table')
    doc.add_child(div)
  
    table = doc.create_element('table', id: 'pickup-table')
    div.add_child(table)
  
    # Create the header for the table
    thead = doc.create_element('thead')
    table.add_child(thead)
  
    header_row = doc.create_element('tr', class: 'header')
    thead.add_child(header_row)
  
    # Single header for Pickup Odds
    table_header = doc.create_element('th', colspan: 2)
    table_header.add_child(doc.create_element('strong', block[:title]))
    table_header['class'] = 'table-header'
    table_header['style'] = 'text-align: center;'
    header_row.add_child(table_header)
  
    tbody = doc.create_element('tbody')
    table.add_child(tbody)
  
    # Iterate over each item in the sorted pickup data
    block[:rows].each do |row|
      item = row[:item]
      content_row = doc.create_element('tr')
      tbody.add_child(content_row)
  
      # Column 1: Item Name (italicized)
      td_item = doc.create_element('td', style: 'text-align: center')
      td_item.add_child(doc.create_element('em', @itemHash[item][:name]))
      content_row.add_child(td_item)
  
      # Column 2: Odds and Level Ranges
      odds_string = row[:odds].map do |odds|
        "- #{odds[:percent]}%: Lv. #{odds[:minLevel]}-#{odds[:maxLevel]}"
      end.join("\n")
  
      td_odds = doc.create_element('td')
      td_odds.content = odds_string
      content_row.add_child(td_odds)
    end
  
    html_output = doc.to_html
    html_output.split("\n")[1..].join("\n")  # Format output similar to your example
  end
  
  def generate_encounter_markdown(map_id, include_list = nil, rods = nil, custom_map_name = nil)
    @encGetter.get_encounter_md(map_id, include_list, rods, custom_map_name)
  end

  def build_encounter_block(map_id, include_list = nil, rods = nil, custom_map_name = nil)
    @encGetter.build_encounter_data(map_id, include_list, rods, custom_map_name)
  end

  def generate_shop_markdown(shop_title, shop_items)
    @shopGetter.generate_shop_markdown(shop_title, shop_items)
  end

  def build_shop_block(shop_title, shop_items)
    @shopGetter.build_shop_data(shop_title, shop_items)
  end

  def generate_cshop_markdown(shop_symbol, shop_name, badges = 0)
    @shopGetter.generate_cshop_markdown(shop_symbol, shop_name, badges: badges)
  end

  def build_cshop_block(shop_symbol, shop_name, badges = 0)
    @shopGetter.build_cshop_data(shop_symbol, shop_name, badges: badges)
  end

  def build_move_block(move_name)
    { type: 'html', move: move_name.to_sym, html: generate_move_markdown(move_name) }
  end

  def generate_move_markdown(move_name)
    # Creates nokogiri HTML
    m = @moveHash[move_name.to_sym]
    acc = m[:accuracy] == 0 ? "Perfect" : "#{m[:accuracy]}%"
    type = m[:type] == :QMARKS ? "???" : m[:type].to_s.capitalize
    "#{m[:name]}: #{type} \\| #{m[:category].to_s.capitalize} \\| #{m[:basedamage]} Pwr \\| #{acc} Acc \\| #{m[:desc]}"
  end

  def generate_trainer_markdown(trainer_id, field = nil)
    @trainerGetter.generate_trainer_markdown(trainer_id, field)
  end

  def build_trainer_block(trainer_id, field = nil)
    @trainerGetter.build_trainer_data(trainer_id, field)
  end

  def generate_boss_markdown(boss_name, field = nil)
    @trainerGetter.generate_trainer_markdown(boss_name.to_sym, field)
  end

  def build_boss_block(boss_name, field = nil)
    @trainerGetter.build_trainer_data(boss_name.to_sym, field)
  end

  def generate_battle_tower_singles_bosses_markdown
    build_battle_tower_singles_bosses_blocks.map { |block| render_block(block) }.join("\n\n")
  end

  def build_battle_tower_singles_bosses_blocks
    return_array = []
    teams = { 'reborn' => REBORN_BT_SINGLES }[@game]
    teams.each do |team|
      field_name = FIELDS[team[3]]
      return_array.push(build_trainer_block([team[1], team[0], team[2]], field_name))
    end
    return_array
  end

  def generate_battle_tower_doubles_bosses_markdown
    build_battle_tower_doubles_bosses_blocks.map { |block| render_block(block) }.join("\n\n")
  end

  def build_battle_tower_doubles_bosses_blocks
    return_array = []
    teams = { 'reborn' => REBORN_BT_DOUBLES }[@game]
    teams.each do |team|
      field_name = FIELDS[team[3]]
      block = build_trainer_block([team[1], team[0], team[2]], field_name)
      block[:double] = true
      return_array.push(block)
    end
    return_array
  end

  def generate_theme_teams_markdown
    build_theme_teams_blocks.map { |block| render_block(block) }.join("\n\n")
  end

  def build_theme_teams_blocks
    return_array = []
    teams = { 'reborn' => REBORN_THEME_TEAMS }[@game]
    teams.each do |team|
      fight, data = @trainerHash.find { |fight, _data| fight[0] == team[:trainer] && fight[2] == team[:teamnumber] }
      field_name = FIELDS[team[:field]]
      block = build_bp_trainer_block(fight, field_name, team_name = "(#{team[:name]})")
      block[:teamName] = team[:name]
      block[:double] = team[:doubles]
      return_array.push(block)
    end

    return_array
  end

  def generate_bp_trainer_markdown(trainer_id, field_text = 'Random Field', team_name = '')
    render_block(build_bp_trainer_block(trainer_id, field_text, team_name))
  end

  def build_bp_trainer_block(trainer_id, field_text = 'Random Field', team_name = '')
    @trainerGetter.build_trainer_data(trainer_id, field = field_text, nil, 0, name_ext = team_name)
  end

  def generate_double_markdown(trainer_id1, trainer_id2, field = nil)
    @trainerGetter.generate_trainer_markdown(trainer_id1, field, trainer_id2)
  end

  def build_double_block(trainer_id1, trainer_id2, field = nil)
    @trainerGetter.build_trainer_data(trainer_id1, field, trainer_id2)
  end

  def generate_partner_markdown(trainer_id)
    @trainerGetter.generate_trainer_markdown(trainer_id, nil, nil, 1)
  end

  def build_partner_block(trainer_id)
    @trainerGetter.build_trainer_data(trainer_id, nil, nil, 1)
  end

  def generate_newself_markdown(trainer_id, new_title=nil)
    return @trainerGetter.generate_trainer_markdown(trainer_id, nil, nil, 2, new_title) if new_title
    return @trainerGetter.generate_trainer_markdown(trainer_id, nil, nil, 2)
  end

  def build_newself_block(trainer_id, new_title=nil)
    return @trainerGetter.build_trainer_data(trainer_id, nil, nil, 2, new_title) if new_title
    return @trainerGetter.build_trainer_data(trainer_id, nil, nil, 2)
  end

  def generate_tutor_markdown(tutor_title, moves)
    render_block(build_tutor_block(tutor_title, moves))
  end

  def build_tutor_block(tutor_title, moves)
    @moveNameLookup ||= @moveHash.each_with_object({}) do |(sym, data), lookup|
      lookup[data[:name]] ||= sym
      lookup[data[:longname]] ||= sym if data[:longname]
    end
    moves = moves.map { |move, price| { move: @moveNameLookup[move], name: move, price: price } }
    { type: 'tutor', title: tutor_title, moves: moves }
  end

  def render_tutor_html(block)
    # Creates nokogiri HTML
    doc = Nokogiri::HTML::Document.new
    div = doc.create_element('div', class: 'tutor_table')
    doc.add_child(div)

    table = doc.create_element('table')
    div.add_child(table)

    # Creates the header for the table
    thead = doc.create_element('thead')
    table.add_child(thead)

    table_header = doc.create_element('th', colspan: 2)
    thead.add_child(table_header)

    bold = doc.create_element('strong')
    bold.content = block[:title]
    table_header.add_child(bold)
    table_header['class'] = 'table-header'
    table_header['style'] = 'text-align: center;'

    block[:moves].each do |entry|
      move, price = entry[:name], entry[:price]
      content_row = doc.create_element('tr')
      table.add_child(content_row)

      # Column 1: Move Name (bolded)
      td_move = doc.create_element('td', style: 'text-align: center')
      td_move.add_child(doc.create_element('strong', content = move))
      content_row.add_child(td_move)

      # Column 2: Price
      price = "$#{price}" if price.is_a?(Integer)
      td_price = doc.create_element('td', style: 'text-align: center')
      td_price.content = price
      content_row.add_child(td_price)
    end

    html_output = doc.to_html
    html_output.split("\n")[1..].join("\n")
  end

  def build_raid_den_block(den_num, num_badges)
    { type: 'html', html: generate_raid_den_markdown(den_num, num_badges) }
  end

  def generate_raid_den_markdown(den_num, num_badges)
    res = []

    [:common, :rare].each do |rarity|

      # Create a Nokogiri document
      doc = Nokogiri::HTML::Document.new
      div = doc.create_element('div', class: 'den_table')
      doc.add_child(div)
    
      table = doc.create_element('table')
      div.add_child(table)
    
      # Create the header for the table
      thead = doc.create_element('thead')
      table.add_child(thead)
    
      table_header = doc.create_element('th', colspan: 4)
      thead.add_child(table_header)

      # Header Row 2: Actual table headers
      thead_row = doc.create_element('tr')

      # Add table headers for Pokemon, Shadow Moves, Stat Details, and %
      ['Pokemon', 'Shadow Moves', 'Stat Details', 'Rate'].each do |col|
        th = doc.create_element('th', col)
        th['style'] = 'text-align: center; vertical-align: middle;'
        thead_row.add_child(th)
      end

      thead.add_child(thead_row)  # Add the header row to thead
    
      bold = doc.create_element('strong')
      bold.content = "Encounters: Den \##{den_num} (#{num_badges} Badges): #{rarity.to_s.capitalize}"
      table_header.add_child(bold)
      table_header['class'] = 'table-header'
      table_header['style'] = 'text-align: center;'
    
      # Create the body of the table
      tbody = doc.create_element('tbody')
      table.add_child(tbody)
    
      # Add encounters for common and rare
      @raidDenHash["Den#{den_num}"][rarity][num_badges].each do |mon, atts|
        content_row = doc.create_element('tr')
        tbody.add_child(content_row)

        # Use actual_pokemon key for pokemonHash lookup (handles form variants like GALARSTUNFISK -> STUNFISK)
        pokemon_lookup_key = atts[:actual_pokemon] || mon
        base_form = @pokemonHash[pokemon_lookup_key].keys.find_all { |key| key.is_a?(String) }[0]
        pokemon_name_formatted = @pokemonHash[pokemon_lookup_key][base_form][:name]

        if atts[:Form] != 0
          form_key = @pokemonHash[pokemon_lookup_key].keys.find_all { |key| key.is_a?(String) }[atts[:Form]]
          pokemon_name_formatted += " (#{form_key})".sub(' Form', '')
        end
        pokemon_name_formatted = "Shadow #{pokemon_name_formatted}"

        # Column 1: Pokémon Name & Details
        td_pokemon = doc.create_element('td')
        td_pokemon.add_child(doc.create_element('strong', pokemon_name_formatted))
        mon_details_parts = [", Lv. #{atts[:level]}"]
        if atts[:Ability] 
          mon_details_parts.push("Ability: #{atts[:Ability]}")
        end
        if atts[:ShinyChance] > 0 
          mon_details_parts.push("Shiny Chance Increase: #{atts[:ShinyChance] * 100}%")
        end
        td_pokemon.add_child(mon_details_parts.reject { |s| s.empty? }.join("\n"))
        content_row.add_child(td_pokemon)

        # Column 2: Movesets
        moves_edited = []
        atts[:Moves].each do |move|
          next if move == nil
          name = @moveHash[move][:name]
          moves_edited.push(name)
        end
        final = "- " + moves_edited.join("\n- ")
        if atts[:Moves] == []
          final = "N/A"
        end
        content_row.add_child(doc.create_element('td', final))

        # Column 3: Stat Attributes (e.g., Form, ShinyChance)
        td_attributes = doc.create_element('td')
        stat_details_parts = []
        if atts[:IVs] 
          stat_details_parts.push(get_iv_str(atts[:IVs]))
        end
        if atts[:EVs]
          stat_details_parts.push(get_ev_str(atts[:EVs]))
        end
        td_attributes.add_child(stat_details_parts.reject { |s| s.empty? }.join("\n"))
        content_row.add_child(td_attributes)
        
        # Column 4: Odds
        td_odds = doc.create_element('td')
        td_odds.add_child(sprintf('%.2f', atts[:odds]) + "%")
        content_row.add_child(td_odds)
      end
    
      # Convert to HTML and format
      html_output = doc.to_html
      res.push(html_output.split("\n")[1..].join("\n"))
    end
    res = res.join("\n\n")
    res.gsub(/<td>\s*\n\s*<strong>/, '<td><strong>')
  end
end

def main
  fw = FunctionWrapper.new('reborn')
  # puts fw.generate_wild_held_markdown
end

main if __FILE__ == $PROGRAM_NAME
