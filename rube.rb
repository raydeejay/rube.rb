#!/usr/bin/env ruby
# encoding: utf-8

# interpreter for RubE On Conveyor Belts
# https://esolangs.org/wiki/RubE_On_Conveyor_Belts

# raydeejay (2019/04/16 at 14:33)
#   ruby
#   I'm implementing RubE (on Conveyor Belts) on Ruby (on Rails)
#   (only I'm not actually using Rails, but I'm upping the pun factor here)

require 'singleton'
require './AttrBoolean'
require './GetKey'

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
$controlProgram = '+[dsti[o[-]]+]'
$input_char_on_tape = 0


# Independent-ish code
##############################
def dirty?(point)
  $dirty.include?(point)
end

def canFall?(x, y)
  y < 25-1 and $theGrid[y+1][x].empty? and not dirty?([x, y+1])
end

def fall(x, y)
  $dirty << [x, y+1]
  $theGrid[y+1][x] = $theGrid[y][x].part
  $theGrid[y][x] = Empty.instance
end

def pushBlocksLeft(x, y)
  # can't push if outside the grid
  return false if y < 0 or y >= 25 or x < 0 or x >= 80

  pos_left_edge = x
  pos_left_edge -= 1 while $theGrid[y][pos_left_edge].crate? and pos_left_edge > 0

  # can't push into the edge of the program
  return false if pos_left_edge == 0

  # can only push into transparent parts (empty, furnace, ramp)
  return false if (not $theGrid[y][pos_left_edge].transparent? and not dirty?([x, y]))

  # can only push into an empty ramp
  return false if $theGrid[y][pos_left_edge] == RampLeft.instance and not pushBlocksLeft(pos_left_edge-1, y-1)

  was_furnace = $theGrid[y][pos_left_edge] == Furnace.instance
  was_ramp = $theGrid[y][pos_left_edge] == RampLeft.instance

  # do some pushing
  (pos_left_edge..x-1).each do | xx |
    $dirty << [xx, y]
    $theGrid[y][xx] = $theGrid[y][xx+1].part
    $theGrid[y][xx+1] = Empty.instance
  end

  # if we pushed into a furnace, erase the crate and restore the furnace
  if was_furnace
    $theGrid[y][pos_left_edge] = Furnace.instance
  end

  # if we pushed into a ramp
  if was_ramp
    $theGrid[y-1][pos_left_edge-1] = $theGrid[y][pos_left_edge].part
    $theGrid[y][pos_left_edge] = RampLeft.instance
  end

  return true
end

def pushBlocksRight(x, y)
  # can't push if outside the grid
  return false if y < 0 or y >= 25 or x < 0 or x >= 80

  pos_right_edge = x
  pos_right_edge += 1 while $theGrid[y][pos_right_edge].crate? and pos_right_edge < 80-1

  # can't push into the edge of the program
  return false if pos_right_edge == 80-1

  # can only push into *non-dirty* transparent parts (empty, furnace, ramp)
  return false if not ($theGrid[y][pos_right_edge].transparent? and not dirty?([x, y]))

  # can only push into an empty ramp
  return false if $theGrid[y][pos_right_edge] == RampRight.instance and not pushBlocksRight(pos_right_edge+1, y-1)

  was_furnace = $theGrid[y][pos_right_edge] == Furnace.instance
  was_ramp = $theGrid[y][pos_right_edge] == RampRight.instance

  # do some pushing, marking blockd as dirty
  (x+1..pos_right_edge).reverse_each do | xx |
    $dirty << [xx, y]
    $theGrid[y][xx] = $theGrid[y][xx-1].part
    $theGrid[y][xx-1] = Empty.instance
  end

  # if we pushed into a furnace, erase the crate and restore the furnace
  if was_furnace
    $theGrid[y][pos_right_edge] = Furnace.instance
  end

  # if we pushed into a ramp
  if was_ramp
    $theGrid[y-1][pos_right_edge+1] = $theGrid[y][pos_right_edge].part
    $theGrid[y][pos_right_edge] = RampRight.instance
  end

  return true
end


# Program grid
##############

# This is a wrapper around an array of arrays of references to Parts
class CodeGrid
  attr_reader :width, :height

  def initialize(width, height)
    @width = width
    @height = height
    @codeGrid = Array.new(height) { Array.new(width) { Empty.instance } }
  end

  # this method is necessary to access the cell contents directly
  # it's not meant to be used outside of the collaborator classes
  # FIXME - feels a bit like a kludge
  def at(x, y)
    @codeGrid[y][x]
  end

  def loadChar(char, x, y)
    # search for a singleton part
    if part = Part.parts.detect { |each| each.instance.char == char }
      entity = part.instance
    else
      # it's a dynamic part holding data, can't be a singleton
      case char
      when 'b'
        entity = Crate.new(0)
      when ('0'..'9')
        entity = Crate.new(char.to_i)
      else
        # or simply a wall
        entity = Wall.new(char)
      end
    end
    @codeGrid[y][x] = entity
  end

  def [](index)
    CodeGridRow.new(@codeGrid[index], index)
  end

  def reverse_each
    @codeGrid.reverse_each
  end

  def load(filename)
    File.open(filename, "r") do |s|
      s.each.with_index do | line, y |
        line.split('').each.with_index do | char, x |
          loadChar(char, x, y)
        end
      end
    end
  end

  def renderFull
    clear()

    moveto(0, 0)
    @codeGrid.each.with_index do | line, y |
      moveto(0, y)
      print "\x1B[K"
      line.each.with_index do | part, x |
        printCode(part.char, x, y)
      end
    end

    moveto(0, self.height + 1)
    print "Output:\n"
    moveto(0, self.height + 2)
    u = $output.split("\n").last($outputCount).join("\n")
    print "\x1B[0J#{u}"
  end

  def render
    $blocks_to_redraw.each do |pos|
      self[pos[1]][pos[0]].render
    end
    $blocks_to_redraw = []

    moveto(0, self.height + 1)
    print "Output:\n"
    moveto(0, self.height + 2)
    u = $output.split("\n").last($outputCount).join("\n")
    print "\x1B[0J#{u}"
  end
end

# This class wraps around a row in the CodeGrid
class CodeGridRow
  @row
  @row_index

  def initialize(row, row_index)
    @row = row
    @row_index = row_index
  end

  def [](column_index)
    CodeGridPosition.new(column_index, @row_index)
  end

  # assignment goes through to the underlying row, so we get the
  # actual part if a CodeGridPosition was passed instead
  def []=(column_index, value)
    @row[column_index] = value.part
    $dirty << [column_index, @row_index]
    $blocks_to_redraw << [column_index, @row_index]
  end
end

# This class wraps around a specific position in the CodeGrid
class CodeGridPosition
  @x
  @y

  def initialize(x, y)
    @x = x
    @y = y
  end

  def ==(part)
    $theGrid.at(@x, @y) == part
  end

  def part
    $theGrid.at(@x, @y)
  end

  def dirty?
    dirty?([@x, @y])
  end

  # proxy any unknown method to the referenced Part
  def method_missing(name, *args, &block)
    $theGrid.at(@x, @y).send(name, *args, &block)
  end

  def render
    printCode($theGrid.at(@x, @y).char, @x, @y)
  end
end



# Base part classes
##############################
class Part
  include AttrBoolean

  attr_boolean :crate, :transparent, :empty
  attr_reader :char, :category

  # every concrete part should add itself to this array
  @@parts = []
  def self.parts
    @@parts
  end

  def self.register
    @@parts << self
  end

  # this method makes CodeGridPositions and Parts polymorphic
  def part
    self
  end

  def initialize
    # override (calling super) to redefine attributes
    @empty = false
    @crate = false
    @transparent = false
    @char = nil
    @category = nil
  end

  def action(x, y)
    # override to define an action
  end
end

class SingletonPart < Part
  # subclasses of SingletonPart call `register`
  include Singleton
end


# Parts without an action (therefore no category)
#################################################
class Empty < SingletonPart
  register
  def initialize
    @char = " "
    @empty = true
    @transparent = true
  end
end

class Wall < Part
  def initialize(char)
    super()
    @char = char
  end
end

class TurningPoint < SingletonPart
  register
  def initialize
    super
    @char = "T"
  end
end


# Category 0 parts
##################
class Scanner < SingletonPart
  register
  def initialize
    super
    @char = "*"
    @category = 0
  end

  def action(x, y)
    if y < 25-1 and $theGrid[y+1][x].crate? and not dirty?([x, y+1])
      $output << " " << $theGrid[y+1][x].number.to_s
    end
  end
end

class Input < SingletonPart
  register
  def initialize
    super
    @char = "?"
    @category = 0
  end

  def action(x, y)
    if y < 25-1 and $input_char and $theGrid[y+1][x].empty? and not dirty?([x, y+1])
      $theGrid[y+1][x] = Crate.new($input_char)
    end
 end
end

class Splitter < SingletonPart
  register
  def initialize
    super
    @char = "s"
    @category = 0
  end
end

class StateControl < SingletonPart
  register
  def initialize
    super
    @char = "a"
    @category = 0
  end
end


# Category 1 parts
##################
class Furnace < SingletonPart
  register
  def initialize
    super
    @char = "F"
    @category = 1
    @transparent = true
  end

  def action(x, y)
    $theGrid[y][x+1] = Empty.instance if x < 80-1 and $theGrid[y][x+1].crate?
    $theGrid[y][x-1] = Empty.instance if x > 0 and $theGrid[y][x-1].crate?
    $theGrid[y+1][x] = Empty.instance if y < 25-1 and $theGrid[y+1][x].crate?
    $theGrid[y-1][x] = Empty.instance if y > 0 and $theGrid[y-1][x].crate?
  end
end

class Door < SingletonPart
  register
  def initialize
    super
    @category = 1
    @char = "D"
  end
end

class RandomCrate < SingletonPart
  register
  def initialize
    super
    @crate = true
    @category = 1
    @char = "r"
  end

  def action(x, y)
    # change into a numerical crate if not directly above or below a copier
    if not ((y < 25-1 and $theGrid[y+1][x] == CopierDown.instance) or
            (y > 0 and $theGrid[y-1][x] == CopierUp.instance))
    then
      $dirty << [x, y]
      $theGrid[y][x] = Crate.new(rand(0..9))
    end

    fall(x, y) if canFall?(x, y)
  end
end


# Category 2 parts
##################
class BulldozerPipe < SingletonPart
  register
  def initialize
    super
    @category = 2
    @char = '^'
  end
end

class PipeDown < SingletonPart
  register
  def initialize
    super
    @category = 2
    @char = 'V'
  end

  def action(x, y)
    if y > 0 and
      y < 25-1 and
      $theGrid[y-1][x].crate? and
      (not dirty?([x, y-1])) and
      ($theGrid[y+1][x].empty? or $theGrid[y+1][x].is(self)) and
      (not dirty?([x, y+1]))
    then
      out_y = y
      out_y +=1 while (out_y < 25-1 and $theGrid[out_y][x] == self)

      # can't output unless there's empty non-dirty space
      return if (not $theGrid[out_y][x].empty?) or dirty?([x, out_y])

      $dirty << [x, out_y]
      $theGrid[out_y][x] = $theGrid[y-1][x].part
      $theGrid[y-1][x] = Empty.instance
    end
  end
end

class PipeUp < SingletonPart
  register
  def initialize
    super
    @category = 2
    @char = 'A'
  end

  def action(x, y)
    if y > 0 and
      y < 25-1 and
      $theGrid[y+1][x].crate? and
      (not dirty?([x, y+1])) and
      ($theGrid[y-1][x].empty? or $theGrid[y-1][x] == self) and
      (not dirty?([x, y-1]))
    then
      out_y = y
      out_y -=1 while (out_y > 0 and $theGrid[out_y][x] == self)

      # can't output unless there's empty non-dirty space
      return if $theGrid[out_y][x] != Empty.instance or dirty?([x, out_y])

      $dirty << [x, out_y]
      $theGrid[out_y][x] = $theGrid[y+1][x]
      $theGrid[y+1][x] = Empty.instance
    end
  end
end


# Category 3 parts
##################
class Crate < Part
  attr_accessor :number

  def initialize(number)
    @number = number
    @crate = true
    @category = 3
    @char = "b"
  end

  def char
    case @number
    when (0..9)
      @number.to_s
    else
      @char
    end
  end

  def action(x, y)
    fall(x, y) if canFall?(x, y)
  end
end

class RampLeft < SingletonPart
  register
  def initialize
    super
    @char = '\\'
    @transparent = true
    @category = 3
  end
end

class RampRight < SingletonPart
  register
  def initialize
    super
    @char = '/'
    @transparent = true
    @category = 3
  end
end


# Category 4 parts
##################
class CopierDown < SingletonPart
  register
  def initialize
    super
    @category = 4
    @char = '!'
  end

  def action(x, y)
    if y > 0 and
      y < 25-1 and
      $theGrid[y-1][x].crate? and
      $theGrid[y+1][x].empty? and
      not dirty?([x, y+1])
    then
      $dirty << [x, y+1]
      $theGrid[y+1][x] = $theGrid[y-1][x]
    end
  end
end

class CopierUp < SingletonPart
  register
  def initialize
    super
    @category = 4
    @char = 'i'
  end

  def action(x, y)
    if y > 0 and
      y < 25-1 and
      $theGrid[y+1][x].crate? and
      $theGrid[y-1][x].empty? and
      not dirty?([x, y-1])
    then
      $dirty << [x, y-1]
      $theGrid[y-1][x] = $theGrid[y+1][x]
    end
  end
end


# Category 5 parts
##################
class BulldozerLeft < SingletonPart
  register
  def initialize
    super
    @category = 5
    @char = ']'
  end

  def action(x, y)
    if canFall?(x, y)
      fall(x, y)
    # suck itself upwards
    elsif y > 1 and
         $theGrid[y-1][x] == BulldozerPipe.instance and
         not dirty?([x, y-1]) and
         $theGrid[y-2][x].empty? and
         not dirty?([x, y-2])
    then
      $dirty << [x, y-2]
      $theGrid[y-2][x] = self
      $theGrid[y][x] = Empty.instance
    # push and move?
    elsif x > 0
      if $theGrid[y][x-1].crate? and not dirty?([x-1, y])
        return if x <=1 or not pushBlocksLeft(x-1, y)
      elsif y < 0 and $theGrid[y][x-1] == RampLeft.instance and not dirty?([x-1, y])
        return if $theGrid[y-1][x-1].crate? and not pushBlocksLeft(x-1, y-1)
        $dirty << [x-1, y-1]
        $theGrid[y-1][x-1] = self
        $theGrid[y][x] = Empty.instance
      else
        return if not ($theGrid[y][x-1].empty? and not dirty?([x-1, y]))
      end
      # move if a push happened
      $dirty << [x-1, y]
      $theGrid[y][x-1] = self
      $theGrid[y][x] = Empty.instance

      #turning behaviour goes here??
      # if
      # end
    end
  end
end

class BulldozerRight < SingletonPart
  register
  def initialize
    super
    @category = 5
    @char = '['
  end

  def action(x, y)
    if canFall?(x, y)
      fall(x, y)
  # suck itself upwards
    elsif y > 1 and
         $theGrid[y-1][x] == BulldozerPipe.instance and
         not dirty?([x, y-1]) and
         $theGrid[y-2][x].empty? and
         not dirty?([x, y-2])
    then
      $dirty << [x, y-2]
      $theGrid[y-2][x] = self
      $theGrid[y][x] = Empty.instance
    # push and move?
    elsif x > 0
      if $theGrid[y][x+1].crate? and not dirty?([x+1, y])
        return if x >=80-2 or not pushBlocksRight(x+1, y)
      elsif y < 0 and $theGrid[y][x+1] == RampRight.instance and not dirty?([x+1, y])
        return if $theGrid[y-1][x+1].crate? and not pushBlocksRight(x+1, y-1)
        $dirty << [x+1, y-1]
        $theGrid[y-1][x+1] = self
        $theGrid[y][x] = Empty.instance
      else
        return if not ($theGrid[y][x+1].empty? and not dirty?([x+1, y]))
      end
      # move if a push happened
      $dirty << [x+1, y]
      $theGrid[y][x+1] = self
      $theGrid[y][x] = Empty.instance

      #turning behaviour goes here??
      # if
      # end
    end
  end
end

class ConveyorLeft < SingletonPart
  register
  def initialize
    super
    @category = 5
    @char = '<'
  end

  def action(x, y)
    if y > 0 and x > 0 and $theGrid[y-1][x].crate? and not dirty?([x, y-1])
      pushBlocksLeft(x, y-1)
    end
  end
end

class ConveyorRight < SingletonPart
  register
  def initialize
    super
    @category = 5
    @char = '>'
  end

  def action(x, y)
    if y > 0 and x > 0 and $theGrid[y-1][x].crate? and not dirty?([x, y-1])
      pushBlocksRight(x, y-1)
    end
  end
end

# Category 6 parts
##################
class AbstractArithmeticPart < SingletonPart
  def initialize
    super
    @category = 6
  end

  def calculateResult(x, y)
    raise Exception.new("#{self.class}>>#{__method__}: Subclass responsibility")
  end

  def action(x, y)
    return if x==0 or x == 80-1 or y == 25-1

    # ignore non-crates and dirty numerical crates
    return if not $theGrid[y+1][x-1].crate? or dirty?([x-1, y+1])
    return if not $theGrid[y+1][x].crate? or dirty?([x-1, y+1])

    # ignore random crates
    return if $theGrid[y+1][x-1] == RandomCrate.instance
    return if $theGrid[y+1][x] == RandomCrate.instance

    # needs space for the output
    return if $theGrid[y+1][x+1] != Empty.instance or dirty?([x+1, y+1])

    # calculate result
    result = self.calculateResult(x, y)

    # create result crate and destroy inputs
    $dirty << [x+1, y+1]
    $theGrid[y+1][x+1] = Crate.new(result)
    $theGrid[y+1][x-1] = Empty.instance
    $theGrid[y+1][x] = Empty.instance
  end
end

class Adder < AbstractArithmeticPart
  register
  def initialize
    super
    @char = "+"
  end

  def calculateResult(x,y)
    $theGrid[y+1][x-1].number + $theGrid[y+1][x].number
  end
end

class Subtracter < AbstractArithmeticPart
  register
  def initialize
    super
    @char = "-"
  end

  def calculateResult(x,y)
    $theGrid[y+1][x-1].number - $theGrid[y+1][x].number
  end
end


# notes:
# file must be 80x25
# lines are padded or cut as necessary
# blank lines are added at the end if necessary

# the grid
#$theGrid = Array.new(25) { Array.new(80) { Empty.instance } }
$dirty = []
$blocks_to_redraw = nil

# Displaying
############


# Running
#########
def run_one_step()
  # (re)create the parts processing order list(s)
  # TODO - derive the size of this array from the highest category number
  processing_list = Array.new(7) { Array.new }

  # run through the rows from bottom to top, as per the spec
  # ignore any blocks without a category (they have no action)
  $theGrid.reverse_each.with_index do | row, y |
    row.each.with_index do | cell, x |
      processing_list[cell.category] << [cell, x, 25-1-y] if cell.category
    end
  end

  # activate each part in the proper order
  processing_list.each do | category |
    category.each do | entry |
      entry[0].action(entry[1], entry[2])
    end
  end

  # clear the dirty list
  $dirty = []

  # clear the input char
  $input_char = nil

end

def run_one_control_cycle()
  # hardcoded +[dsti[o[-]]+] program
  control = $controlProgram

  control.chars.each do | command |
    case command
    when '['
    when ']'
    when '+'
    when '-'
    when '>'
    when '<'
    when 'd'
      if $blocks_to_redraw == nil
        $theGrid.renderFull
        $blocks_to_redraw = []
      else
        $theGrid.render
      end
    when 'i'
      if key = GetKey.getkey
        $input_char_on_tape = key
      else
        $input_char_on_tape = 0
      end
    when 'o'
      $input_char = ('0'.ord..'9'.ord).include?($input_char_on_tape) ? $input_char_on_tape.chr.to_i : nil
    # when 'O'
    #   $input_char = ('0'.ord..'9'.ord).include?($input_char_on_tape) ? $input_char_on_tape : 0
    #   $input_char = $input_char_on_tape.chr
    when 's'
      sleep($delay)
    when 't'
      run_one_step()
    when 'a'
    end
  end

  # input at head (0 if no input) (doesn't block)
  # if head not zero
  #   output
  #   set head to zero
  # set head to 1
end



# Temporary entry point
#######################
input_filename = ARGV.length == 1 ? ARGV[0] : 'grid.rube'

$theGrid = CodeGrid.new(80, 25)
$theGrid.load(input_filename)

(1..120).each do | each |
  run_one_control_cycle()
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
