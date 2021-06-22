require 'csv'
require 'progress_bar'

# Extends CSV class to include progress bar enhancement
class CSV
  module ProgressBar
    def progress_bar
      ::ProgressBar.new(@io.size, :bar, :counter, :percentage, :elapsed, :rate, :eta)
    end

    def each
      progress_bar = self.progress_bar

      super do |row|
        yield row
        progress_bar.count = pos
        progress_bar.increment!(0)
      end
    end
  end

  class WithProgressBar < CSV
    include ProgressBar
  end

  def self.with_progress_bar
    WithProgressBar
  end
end
