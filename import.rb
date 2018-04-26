#! /usr/bin/env ruby

require 'http'
require 'colorize'
require 'tty-prompt'

class API
  BASE_URL = 'https://api.deezer.com'.freeze
  TOKEN = ENV['TOKEN'].freeze
  PLAYLIST = 4_408_493_022
  Song = Struct.new(:id, :title, :artist) do
    def to_s
      "#{artist} - #{title}"
    end
  end

  def search(string)
    url = "#{BASE_URL}/search"
    response = HTTP.get(url, params: to_params(q: string))
    JSON.parse(response.to_s).fetch('data').map do |item|
      Song.new(
        item.fetch('id').to_i,
        item.fetch('title'),
        item.dig('artist', 'name')
      )
    end
  rescue StandardError
    retry
  end

  def add(songs)
    url = "#{BASE_URL}/playlist/#{PLAYLIST}/tracks"
    ids = songs.map(&:id).join(',')
    params = to_params(songs: ids)
    response = HTTP.post(url, form: params)
    JSON.parse(response.to_s)
  rescue StandardError
    retry
  end

  def to_params(params)
    { **params, output: 'json', access_token: TOKEN }
  end
end

class Parser
  attr_reader :lines

  def initialize(file_path)
    @lines = File.readlines(file_path)
  end

  def each
    lines.each { |line| yield(line.strip) }
  end
end

api = API.new
parser = Parser.new File.expand_path('./music', __dir__)
prompt = TTY::Prompt.new

songs = []
not_found = []
found_count = 0

parser.each do |search_string|
  suggested = api.search(search_string)

  if suggested.empty?
    puts "- #{search_string}".red
    not_found << search_string
    next
  end

  suggested = suggested.select do |song|
    song.to_s.casecmp(search_string).zero?
  end.first

  suggested = [suggested]

  song = if suggested.size > 1
           prompt.select(search_string, suggested.map(&:to_s))
         else
           suggested.first
         end

  songs << song
  found_count += 1

  puts "#{found_count} #{song} (#{search_string})".green

  next if songs.size < 30
  puts "Import #{songs.size} songs....".blue
  pp api.add(songs)
  songs = []
end

puts "Import #{songs.size} songs....".blue
pp api.add(songs)
puts '---------------------------'.green

puts "Found #{found_count}".green
puts "Not found #{not_found.size}".red

File.open('./not_found', 'a') { |f| f << not_found.join("\n") }
