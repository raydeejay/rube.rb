#!/usr/bin/env ruby
# encoding: utf-8

# interpreter for RubE On Conveyor Belts
# https://esolangs.org/wiki/RubE_On_Conveyor_Belts

# raydeejay (2019/04/16 at 14:33)
#   ruby
#   I'm implementing RubE (on Conveyor Belts) on Ruby (on Rails)
#   (only I'm not actually using Rails, but I'm upping the pun factor here)

require_relative 'AttrBoolean'
require_relative 'GetKey'
require_relative 'Parts'
require_relative 'Tape'

include Parts

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
    "]" => "35;1",
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
$delay = 0.01
prefix = 0
should_collect = false
$controlProgram = '+[dsti[o[-]]+]'  # numerical input
#$controlProgram = '+[dsti[O[-]]+]'  # alphanumeric input
$input_char_on_tape = 0
$state_value = 0

# Independent-ish code
##############################
def is_dirty?(point)
  $dirty.include?(point)
end

def canFall?(x, y)
  y < $theGrid.height-1 and $theGrid[y+1][x].empty? and not is_dirty?([x, y+1])
end

def fall(x, y)
  $dirty << [x, y+1]
  $theGrid[y+1][x] = $theGrid[y][x]
  $theGrid[y][x] = Empty.instance
end

def pushBlocksLeft(x, y)
  # can't push if outside the grid
  return false if y < 0 or y >= $theGrid.height or x < 0 or x >= $theGrid.width

  pos_left_edge = x
  pos_left_edge -= 1 while $theGrid[y][pos_left_edge].crate? and pos_left_edge > 0

  # can't push into the edge of the program
  return false if pos_left_edge == 0

  # can only push into transparent parts (empty, furnace, ramp)
  return false if (not $theGrid[y][pos_left_edge].transparent? and not is_dirty?([x, y]))

  # can only push into an empty ramp
  return false if $theGrid[y][pos_left_edge] == RampLeft.instance and not pushBlocksLeft(pos_left_edge-1, y-1)

  was_furnace = $theGrid[y][pos_left_edge] == Furnace.instance
  was_ramp = $theGrid[y][pos_left_edge] == RampLeft.instance

  # do some pushing
  (pos_left_edge..x-1).each do | xx |
    $dirty << [xx, y]
    $theGrid[y][xx] = $theGrid[y][xx+1]
    $theGrid[y][xx+1] = Empty.instance
  end

  # if we pushed into a furnace, erase the crate and restore the furnace
  if was_furnace
    $theGrid[y][pos_left_edge] = Furnace.instance
  end

  # if we pushed into a ramp
  if was_ramp
    $theGrid[y-1][pos_left_edge-1] = $theGrid[y][pos_left_edge]
    $theGrid[y][pos_left_edge] = RampLeft.instance
  end

  return true
end

def pushBlocksRight(x, y)
  # can't push if outside the grid
  return false if y < 0 or y >= $theGrid.height or x < 0 or x >= $theGrid.width

  pos_right_edge = x
  pos_right_edge += 1 while $theGrid[y][pos_right_edge].crate? and pos_right_edge < $theGrid.width-1

  # can't push into the edge of the program
  return false if pos_right_edge == $theGrid.width-1

  # can only push into *non-dirty* transparent parts (empty, furnace, ramp)
  return false if not ($theGrid[y][pos_right_edge].transparent? and not is_dirty?([x, y]))

  # can only push into an empty ramp
  return false if $theGrid[y][pos_right_edge] == RampRight.instance and not pushBlocksRight(pos_right_edge+1, y-1)

  was_furnace = $theGrid[y][pos_right_edge] == Furnace.instance
  was_ramp = $theGrid[y][pos_right_edge] == RampRight.instance

  # do some pushing, marking blockd as dirty
  (x+1..pos_right_edge).reverse_each do | xx |
    $dirty << [xx, y]
    $theGrid[y][xx] = $theGrid[y][xx-1]
    $theGrid[y][xx-1] = Empty.instance
  end

  # if we pushed into a furnace, erase the crate and restore the furnace
  if was_furnace
    $theGrid[y][pos_right_edge] = Furnace.instance
  end

  # if we pushed into a ramp
  if was_ramp
    $theGrid[y-1][pos_right_edge+1] = $theGrid[y][pos_right_edge]
    $theGrid[y][pos_right_edge] = RampRight.instance
  end

  return true
end


# Program grid
##############

# This is a wrapper around an array of arrays of references to Parts
class CodeGrid
  attr_accessor :width, :height

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
      when 'D'
        entity = Door.new
      when 'b'
        entity = Crate.new.value!(0)
      when ('0'..'9')
        entity = Crate.new.value!(char.to_i)
      else
        # or simply a wall
        entity = Wall.new.value!(char)
      end
    end

    # add rows as necessary
    while y >= @codeGrid.length do
      row = Array.new
      row << Empty.instance while x >= row.length
      @codeGrid << row
    end

    # add columns as necessary
    @codeGrid[y] << Empty.instance while x >= @codeGrid[y].length

    # set the cell
    @codeGrid[y][x] = entity
  end

  def [](index)
    CodeGridRow.new(@codeGrid[index], index)
  end

  def reverse_each
    @codeGrid.reverse_each
  end

  def load(filename)
    max_length = 0
    File.open(filename, "r") do |s|
      s.each.with_index do | line, y |
        max_length = [max_length, line.length].max()
        line.split('').each.with_index do | char, x |
          loadChar(char, x, y)
        end
      end
    end

    # fix width for all the lines
    # tell the grid the new width
    @width = max_length
    @height = @codeGrid.length
  end

  def render_bottom
    moveto(0, self.height + 1)
    print "Control:\n"
    moveto(0, self.height + 2)
    print $controlProgram

    moveto(0, self.height + 5)
    print "Output:\n"
    moveto(0, self.height + 6)
    u = $output.split("\n").last($outputCount).join("\n")
    print "\x1B[0J#{u}"
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
    self.render_bottom
  end

  def render
    $blocks_to_redraw.each do |pos|
      self[pos[1]][pos[0]].render
    end
    $blocks_to_redraw = []
    self.render_bottom
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

  # interacting with the pointed at cell
  def ==(part)
    $theGrid.at(@x, @y) == part
  end

  def become(another_object)
    $theGrid[@y][@x] = another_object
  end

  def move_to(x, y)
    $theGrid[y][x] = self
    $theGrid[@y][@x] = Empty.instance
    # should wwe return THIS position or the new position?
    # return the new position for now
    $theGrid[y][x]
  end

  def part
    $theGrid.at(@x, @y)
  end

  def clear!
    $theGrid[@y][@x] = Empty.instance
    self
  end

  def render
    printCode($theGrid.at(@x, @y).char, @x, @y)
    self
  end

  # wrapping this method so it returns a position, so other methods
  # can be &. chained to it
  def crate?
    $theGrid.at(@x, @y).crate? ? self : nil
  end

  # moving through the grid
  def up
    @y.positive? ? $theGrid[@y-1][@x] : nil
  end

  def down
    @y < $theGrid.height-1 ? $theGrid[@y+1][@x] : nil
  end

  def left
    @x.positive? ? $theGrid[@y][@x-1] : nil
  end

  def right
    @x < $theGrid.width-1 ? $theGrid[@y][@x+1] : nil
  end

  # testing position
  # these may not be necessary since, whenever a cell wants to know if
  # it's not at an edge, it's because it wants to do something with
  # that position, and the movement methods already test for edgeness
  def notTopEdge?
    @y.positive? ? self : nil
  end

  def notBottomEdge?
    @y < $theGrid.height-1 ? self : nil
  end

  def notRightEdge?
    @x < $theGrid.width-1 ? self : nil
  end

  def notLeftEdge?
    @x.positive? ? self : nil
  end

  # testing properties
  def dirty?
    is_dirty?([@x, @y]) ? self : nil
  end

  def dirty!
    $dirty << [column_index, @row_index]
    self
  end

  def clean?
    (not is_dirty?([@x, @y])) ? self : nil
  end

  def clean!
    $dirty.remove([@x, @y])
    self
  end

  # proxy any unknown method to the referenced Part
  def method_missing(name, *args, &block)
    $theGrid.at(@x, @y).send(name, *args, &block)
  end
end


# Parts without an action and, therefore, no category
#####################################################
SingletonPart.register :Empty do
  char! ' '
  empty!
  transparent!
end

SingletonPart.register :TurningPoint do
  char! 'T'
end

# this part is dynamic
Part.define :Wall do
  def value!(char)
    @char = char
    return self
  end
end

# Category 0 parts
##################
SingletonPart.register :Scanner do
  char! '*'
  category! 0

  # action! do | x, y |
  #   if y < $theGrid.height-1 and $theGrid[y+1][x].crate? and not is_dirty?([x, y+1])
  #     $output << " " << $theGrid[y+1][x].number.to_s
  #   end
  # end

  action! do | x, y |
    cell = $theGrid[y][x]
    $output << " " << cell.down.number.to_s if cell&.down&.crate?&.clean?
  end
end

SingletonPart.register :LetterScanner do
  char! '$'
  category! 0

  # action! do | x, y |
  #   if y < $theGrid.height-1 and $theGrid[y+1][x].crate? and not is_dirty?([x, y+1])
  #     $output << $theGrid[y+1][x].number.chr
  #   end
  # end

  action! do | x, y |
    cell = $theGrid[y][x]
    $output << cell.down.number.chr if cell&.down&.crate?.clean?
  end
end

SingletonPart.register :Input do
  char! '?'
  category! 0

  action! do |x,y|
    if y < $theGrid.height-1 and $input_char and $theGrid[y+1][x].empty? and not is_dirty?([x, y+1])
      $theGrid[y+1][x] = Crate.new.value!($input_char)
    end
  end
end

SingletonPart.register :Splitter do
  char! 's'
  category! 0

  action! do |x,y|
    cell = $theGrid[y][x]
    if cell&.down&.crate?
      # check for space
      clear_path = true
      num_string = cell.down.number.to_s
      (1..num_string.length).each { |each| obstructed &= !!$theGrid[y][x+each].empty? }

      if clear_path
        # spawn crates
        num_string.chars.each.with_index {|c, i| $theGrid[y][x+1+i] = Crate.new.value!(c.to_i) }
        # delete self
        cell.down.clear!
      end
    end
  end
end

SingletonPart.register :StateControl do
  char! 'a'
  category! 0

  action! do |x,y|
    cell = $theGrid[y][x]
    if cell.notLeftEdge? and cell&.up&.crate?&.char&.between?('0', '9')
      #active
      cell.left.become(Wall.new.value!('=')) if cell&.left&.empty?
      cell.right.become(Wall.new.value!('=')) if cell&.right&.empty?
      cell.down.become(Wall.new.value!('|')) if cell&.down&.empty?
    else
      #inactive
      cell.left.clear! if cell&.left&.char == '='
      cell.right.clear! if cell&.right&.char == '='
      cell.down.clear! if cell&.down&.char == '|'
    end
  end
end


# Category 1 parts
##################
SingletonPart.register :Furnace do
  char! 'F'
  category! 1
  transparent!

  action! do |x,y|
    cell = $theGrid[y][x]
    cell.left.clear! if cell&.left&.crate?
    cell.right.clear! if cell&.right&.crate?
    cell.up.clear! if cell&.up&.crate?
    cell.down.clear! if cell&.down&.crate?
  end
end

Part.define :Door do
  category! 1
  char! 'D'

  @data = 0

  action! do |x,y|
    if x > 0 and x < $theGrid.width-1
      # key on the left
      left = $theGrid[y][x-1]
      right = $theGrid[y][x+1]
      if (not left.empty?) and right.empty? and (not right.dirty?) and (@data&2 != 2)
        $theGrid[y][x+1] = Wall.new.value!('=')
        @data |= 1
      end

      if left.empty? and (not left.dirty?) and (@data&1 == 1)
        $theGrid[y][x+1] = Empty.instance
        @data &= ~1
      end

      # key on the right
      left = $theGrid[y][x-1]
      right = $theGrid[y][x+1]
      if (not right.empty?) and left.empty? and (not left.dirty?) and (@data&1 != 1)
        $theGrid[y][x-1] = Wall.new.value!('=')
        @data |= 2
      end

      if right.empty? and (not right.dirty?) and (@data&2 == 2)
        $theGrid[y][x-1] = Empty.instance
        @data &= ~2
      end

      # key on the top
      up = $theGrid[y-1][x]
      down = $theGrid[y+1][x]
      if (not up.empty?) and down.empty? and (not down.dirty?) and (@data&8 != 8)
        $theGrid[y+1][x] = Wall.new.value!('=')
        @data |= 4
      end

      if up.empty? and (not up.dirty?) and (@data&4 == 4)
        $theGrid[y+1][x] = Empty.instance
        @data &= ~4
      end

      # key on the bottom
      up = $theGrid[y-1][x]
      down = $theGrid[y+1][x]
      if (not down.empty?) and up.empty? and (not up.dirty?) and (@data&4 != 4)
        $theGrid[y-1][x] = Wall.new.value!('=')
        @data |= 8
      end

      if down.empty? and (not down.dirty?) and (@data&8 == 8)
        $theGrid[y-1][x] = Empty.instance
        @data &= ~8
      end
    end
  end
end

SingletonPart.register :RandomCrate do
  crate!
  category! 1
  char! 'r'

  action! do |x,y|
    # change into a numerical crate if not directly above or below a copier
    # if not ((y < $theGrid.height-1 and $theGrid[y+1][x] == CopierDown.instance) or
    #         (y > 0 and $theGrid[y-1][x] == CopierUp.instance))

    cell = $theGrid[y][x]
    cell.become(Crate.new.value!(rand(0..9))) if cell&.down != CopierDown.instance and cell&.up != CopierUp.instance

    fall(x, y) if canFall?(x, y)
  end
end


# Category 2 parts
##################
SingletonPart.register :BulldozerPipe do
  category! 2
  char! '^'
end

SingletonPart.register :PipeDown do
  category! 2
  char! 'V'

  action! do |x,y|
    if y > 0 and
      y < $theGrid.height-1 and
      $theGrid[y-1][x].crate? and
      (not is_dirty?([x, y-1])) and
      ($theGrid[y+1][x].empty? or $theGrid[y+1][x] == self) and
      (not is_dirty?([x, y+1]))
    then
      out_y = y
      out_y +=1 while (out_y < $theGrid.height-1 and $theGrid[out_y][x] == self)

      # can't output unless there's empty non-dirty space
      return if (not $theGrid[out_y][x].empty?) or is_dirty?([x, out_y])

      $dirty << [x, out_y]
      $theGrid[out_y][x] = $theGrid[y-1][x]
      $theGrid[y-1][x] = Empty.instance
    end
  end
end

SingletonPart.register :PipeUp do
  category! 2
  char! 'A'

  action! do |x,y|
    if y > 0 and
      y < $theGrid.height-1 and
      $theGrid[y+1][x].crate? and
      (not is_dirty?([x, y+1])) and
      ($theGrid[y-1][x].empty? or $theGrid[y-1][x] == self) and
      (not is_dirty?([x, y-1]))
    then
      out_y = y
      out_y -=1 while (out_y > 0 and $theGrid[out_y][x] == self)

      # can't output unless there's empty non-dirty space
      if $theGrid[out_y][x].empty? and not $theGrid[out_y][x].dirty?
        $dirty << [x, out_y]
        $theGrid[out_y][x] = $theGrid[y+1][x]
        $theGrid[y+1][x] = Empty.instance
      end
    end
  end
end


# Category 3 parts
##################
Part.define :Crate do
  crate!
  category! 3
  char! "b"

  # attr_accessor :number

  def value!(number)
    @number = number
    return self
  end

  def number
    @number
  end

  def char
    case @number
    when (0..9)
      @number.to_s
    else
      @char
    end
  end

  action! do |x,y|
    fall(x, y) if canFall?(x, y)
  end
end

SingletonPart.register :RampLeft do
  char! '\\'
  transparent!
  category! 3

  action! do |x,y|
    if y > 0 and x < $theGrid.width-1 and $theGrid[y-1][x].crate?
      $theGrid[y][x+1] = $theGrid[y-1][x]
      $theGrid[y-1][x] = Empty.instance
    end
  end
end

SingletonPart.register :RampRight do
  char! '/'
  transparent!
  category! 3

  action! do |x,y|
    if y > 0 and x > 0 and $theGrid[y-1][x].crate?
      $theGrid[y][x-1] = $theGrid[y-1][x]
      $theGrid[y-1][x] = Empty.instance
    end
  end
end


# Category 4 parts
##################
SingletonPart.register :SwinchDown do
  category! 4
  char! 'W'

  action! do |x,y|
    cell = $theGrid[y][x]
    if cell&.up&.crate?&.clean? and cell&.down&.empty?
      cell.down.become(cell.up)
      cell.up.clear!
      $theGrid[y][x] = SwinchUp.instance
    end
  end
end

SingletonPart.register :SwinchUp do
  category! 4
  char! 'M'

  action! do |x,y|
    cell = $theGrid[y][x]
    if cell&.down&.crate?&.clean? and cell&.up&.empty?
      cell.up.become(cell.down)
      cell.down.clear!
      $theGrid[y][x] = SwinchDown.instance
    end
  end
end

SingletonPart.register :CopierDown do
  category! 4
  char! '!'

  action! do |x,y|
    if y > 0 and
      y < $theGrid.height-1 and
      $theGrid[y-1][x].crate? and
      $theGrid[y+1][x].empty? and
      not is_dirty?([x, y+1])
    then
      $dirty << [x, y+1]
      $theGrid[y+1][x] = $theGrid[y-1][x]
    end
  end
end

SingletonPart.register :CopierUp do
  category! 4
  char! 'i'

  action! do |x,y|
    if y > 0 and
      y < $theGrid.height-1 and
      $theGrid[y+1][x].crate? and
      $theGrid[y-1][x].empty? and
      not is_dirty?([x, y-1])
    then
      $dirty << [x, y-1]
      $theGrid[y-1][x] = $theGrid[y+1][x]
    end
  end
end

SingletonPart.register :CopierChar do
  category! 4
  char! '~'

  action! do |x,y|
    if y > 0 and
      y < $theGrid.height-1 and
      $theGrid[y+1][x].empty? and
      not is_dirty?([x, y+1])
    then
      $dirty << [x, y+1]
      $theGrid[y+1][x] = Crate.new.value!($theGrid[y-1][x].char.ord)
    end
  end
end


# Category 5 parts
##################
SingletonPart.register :BulldozerLeft do
  category! 5
  char! ']'

  action! do |x,y|
    if canFall?(x, y)
      fall(x, y)
    # suck itself upwards
    elsif y > 1 and
         $theGrid[y-1][x] == BulldozerPipe.instance and
         not is_dirty?([x, y-1]) and
         $theGrid[y-2][x].empty? and
         not is_dirty?([x, y-2])
    then
      $dirty << [x, y-2]
      $theGrid[y-2][x] = self
      $theGrid[y][x] = Empty.instance
    # push and move?
    elsif x > 0
      should_push = true

      if $theGrid[y][x-1].crate? and not is_dirty?([x-1, y])
        if x <=1 or not pushBlocksLeft(x-1, y)
          should_push = false
        end
      elsif y < 0 and $theGrid[y][x-1] == RampLeft.instance and not is_dirty?([x-1, y])
        if $theGrid[y-1][x-1].crate? and not pushBlocksLeft(x-1, y-1)
          should_push = false
        else
          $dirty << [x-1, y-1]
          $theGrid[y-1][x-1] = self
          $theGrid[y][x] = Empty.instance
        end
      else
        if not ($theGrid[y][x-1].empty? and not is_dirty?([x-1, y]))
          should_push = false
        end
      end

      if should_push
        # move if a push happened
        $dirty << [x-1, y]
        $theGrid[y][x-1] = self
        $theGrid[y][x] = Empty.instance

        #turning behaviour goes here??
        if y > 0 and x > 1 and $theGrid[y-1][x-2] == TurningPoint.instance
          $theGrid[y][x-1] = BulldozerRight.instance
        end
      end
    end
  end
end

SingletonPart.register :BulldozerRight do
  category! 5
  char! '['

  action! do |x,y|
    if canFall?(x, y)
      fall(x, y)
    # suck itself upwards
    elsif y > 1 and
         $theGrid[y-1][x] == BulldozerPipe.instance and
         not is_dirty?([x, y-1]) and
         $theGrid[y-2][x].empty? and
         not is_dirty?([x, y-2])
    then
      $dirty << [x, y-2]
      $theGrid[y-2][x] = self
      $theGrid[y][x] = Empty.instance
    # push and move?
    elsif x > 0
      should_push = true

      if $theGrid[y][x+1].crate? and not is_dirty?([x+1, y])
        if x >=$theGrid.width-2 or not pushBlocksRight(x+1, y)
          should_push = false
        end
      elsif y < 0 and $theGrid[y][x+1] == RampRight.instance and not is_dirty?([x+1, y])
        if $theGrid[y-1][x+1].crate? and not pushBlocksRight(x+1, y-1)
          should_push = false
        else
          $dirty << [x+1, y-1]
          $theGrid[y-1][x+1] = self
          $theGrid[y][x] = Empty.instance
        end
      else
        if not ($theGrid[y][x+1].empty? and not is_dirty?([x+1, y]))
          should_push = false
        end
      end

      if should_push
        # move if a push happened
        $dirty << [x+1, y]
        $theGrid[y][x+1] = self
        $theGrid[y][x] = Empty.instance

        #turning behaviour goes here??
        if y > 0 and x < $theGrid.width-2 and $theGrid[y-1][x+2] == TurningPoint.instance
          $theGrid[y][x+1] = BulldozerLeft.instance
        end
      end
    end
  end
end

SingletonPart.register :ConveyorLeft do
  category! 5
  char! '<'

  action! do |x,y|
    if y > 0 and x > 0 and $theGrid[y-1][x].crate? and not is_dirty?([x, y-1])
      pushBlocksLeft(x, y-1)
    end
  end
end

SingletonPart.register :ConveyorRight do
  category! 5
  char! '>'

  action! do |x,y|
    if y > 0 and x > 0 and $theGrid[y-1][x].crate? and not is_dirty?([x, y-1])
      pushBlocksRight(x, y-1)
    end
  end
end

# Category 6 parts
##################
SingletonPart.register :Gate do
  category! 6
  char! 'O'

  def action(x, y)
    if y > 0 and y < $theGrid.width-1 and $theGrid[y-1][x].crate? and (not is_dirty?([x, y-1])) and $theGrid[y+1][x].crate?
      if $theGrid[y-1][x].number > $theGrid[y+1][x].number
        #right
        if x < $theGrid.width-1 and $theGrid[y-1][x+1].empty? and not $theGrid[y-1][x+1].dirty?
          $theGrid[y-1][x+1] = $theGrid[y-1][x]
          $theGrid[y-1][x] = Empty.instance
        end
      else
        #left
        if x > 0 and $theGrid[y-1][x-1].empty? and not $theGrid[y-1][x-1].dirty?
          $theGrid[y-1][x-1] = $theGrid[y-1][x]
          $theGrid[y-1][x] = Empty.instance
        end
      end
    end
  end
end

SingletonPart.register :ReverseGate do
  category! 6
  char! 'U'

  def action(x, y)
    if y > 0 and y < $theGrid.width-1 and $theGrid[y-1][x].crate? and (not is_dirty?([x, y-1])) and $theGrid[y+1][x].crate?
      if $theGrid[y-1][x].number <= $theGrid[y+1][x].number
        #right
        if x < $theGrid.width-1 and $theGrid[y-1][x+1].empty? and not $theGrid[y-1][x+1].dirty?
          $theGrid[y-1][x+1] = $theGrid[y-1][x]
          $theGrid[y-1][x] = Empty.instance
        end
      else
        #left
        if x > 0 and $theGrid[y-1][x-1].empty? and not $theGrid[y-1][x-1].dirty?
          $theGrid[y-1][x-1] = $theGrid[y-1][x]
          $theGrid[y-1][x] = Empty.instance
        end
      end
    end
  end
end

class AbstractArithmeticPart < SingletonPart
  def calculateResult(x, y)
    raise Exception.new("#{self.class}>>#{__method__}: Subclass responsibility")
  end

  def action(x, y)
    return if x==0 or x == $theGrid.width-1 or y == $theGrid.height-1

    # ignore non-crates and dirty numerical crates
    return if not $theGrid[y+1][x-1].crate? or is_dirty?([x-1, y+1])
    return if not $theGrid[y+1][x].crate? or is_dirty?([x-1, y+1])

    # ignore random crates
    return if $theGrid[y+1][x-1] == RandomCrate.instance
    return if $theGrid[y+1][x] == RandomCrate.instance

    # needs space for the output
    return if $theGrid[y+1][x+1] != Empty.instance or is_dirty?([x+1, y+1])

    # calculate result
    result = self.calculateResult(x, y)

    # create result crate and destroy inputs
    $dirty << [x+1, y+1]
    $theGrid[y+1][x+1] = Crate.new.value!(result)
    $theGrid[y+1][x-1] = Empty.instance
    $theGrid[y+1][x] = Empty.instance
  end
end

class Adder < AbstractArithmeticPart
  register_into_parts
  def initialize
    super
    @char = "+"
    @category = 6
  end

  def calculateResult(x,y)
    $theGrid[y+1][x-1].number + $theGrid[y+1][x].number
  end
end

class Subtracter < AbstractArithmeticPart
  register_into_parts
  def initialize
    super
    @char = "-"
    @category = 6
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
      processing_list[cell.category] << [cell, x, $theGrid.height-1-y] if cell.category
    end
  end

  # activate each part in the proper order
  processing_list.each do | category |
    category.each do | entry |
      cell, x, y = entry
      cell.action(x, y)
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

  control.chars.each.with_index do | command, x |
    # show the head, this probably belongs somewhere else
    moveto(0, $theGrid.height + 3)
    print " " * (x)
    print "^   "

    case command
    when '['
    when ']'
    when '+'
      $tape.increment
    when '-'
      $tape.decrement
    when '>'
      $tape.forward
    when '<'
      $tape.backward
    when 'd'
      if $blocks_to_redraw == nil
        $theGrid.renderFull
        $blocks_to_redraw = []
      else
        $theGrid.render
      end
    when 'i'
      if key = GetKey.getkey
        if key == 27
          print "\n"
          exit 1
        end
        $tape.write(key)
      else
        $tape.write(0)
      end
    when 'o'
      $input_char = ('0'.ord..'9'.ord).include?($tape.read) ? $tape.read.chr.to_i : nil
    when 'O'
      $input_char = $tape.read.zero? ? nil : $tape.read
    when 's'
      sleep($delay)
    when 't'
      run_one_step()
    when 'a'
      $state_value = $tape.read % 10
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
$tape = Tape.new

loop {
  run_one_control_cycle()
}




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
        STDIN.echo = false
        vars[varp] = STDIN.getc.ord
        STDIN.echo = true
      when ";"
        STDIN.echo = false
        vars[varp] = STDIN.gets.to_i
        STDIN.echo = true
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
