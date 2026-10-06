require_relative 'test_helper'
require_relative '../_utils/scan_double_battles'

# Unit tests for the map-event scan behind _utils/double_battles/<game>.json (no game data needed).
class DoubleBattlesTest < Minitest::Test
  Cmd = Struct.new(:code, :parameters)

  def parse(script)
    m = script.match(DoubleBattleScan::CALL)
    DoubleBattleScan.split_args(script, m.end(0)).map { |a| DoubleBattleScan.literal(a) }
  end

  def test_parses_call_arguments
    args = parse('pbTrainerBattle(:CHARLOTTE,"Charlotte",_I("Hot, hot (really)!"),true,0)')
    assert_equal [:CHARLOTTE, 'Charlotte', :dynamic, true, 0], args
    assert_equal [:QCHAMP, 'BRUHCHAMP', ''], parse('pbTrainerBattle(:QCHAMP,"BRUHCHAMP","",)')
    assert_equal [:X, 'Esc \\"q\\", ok', :dynamic], parse('pbTrainerBattle100(:X,"Esc \\"q\\", ok",_I("a,b"))')
  end

  def test_ignores_double_trainer_battles
    refute_match DoubleBattleScan::CALL, 'pbDoubleTrainerBattle(:A,"A",0,"",:B,"B",0,"")'
    refute_match DoubleBattleScan::CALL, 'Kernel.pbDoubleTrainerBattle100(:A,"A",0,"",:B,"B",0,"")'
  end

  def test_page_scripts_join_continuations_and_conditions
    list = [Cmd.new(355, ['pbTrainerBattle(:A,"A",']), Cmd.new(655, ['_I("x"),true,2)']),
            Cmd.new(111, [12, 'pbTrainerBattle100(:B,"B",_I("y"),false)']), Cmd.new(111, [0, 5, 0])]
    scripts = DoubleBattleScan.page_scripts(list)
    assert_equal 2, scripts.length
    assert_equal [:A, 'A', :dynamic, true, 2], parse(scripts[0])
  end

  def test_doubles_require_every_call_to_be_double
    call = ->(name, party, double) { { type: :T, name: name, party: party, double: double, map: 1, event: 2 } }
    doubles, conflicts = DoubleBattleScan.doubles([
      call.('Always', 0, true), call.('Always', 0, true),
      call.('Never', 0, false),
      call.('Choice', 0, true), call.('Choice', 0, false),
      call.('Dyn', 0, :dynamic)
    ])
    assert_equal [['Always', 'T', 0]], doubles.map { |d| [d[:name], d[:type], d[:party]] }
    assert_equal %w[Choice Dyn], conflicts.map { |c| c[:name] }.sort
  end
end
