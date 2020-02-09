#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'csv'

class SplitCodes
  class << self
    def split(input, output)
      output_dir = File.dirname(output)
      ensure_dir(output_dir)
      csv = CSV.read(input, encoding: 'UTF-8')

      adoc = process_codes(csv)
      File.open(output, 'w') do |f|
        f.puts adoc
      end
    end

    def process_codes(csv)
      # Remove <feff>
      @headers = csv[0].map do |e|
        e.gsub(/[^A-Za-z 0-9()-]/, '')
      end

      csv.reject do |row|
        row.compact.empty?
      end[1..-1].map do |row|
        convert_row_to_clause(row)
      end.join "\n\n"
    end

    def convert_row_to_clause(row)
      title_index = 1
      title = row[title_index]

      other_rows = @headers.zip(row)

      # exclude the title from the table?
      if @exclude_title_from_table
        other_rows = other_rows[0..title_index] + other_rows[(title_index + 1)..-1]
      end

      <<~EOF
        .#{title}
        [%noheader,cols="h,1"]
        |===
        #{
          other_rows.map do |(key, value)|
            "| #{key} | #{value}\n"
          end.join("\n")
        }|===
      EOF
    end

    def ensure_dir(dir)
      FileUtils.mkdir_p(dir)
    end
  end
end

def show_usage
  puts "Usage:  #{$PROGRAM_NAME}  INPUT_CSV_FILE  OUTPUT_ADOC_FILE"
end

def main
  if ARGV.length != 2
    show_usage
    exit 1
  end

  input = ARGV[0]
  output_dir = ARGV[1]
  SplitCodes.split(input, output_dir)
end

main if $PROGRAM_NAME == __FILE__

__END__
