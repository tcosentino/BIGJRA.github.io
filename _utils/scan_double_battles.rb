# Scans a game's map events for trainer battles the game runs as double battles against ONE trainer
# (pbTrainerBattle / pbTrainerBattle100 with doublebattle = true) and writes the lookup the JSON export
# reads to set `double: true` on single-trainer `!battle` blocks (see load_double_battles in common.rb).
#
# Two-trainer doubles (pbDoubleTrainerBattle) are already marked by the `!dbattle` macro and are not listed.
# The output is committed so builds do not need the game's Data folder; rerun this when the game updates.
#
# Usage: ruby _utils/scan_double_battles.rb <game> <game Data dir>
#   e.g. ruby _utils/scan_double_battles.rb reborn ../Reborn.app/Contents/Game/Data
require 'json'
require_relative 'common'

# Minimal stand-ins for the RGSS classes Marshal needs to load MapXXX.rxdata; only event lists are read.
class Table; def self._load(_s) = allocate; end
class Color; def self._load(_s) = allocate; end
class Tone; def self._load(_s) = allocate; end
module RPG
  class Map; attr_reader :events; end
  class Event
    attr_reader :id, :pages
    class Page
      attr_reader :list
      class Condition; end
      class Graphic; end
    end
  end
  class EventCommand; attr_reader :code, :parameters; end
  class MoveRoute; end
  class MoveCommand; end
  class AudioFile; end
end

module DoubleBattleScan
  SCRIPT = 355 # Script command; continuation lines are 655
  SCRIPT_MORE = 655
  CONDITIONAL = 111 # Conditional branch; parameters [12, "<script>"] is a script condition
  CALL = /(?<![\w.])(pbTrainerBattle(?:100)?)\(/

  module_function

  # Splits the argument list starting at str[start] (just after the opening paren) on top-level commas.
  def split_args(str, start)
    args = []
    depth = 0
    quote = nil
    cur = +''
    i = start
    while i < str.length
      ch = str[i]
      if quote
        cur << ch
        if ch == '\\'
          cur << str[i + 1].to_s
          i += 1
        elsif ch == quote
          quote = nil
        end
      elsif ch == '"' || ch == "'"
        quote = ch
        cur << ch
      elsif '([{'.include?(ch)
        depth += 1
        cur << ch
      elsif ')]}'.include?(ch)
        if depth.zero?
          args << cur.strip
          args.pop if args.last.empty? # trailing comma: f(a, b,)
          return args
        end
        depth -= 1
        cur << ch
      elsif ch == ',' && depth.zero?
        args << cur.strip
        cur = +''
      else
        cur << ch
      end
      i += 1
    end
    nil # unterminated (script continues somewhere we did not join)
  end

  # Literal value of a positional argument, or :dynamic when it is an expression.
  def literal(arg)
    case arg
    when nil then nil
    when /\A:(\w+)\z/ then Regexp.last_match(1).to_sym
    when /\A"((?:[^"\\]|\\.)*)"\z/, /\A'((?:[^'\\]|\\.)*)'\z/ then Regexp.last_match(1)
    when 'true' then true
    when 'false', 'nil' then false
    when /\A\d+\z/ then arg.to_i
    else :dynamic
    end
  end

  # Script strings of an event page: script commands joined with their continuation lines,
  # plus script conditions of conditional branches.
  def page_scripts(list)
    scripts = []
    list.each do |cmd|
      case cmd.code
      when SCRIPT then scripts << cmd.parameters[0].to_s.dup
      when SCRIPT_MORE then scripts.last << "\n" << cmd.parameters[0].to_s if scripts.last
      when CONDITIONAL then scripts << cmd.parameters[1].to_s if cmd.parameters[0] == 12
      end
    end
    scripts
  end

  # Every pbTrainerBattle/pbTrainerBattle100 call in the game's maps:
  # { fn:, type:, name:, party:, double:, map:, event: }
  def calls(data_dir)
    found = []
    Dir[File.join(data_dir, 'Map[0-9]*.rxdata')].sort.each do |path|
      map_id = File.basename(path)[/\d+/].to_i
      map = File.open(path, 'rb') { |io| Marshal.load(io) }
      map.events.each_value do |ev|
        ev.pages.each do |page|
          page_scripts(page.list).each do |script|
            script.to_enum(:scan, CALL).each do
              m = Regexp.last_match
              args = split_args(script, m.end(0))
              next unless args
              # (trainerid, trainername, endspeech, doublebattle = false, trainerparty = 0, ...)
              found << { fn: m[1], type: literal(args[0]), name: literal(args[1]),
                         double: args[3] ? literal(args[3]) : false,
                         party: args[4] ? literal(args[4]) : 0, map: map_id, event: ev.id }
            end
          end
        end
      end
    end
    found
  end

  # Groups calls by team id [name, type, party] and keeps the teams every call fights as a double.
  # Returns [doubles, conflicts]: conflicts are teams fought both ways (or with a non-literal flag).
  def doubles(calls)
    usable = calls.select { |c| c[:type].is_a?(Symbol) && c[:name].is_a?(String) && c[:party].is_a?(Integer) }
    by_team = usable.group_by { |c| [c[:name], c[:type], c[:party]] }
    doubles = []
    conflicts = []
    by_team.each do |team, cs|
      flags = cs.map { |c| c[:double] }.uniq
      next if flags == [false]
      events = cs.map { |c| "#{c[:map]}:#{c[:event]}" }.uniq
      if flags == [true]
        doubles << { name: team[0], type: team[1].to_s, party: team[2], events: events }
      else
        conflicts << { name: team[0], type: team[1].to_s, party: team[2], flags: flags.map(&:to_s), events: events }
      end
    end
    sort = ->(list) { list.sort_by { |d| [d[:type], d[:name], d[:party]] } }
    [sort.(doubles), sort.(conflicts)]
  end
end

if $PROGRAM_NAME == __FILE__
  game, data_dir = ARGV
  abort 'usage: ruby _utils/scan_double_battles.rb <game> <game Data dir>' unless game && data_dir
  abort "No Map*.rxdata in #{data_dir}" if Dir[File.join(data_dir, 'Map[0-9]*.rxdata')].empty?
  calls = DoubleBattleScan.calls(data_dir)
  doubles, conflicts = DoubleBattleScan.doubles(calls)
  out = double_battles_path(game)
  File.write(out, JSON.pretty_generate({
    note: 'Generated by _utils/scan_double_battles.rb from the game map events. Teams ([name, type, party]) ' \
          'that pbTrainerBattle/pbTrainerBattle100 always start as a double battle against one trainer.',
    doubles: doubles,
    conflicts: conflicts
  }) + "\n")
  puts "#{calls.length} trainer battle calls, #{doubles.length} single-trainer doubles, #{conflicts.length} conflicts -> #{out}"
end
