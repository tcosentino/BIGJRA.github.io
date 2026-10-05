require_relative 'test_helper'

class JsonExportTest < Minitest::Test
  RAW_DIR = File.join(TestPaths::REPO_DIR, 'src', '_raw', 'reborn')

  def index
    GeneratedOutput.json('index.json')
  end

  def dex
    GeneratedOutput.json('dex.json')
  end

  def chapters
    index['chapters'].map { |ch| GeneratedOutput.json(ch['file']) }
  end

  def all_blocks
    @all_blocks ||= chapters.flat_map { |ch| ch['sections'].flat_map { |sec| sec['blocks'] } }
  end

  def raw_macro_counts
    Dir[File.join(RAW_DIR, '*.md')].flat_map do |path|
      File.read(path, encoding: 'UTF-8').each_line.select { |l| l.start_with?('!') }.map { |l| l[1..][/\A\w+/] }
    end.tally
  end

  def test_index_metadata
    assert_equal 'reborn', index['game']
    assert_equal 'https://bigjra.github.io/reborn/', index['source']
    refute_nil index['version']
    refute_nil index['generatedAt']
    assert_equal 29, index['chapters'].length
  end

  def test_heading_ids_match_live_site_in_order
    live = File.read(File.join(TestPaths::BASELINE_DIR, 'live.html'), encoding: 'UTF-8')
    live_ids = live.scan(/<h([12]) id="([^"]*)"/).reject { |_, id| %w[project_title project_tagline].include?(id) }
    ours = index['chapters'].flat_map { |ch| [['1', ch['id']]] + ch['sections'].map { |sec| ['2', sec['id']] } }
    assert_equal live_ids, ours
  end

  def test_chapter_files_match_index
    index['chapters'].each do |entry|
      chapter = GeneratedOutput.json(entry['file'])
      assert_equal entry['id'], chapter['id']
      assert_equal entry['title'], chapter['title']
      assert_equal entry['sections'], chapter['sections'].reject { |s| s['id'].nil? }.map { |s| { 'id' => s['id'], 'title' => s['title'] } }
    end
  end

  def test_block_counts_match_macro_counts
    raw = raw_macro_counts
    by_macro = all_blocks.reject { |b| b['type'] == 'prose' }.group_by { |b| b['macro'] }.transform_values(&:length)
    %w[battle dbattle partner enc shop tutor img mine pickup wildheld].each do |macro|
      assert_equal raw[macro], by_macro[macro], "block count for !#{macro}"
    end
    assert_equal 232, by_macro['enc']
    assert_includes 84..85, by_macro['shop']

    types = all_blocks.map { |b| b['type'] }.tally
    assert_equal raw['battle'] + raw['dbattle'] + raw['partner'] + by_macro['ttbattles'] +
                 by_macro['btsinglesboss'] + by_macro['btdoublesboss'], types['battle']
    assert_equal raw['enc'], types['encounters']
    assert_equal raw['img'], types['image']
    assert_operator by_macro['ttbattles'], :>, 0
    assert_operator by_macro['btsinglesboss'], :>, 0
    assert_operator by_macro['btdoublesboss'], :>, 0
    assert_equal raw['dbattle'], all_blocks.count { |b| b['type'] == 'battle' && b['double'] }
    assert_equal raw['partner'], all_blocks.count { |b| b['type'] == 'battle' && b['partner'] }
  end

  def test_no_render_only_keys_exported
    json = File.read(File.join(GeneratedOutput.dir, 'json', 'chapters', "#{index['chapters'][0]['id']}.json"))
    refute_match(/"_\w+":/, json)
  end

  def test_prose_blocks_are_merged_and_nonempty
    chapters.each do |ch|
      ch['sections'].each do |sec|
        sec['blocks'].each_cons(2) do |a, b|
          refute(a['type'] == 'prose' && b['type'] == 'prose', "consecutive prose blocks in #{sec['id']}")
        end
        sec['blocks'].select { |b| b['type'] == 'prose' }.each { |b| refute_empty b['markdown'].strip }
      end
    end
  end

  def test_referenced_symbols_exist_in_dex
    all_blocks.each do |block|
      case block['type']
      when 'battle'
        assert dex['fields'].key?(block['field']), "field #{block['field']}" if block['field']
        block['items'].each { |i| assert dex['items'].key?(i['item']), "item #{i['item']}" }
        block['party'].each do |mon|
          assert dex['species'].key?(mon['species']), "species #{mon['species']}"
          assert dex['items'].key?(mon['item']), "item #{mon['item']}" if mon['item']
          assert dex['abilities'].key?(mon['ability']), "ability #{mon['ability']}" if mon['ability']
          (mon['abilities'] || []).each { |ab| assert dex['abilities'].key?(ab), "ability #{ab}" }
          mon['moves'].each { |m| assert dex['moves'].key?(m), "move #{m}" if m.is_a?(String) }
        end
      when 'encounters'
        block['methods'].each { |m| m['rows'].each { |r| assert dex['species'].key?(r['species']), "species #{r['species']}" } }
      when 'shop'
        block['items'].each do |i|
          assert dex['items'].key?(i['item']), "item #{i['item']}" if i['item']
          assert dex['species'].key?(i['species']), "species #{i['species']}" if i['species']
        end
      when 'tutor'
        block['moves'].each { |m| assert dex['moves'].key?(m['move']), "move #{m['move']}" if m['move'] }
      end
    end
    dex['moves'].each_value { |m| assert dex['types'].key?(m['type']), "type #{m['type']}" }
    dex['species'].each_value do |s|
      s['forms'].each_value { |f| f['types'].each { |t| assert dex['types'].key?(t), "type #{t}" } }
    end
  end

  def test_obsidia_ward_franklin_battle
    chapter = chapters.find { |ch| ch['sections'].any? { |s| s['id'] == 'obsidia-ward' } }
    section = chapter['sections'].find { |s| s['id'] == 'obsidia-ward' }
    battle = section['blocks'].find { |b| b['type'] == 'battle' && b['trainers'][0]['name'] == 'Franklin' }
    refute_nil battle
    assert_equal 'StreetRat', battle['trainers'][0]['trainerType']
    assert_equal ['Franklin', 'StreetRat', 0], battle['trainers'][0]['teamId']
    mon = battle['party'][0]
    assert_equal 'TOGEDEMARU', mon['species']
    assert_equal 13, mon['level']
    assert_equal 'IRONBARBS', mon['ability']
    assert_equal %w[THUNDERSHOCK DEFENSECURL ROLLOUT CHARGE], mon['moves']
  end

  def test_dex_spot_checks
    assert_equal 'ELECTRIC', dex['moves']['THUNDERSHOCK']['type']
    assert_kind_of Integer, dex['moves']['THUNDERSHOCK']['power']
    assert_operator dex['moves']['THUNDERSHOCK']['power'], :>, 0
    types = dex['species']['TOGEDEMARU']['forms']['0']['types']
    assert_includes types, 'ELECTRIC'
    assert_includes types, 'STEEL'
  end

  def test_encounter_block_shape
    block = all_blocks.find { |b| b['type'] == 'encounters' }
    assert_kind_of Integer, block['mapId']
    refute_empty block['methods']
    row = block['methods'][0]['rows'][0]
    %w[species form minLevel maxLevel rate].each { |key| assert row.key?(key), key }
  end

  def test_pokedex_covers_all_species_with_evolutions_and_locations
    data = GeneratedOutput.json('pokedex.json')
    pokedex = data['species']
    assert_equal 'Water Stone', data['items']['WATERSTONE']
    assert_equal 'Overgrow', data['abilities']['OVERGROW']['name']
    assert_operator pokedex.length, :>=, 800
    bulba = pokedex['BULBASAUR']
    assert_equal 1, bulba['num']
    assert_equal [{ 'species' => 'IVYSAUR', 'method' => 'Level', 'parameter' => 16 }], bulba['forms']['0']['evolutions']
    pokedex.each_value do |s|
      s['forms'].each_value do |f|
        f['abilities'].each { |ab| assert data['abilities'].key?(ab), "ability #{ab}" }
        f['evolutions'].each { |e| assert pokedex.key?(e['species']), "evolution target #{e['species']}" }
      end
    end

    # Every encountered species carries the section it appears in
    encountered = all_blocks.select { |b| b['type'] == 'encounters' }
                            .flat_map { |b| b['methods'].flat_map { |m| m['rows'].map { |r| r['species'] } } }.uniq
    encountered.each { |sym| refute_empty pokedex[sym]['locations'], "locations for #{sym}" }
    section_ids = index['chapters'].flat_map { |ch| [ch['id']] + ch['sections'].map { |s| s['id'] } }
    pokedex.each_value { |s| s['locations'].each { |l| assert_includes section_ids, l['sectionId'] } }
  end
end
