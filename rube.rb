#!/usr/bin/env ruby
# encoding: utf-8

# interpreter for RubE On Conveyor Belts
# https://esolangs.org/wiki/RubE_On_Conveyor_Belts

# raydeejay (2019/04/16 at 14:33)
#   ruby
#   I'm implementing RubE (on Conveyor Belts) on Ruby (on Rails)
#   (only I'm not actually using Rails, but I'm upping the pun factor here)

require 'singleton'

# Ruby magic
##############################
module AttrBoolean
  def self.included(base)
    base.extend ClassMethods
  end

  module ClassMethods
    def attr_boolean(*names)
      names.each do |name|
        define_method(:"#{name}=") do |value|
          instance_variable_set(:"@#{name}", value)
        end

        define_method(:"#{name}?") do
          !!instance_variable_get(:"@#{name}")
        end
      end
    end
  end
end

# Utility code
##############################
def moveto(x, y)
  print "\x1B[#{y+1};#{x+1}H"
end

def clear()
  print "\x1B[2J"
end

def colorForChar(c)
  {
    "=" => "33",
    "-" => "31",
    "+" => "32",
    "<" => "37;1",
    ">" => "37;1",
    "(" => "33;1",
    ")" => "33;1",
    "#" => "31;1",
    "\"" => "36;1",
    "[" => "35;1",
  }[c] or "0"
end

def printCode(code, x, y)
  moveto(x, y)
  print "\x1B[0m "
  moveto(x, y)
  print "\x1B[#{colorForChar(code)}m#{code}\x1B[0m"
end


################################
# Loading the grid
if ARGV.length == 1 then
  s = File.new(ARGV[0], "r")
else
  print "no program\n"
  exit 1
end

code = s.collect { |line| line }
s.close()

# Global-ish vars, need refactor
################################
vars = [0]
varl = varp = 0
posx = posy = 0
oldx = oldy = 0
dirx = 1
diry = 0
elevator = false
skip = 0
$output = ""
$outputCount = 20
visual = (ARGV.length == 1)
$delay = 0.1
prefix = 0
should_collect = false

$codeGrid = Array.new(25) { Array.new(80) { $empty } }

$futureCodeGrid = $codeGrid.map do |each| each.dup end

$dirty = []

# Independent-ish code
##############################
def pushBlocksLeft(x, y)
  # can't push if outside the grid
  return false if y < 0 or y >= 25 or x < 0 or x >= 80

  pos_left_edge = x
  pos_left_edge -= 1 while $codeGrid[y][pos_left_edge].crate? and pos_left_edge > 0

  # can't push into the edge of the program
  return false if pos_left_edge == 0

  # can only push into transparent parts (empty, furnace, ramp)
  return false if (not $codeGrid[y][pos_left_edge].transparent? and not $dirty.include?([x, y]))

  # can only push into an empty ramp
  return false if $codeGrid[y][pos_left_edge] == RampLeft.instance and not pushBlocksLeft(pos_left_edge-1, y-1)

  # do some pushing
  (pos_left_edge..x-1).each do | xx |
    $futureCodeGrid[y][xx] = $codeGrid[y][xx+1]
    $futureCodeGrid[y][xx+1] = Empty.instance
  end

  # if we pushed into a furnace, erase the crate and restore the furnace
  if $codeGrid[y][pos_left_edge] == Furnace.instance
    $futureCodeGrid[y][pos_left_edge] = Furnace.instance
  end

  # if we pushed into a ramp
  if $codeGrid[y][pos_left_edge] == RampLeft.instance
    $futureCodeGrid[y-1][pos_left_edge-1] = $futureCodeGrid[y][pos_left_edge]
    $futureCodeGrid[y][pos_left_edge] = RampLeft.instance
  end

  return true
end

def pushBlocksRight(x, y)
  # can't push if outside the grid
  return false if y < 0 or y >= 25 or x < 0 or x >= 80

  pos_right_edge = x
  pos_right_edge += 1 while $codeGrid[y][pos_right_edge].crate? and pos_right_edge < 80-1

  # can't push into the edge of the program
  return false if pos_right_edge == 80-1

  # can only push into *non-dirty* transparent parts (empty, furnace, ramp)
  return false if not ($codeGrid[y][pos_right_edge].transparent? and not $dirty.include?([x, y]))

  # can only push into an empty ramp
  return false if $codeGrid[y][pos_right_edge] == RampRight.instance and not pushBlocksRight(pos_right_edge+1, y-1)

  was_furnace = $codeGrid[y][pos_right_edge] == Furnace.instance
  was_ramp = $codeGrid[y][pos_right_edge] == RampRight.instance

  # do some pushing, marking blockd as dirty
  (x+1..pos_right_edge).reverse_each do | xx |
    $dirty << [xx, y]
    $futureCodeGrid[y][xx] = $codeGrid[y][xx-1]
    $futureCodeGrid[y][xx-1] = Empty.instance
  end

  # if we pushed into a furnace, erase the crate and restore the furnace
  if was_furnace
    $codeGrid[y][pos_right_edge] == Furnace.instance
    $futureCodeGrid[y][pos_right_edge] = Furnace.instance
  end

  # if we pushed into a ramp
  if was_ramp
    $futureCodeGrid[y-1][pos_right_edge+1] = $futureCodeGrid[y][pos_right_edge]
    $futureCodeGrid[y][pos_right_edge] = RampRight.instance
  end

  return true
end

# Classes
##############################
class Part
  include AttrBoolean

  attr_boolean :crate, :transparent
  attr_reader :char, :category

  def initialize
    # override to redefine attributes
    @crate = false
    @transparent = false
    @char = ' '
    @category = 1
  end

  def action(x, y)
    # override to define an action
  end
end

class SingletonPart < Part
  include Singleton
end

class TurningPoint < Part
  def char
    "T"
  end
end

class Scanner < SingletonPart
  def char
    "*"
  end

  def category
    0
  end

  def action(x, y)
    $output << "Scanner action\n"
  end
end

class Input < SingletonPart
  def char
    "?"
  end

  def category
    0
  end

  def action(x, y)
    $output << "Input action\n"
 end
end

class Furnace < SingletonPart
  def transparent?
    true
  end

  def char
    "F"
  end

  def category
    1
  end

  def action(x, y)
  end
end

class BulldozerLeft < SingletonPart
  def initialize
    super
    @category = 4
    @char = ']'
  end

  def action(x, y)
    #fall
    if y < 25-1 and $codeGrid[y+1][x].crate? and not $dirty.include?([x, y+1])
      $dirty << [x, y+1]
      $futureCodeGrid[y+1][x] = self
      $futureCodeGrid[y][x] = Empty.instance
    # suck itself upwards
    elsif y > 1 and
         $codeGrid[y-1][x] == BulldozerPipe.instance and
         not $dirty.include?([x, y-1]) and
         $codeGrid[y-2][x] == Empty.instance and
         not $dirty.include?([x, y-2])
    then
      $dirty << [x, y-2]
      $futureCodeGrid[y-2][x] = self
      $futureCodeGrid[y][x] = Empty.instance
    # push and move?
    elsif x > 0
      if $codeGrid[y][x-1].crate? and not $dirty.include?([x-1, y])
        return if x <=1 or not pushBlocksLeft(x-1, y)
      elsif y < 0 and $codeGrid[y][x-1] == RampLeft.instance and not $dirty.include?([x-1, y])
        return if $codeGrid[y-1][x-1].crate? and not pushBlocksLeft(x-1, y-1)
        $dirty << [x-1, y-1]
        $futureCodeGrid[y-1][x-1] = self
        $futureCodeGrid[y][x] = Empty.instance
      else
        return if not ($codeGrid[y][x-1] == Empty.instance and not $dirty.include?([x-1, y]))
      end
      # move if a push happened
      $dirty << [x-1, y]
      $futureCodeGrid[y][x-1] = self
      $futureCodeGrid[y][x] = Empty.instance

      #turning behaviour goes here??
      # if
      # end
    end
  end
end

class ConveyorLeft < SingletonPart
  def initialize
    super
    @category = 4
    @char = '<'
  end

  def action(x, y)
    if y > 0 and x > 0 and $codeGrid[y-1][x].crate? and not $dirty.include?([x, y-1])
      pushBlocksLeft(x, y-1)
    end
  end
end

class ConveyorRight < SingletonPart
  def initialize
    super
    @category = 4
    @char = '>'
  end

  def action(x, y)
    if y > 0 and x > 0 and $codeGrid[y-1][x].crate? and not $dirty.include?([x, y-1])
      pushBlocksRight(x, y-1)
    end
  end
end

class RampLeft < SingletonPart
  def initialize
    super
    @category = 3
    @char = '\\'
    @transparent = true
  end
end

class RampRight < SingletonPart
  def initialize
    super
    @category = 3
    @char = '/'
    @transparent = true
  end
end

class CopierDown < SingletonPart
  def initialize
    super
    @category = 3
    @char = '!'
  end

  def action(x, y)
    if y > 0 and
      y < 25-1 and
      $codeGrid[y-1][x].crate? and
      $codeGrid[y+1][x] == Empty.instance and
      not $dirty.include?([x, y+1])
    then
      $dirty << [x, y+1]
      # not quite right... we want a random number from R
      # maybe introduce a method to the crates to copy them?
      $futureCodeGrid[y+1][x] = $codeGrid[y-1][x]
    end
  end
end

class BulldozerPipe < SingletonPart
  def initialize
    super
    @category = 2
    @char = '^'
  end
end

class PipeDown < SingletonPart
  def initialize
    super
    @category = 2
    @char = 'V'
  end

  def action(x, y)
    if y > 0 and
      y < 25-1 and
      $codeGrid[y-1][x].crate? and
      (not $dirty.include?([x, y-1])) and
      ($codeGrid[y+1][x] == Empty.instance or $codeGrid[y+1][x] == self) and
      (not $dirty.include?([x, y+1]))
    then
      out_y = y
      out_y +=1 while (out_y < 25-1 and $codeGrid[out_y][x] == self)

      # can't output unless there's empty non-dirty space
      return if $codeGrid[out_y][x] != Empty.instance or $dirty.include?([x, out_y])

      $dirty << [x, out_y]
      $futureCodeGrid[out_y][x] = $codeGrid[y-1][x]
      $futureCodeGrid[y-1][x] = Empty.instance
    end
  end
end

class Crate < Part
  attr_accessor :value

  def initialize(value)
    @value = value
    @crate = true
    @category = 3
  end

  def char
    case @value
    when (0..9)
      @value.to_s
    else
      "b"
    end
  end

  def action(x, y)
    # fall
    if y < 25-1 and $codeGrid[y+1][x] == Empty.instance and not $dirty.include?([x, y+1])
      $dirty << [x, y+1]
      $futureCodeGrid[y+1][x] = $futureCodeGrid[y][x]
      $futureCodeGrid[y][x] = Empty.instance
    end
  end
end

class RandomCrate < SingletonPart
  attr_accessor :value

  def initialize
    super
    @crate = true
    @category = 1
    @char = "r"
    @value = 0
  end

  def action(x, y)
    # change into a numerical crate if not directly above or below a copier
    if not ((y < 25-1 and $codeGrid[y+1][x] == CopierDown.instance) or
            (y > 0 and $codeGrid[y-1][x] == CopierDown.instance))
    then
      $dirty << [x, y]
      $futureCodeGrid[y][x] = Crate.new(rand(0..9))
    end

    # fall
    if y < 25-1 and $codeGrid[y+1][x] == Empty.instance and not $dirty.include?([x, y+1])
      $dirty << [x, y+1]
      $futureCodeGrid[y+1][x] = $futureCodeGrid[y][x]
      $futureCodeGrid[y][x] = Empty.instance
    end
  end
end

class Empty < SingletonPart
  def char
    " "
  end

  def transparent?
    true
  end
end

class Wall < Part
  def initialize(char)
    super()
    @char = char
  end
end


# file must be 80x25
# lines are padded or cut as necessary
# blank lines are added at the end if necessary

# reverse the lines, to read the parts and add them to the arrays in evaluation order
# use the loaded lines otherwise


def loadChar(char, x, y)
  entity = Empty.instance
  data = 0

  case char
  when 'F'
    entity = Furnace.instance
  when '*'
    entity = Scanner.instance
  when '<'
    entity = ConveyorLeft.instance
  when '>'
    entity = ConveyorRight.instance
  when ']'
    entity = BulldozerLeft.instance
  when '\\'
    entity = RampLeft.instance
  when '/'
    entity = RampRight.instance
  when '!'
    entity = CopierDown.instance
  when '^'
    entity = BulldozerPipe.instance
  when 'V'
    entity = PipeDown.instance
  when 'r'
    entity = RandomCrate.instance
  when 'b'
    data = 0
  when ('0'..'9')
    entity = Crate.new(char.to_i)
  when ' '
    entity = Empty.instance
  else
    entity = Wall.new(char)
  end

  $codeGrid[y][x] = entity
end

def load_grid(code)
  code.each.with_index do | line, y |
    line.split('').each.with_index do | char, x |
      loadChar(char, x, y)
    end
  end
end

def printLevel(code)
  clear()

  moveto(0, 0)
  $codeGrid.each.with_index do | line, y |
    moveto(0, y)
    print "\x1B[K"
    line.each.with_index do | part, x |
      printCode(part.char, x, y)
    end
  end

  moveto(0, code.length + 1)
  print "Output:\n"
  moveto(0, code.length + 2)
  u = $output.split("\n").last($outputCount).join("\n")
  print "\x1B[0J#{u}"
end

$controlProgram = '+[dsti[o[-]]+]'

def run_one_step(code)
  # copy the grid into the future one
  # $futureCodeGrid = $codeGrid.map do |each| each.dup end

  # (re)create the parts processing order list(s)
  processing_list = Array.new(6) { Array.new }

  # run through the rows from bottom to top, as per the spec
  $codeGrid.reverse_each.with_index do | row, y |
    row.each.with_index do | cell, x |
      if cell != $empty and cell != $wall then
        processing_list[cell.category] << [cell, x, 25-1-y]
      end
    end
  end

  # # run through the rows from bottom to top, as per the spec
  # $codeGrid.each.with_index do | row, y |
  #   row.each.with_index do | cell, x |
  #     if cell != $empty and cell != $wall then
  #       processing_list[cell.category] << [cell, x, y]
  #     end
  #   end
  # end

  # activate each part in the proper order
  processing_list.each do | category |
    # copy the grid into the future one

    category.each do | entry |
      $futureCodeGrid = $codeGrid.map do |each| each.dup end
      entry[0].action(entry[1], entry[2])
      $codeGrid = $futureCodeGrid
    end

  end

  # make the future the present
  # $codeGrid = $futureCodeGrid
end

def run_one_control_cycle(code)
  # hardcoded +[dsti[o[-]]+] program
  control = $controlProgram

  control.chars.each do | command |
    case command
    when "["
    when "]"
    when "+"
    when "-"
    when ">"
    when "<"
    when "d"
      printLevel(code)
    when "i"
    when "o"
    when "s"
      sleep($delay)
    when "t"
      run_one_step(code)
    when "a"
    end
  end

  $dirty = []

  # input at head (0 if no input) (doesn't block)
  # if head not zero
  #   output
  #   set head to zero
  # set head to 1
end

load_grid(code)

(1..20).each do | each |
  run_one_control_cycle(code)
end

print "\n"
exit 1






# Old MarioLang code for temprorary reference or something
##########################################################
loop {
  oldx = posx
  oldy = posy

  if posy < 0 then
    STDERR.print "Error: trying to get out of the program!\n"
    exit 1
  end

  if skip == 0 then
    if should_collect and code[posy][posx] != "'" then
      vars[varp] = code[posy][posx].ord
      varp += 1
      vars << 0 if varp > vars.size - 1
    else
      case code[posy][posx]
      when "'"
        # varp +=1 if should_collect
        # vars << 0 if varp > vars.size - 1
        should_collect = !should_collect
      when ("0".."9")
        prefix = prefix * 10 + code[posy][posx].to_i
      when "\""
        diry = -1
        elevator = false
      when ")"
        if prefix == 0 then
          varp += 1
        else
          varp += prefix
        end
        prefix = 0
        vars << 0 while varp > vars.size - 1
      when "("
        if prefix == 0 then
          varp -= 1
        else
          varp -= prefix
        end
        prefix = 0
        if varp < 0 then
          STDERR.print "Error: trying to access Memory Cell -1\n"
          exit 1
        end
      when "+"
        if prefix == 0 then
          vars[varp] = (vars[varp] + 1) % 256
        else
          vars[varp] = (vars[varp] + prefix) % 256
        end
        prefix = 0
      when "-"
        if prefix == 0 then
          vars[varp] = (vars[varp] - 1) % 256
        else
          vars[varp] = (vars[varp] - prefix) % 256
        end
        prefix = 0
      when "."
        print vars[varp].chr if not visual
        $output << vars[varp].chr if visual
      when ":"
        print "#{vars[varp]} " if not visual
        $output << "#{vars[varp]} " if visual
      when ","
        vars[varp] = STDIN.getc.ord
      when ";"
        vars[varp] = STDIN.gets.to_i
      when ">"
        dirx = 1
      when "<"
        dirx = -1
      when "^"
        diry = -1
      when "!"
        dirx = diry = 0
      when "["
        skip = 2 if vars[varp] == 0
      when "@"
        dirx = -dirx
      end
    end

    while code[posy][posx].nil?
      code[posy] << " "
    end
  end

  exit 0 if posy == code.length - 1 or posx >= code[posy+1].length

  if "><@".include?(code[posy][posx]) and skip == 0 then
    elevator = false
    diry = 0
    posx += dirx
  elsif diry != 0 then
    skip -= 1 if skip > 0
    posy += diry
    diry = 0 if !elevator
  else
    case code[posy+1][posx]
    when "=", "|", "\""
      posx += dirx
    when "#"
      posx += dirx
      if dirx == 0 and code[posy][posx] == "!" and skip == 0 then
        elevator = true
        diry = elevdir(code, posx, posy)
        if diry == 0 then
          STDERR.print "Error: No matching elevator ending found!\n"
          exit 1
        end
        posy += diry
      end
    else
      posy += 1
    end
    skip -= 1 if skip > 0
  end
}
