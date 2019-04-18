# RubE On Conveyor Belts
  **RubE On Conveyor Belts** (abbreviated to **ROCB** in this article
  and pronounced _"Roob-Ee On Conveyor Belts"_, a bad pun on _"Ruby on
  Rails"_) is a language created in 2007 by @immibis, and based on
  Chris Pressey's @RUBE.

## File format

  The file format is the grid itself.

## Defining a Part
  To add a new Part, the Part DSL can be used like this:

    Part.define :NameOfPart do
      char! "X"
      category! 6
      empty!
      crate!
      transparent!
      action! do |x,y|
          stuff
      end
    end

    Singleton.register :NameOfPart do
      char! "X"
      category! 6
      empty!
      crate!
      transparent!
      action! do |x,y|
          stuff
      end
    end

  Singleton parts use `register` so they can make themselves eligible
  when loading a program from a file.

## The control program

  The default control program is

    +[dsti[O[-]]+]

## The main program


| dds  | dsds | dsds |
|------|------|------|
| dsds | dsds | dsds |


### Loading

  Loading happens in X phases:

  1. The text file is loaded, lines are padded/trimmed to 80 characters
  2. If the file is longer than 25 lines, additional lines are
     ignored. If it's shorter, additional 80-character blank lines are
     added until there's 25.
  3.

### Order of evaluation
  Every part in the main program performs its action, in the following
  categories - lower category numbers perform their actions first, and
  from left to right, bottom to top, within a category.

  0. output (*), input(?), splitter(separator), state control
  1. door key(actuate the door), furnace, random crate(generate random)
  2. up pipe, down pipe
  3. data/crates (??), ramps (???)
  4. gravity(global, not a part), copiers, winches
  5. dozers, conveyors (the ones to the right first, each type together, in order)
  6. gate(sorter), adder, subtracter

Evaluation happens in frames, and should be double buffered, that is:

    The results of the actions of a part will not affect the results
    of the activation of parts activated later in the same frame, and
    at the end of the frame, the output becomes input and a new frame
    is created as output.

There's a data layer and a code layer. That's because data may occupy
the same place as code.
