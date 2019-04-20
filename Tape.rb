# A basic BF tape and head

class Tape
  attr_reader :head, :contents

  def initialize
    @contents = []
    @head = 0
  end

  def [](index)
    return 0 if index >= @contents.size
    @contents[index]
  end

  def []=(index, value)
    @contents << 0 while @contents.size <= index
    @contents[index] = value % 256
  end

  def read
    self[@head]
  end

  def write(value)
    self[@head] = value
    self[@head] %= 256
  end

  def increment(n = 1)
    self[@head] += n
    self[@head] %= 256
  end

  def decrement(n = 1)
    self[@head] -= n
    self[@head] %= 256
  end

  def move(n)
    @head += n
  end

  def forward(n = 1)
    self.move(n)
  end

  def backward(n = 1)
    self.move(-n)
  end
end
