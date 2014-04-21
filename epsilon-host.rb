#!/usr/bin/env ruby

require 'rubygems'
require 'bundler'
Bundler.setup(:default)

require 'fileutils'
require 'json'
require 'yaml'
require 'ruby-mpd'
require 'logger'
require 'uri'
require 'net/http'

class EpsilonHost
  DEFAULT_CONFIG = {
    'library'  => "~/Music/Epsilon Library",
    'data_dir' => "data",
    'hub'      => "http://epsilon.ideahack.devyn.me/"
  }

  def initialize(config={})
    @config = DEFAULT_CONFIG.merge(config)

    @hub_uri = URI.parse(@config['hub'])

    @log = Logger.new($stderr)
  end

  def start
    unless File.directory?(data)
      initialize_data_dir
    end

    # Start MPD

    @log.info "Starting MPD"

    at_exit do
      Process.kill("INT", @mpd_pid) if @mpd_pid
      Process.waitall
    end

    @mpd_pid = Process.spawn("mpd --no-daemon #{data("mpd.conf")}")

    [:INT, :TERM].each do |signal|
      trap signal, :DEFAULT
    end

    # Connect to MPD, tell it to update

    @mpd = MPD.new 'localhost', 6616, :callbacks => true

    proc do
      @log.debug "Connecting"
      begin
        @mpd.connect
      rescue
        sleep 0.1
        redo
      end
    end.call

    @log.debug "Connected; clearing state"

    @mpd.clear

    @log.debug "Updating database"

    @mpd.update
    sleep 1 while @mpd.status[:updating_db]

    @log.debug "Database updated"

    # Generate playlist and upload

    @log.debug "Generating playlist"

    @mpd.add '/'

    upload_playlist

    # Start playing

    @mpd.on :song do |song|
      @log.info "Song changed to #{song.artist} - #{song.title}"
      send_position
    end

    @mpd.play

    sleep
  end

  def initialize_data_dir
    # Make MPD data dir

    @log.debug "Initializing data directory"

    FileUtils.mkdir_p(data("mpd"))
    FileUtils.mkdir_p(data("mpd/playlists"))
    FileUtils.touch(data("mpd/database"))

    # Write MPD config

    File.open(data("mpd.conf"), "w") do |f|
      f.write <<-END
music_directory    "#{@config['library']}"
playlist_directory "#{data("mpd")}/playlists"
db_file            "#{data("mpd")}/database"
pid_file           "#{data("mpd")}/pid"
state_file         "#{data("mpd")}/state"
sticker_file       "#{data("mpd")}/sticker.sql"
port               "6616"
auto_update        "yes"
END

      case RUBY_PLATFORM
      when /mswin/, /mingw/
        f.write <<-END

audio_output {
  type		"winmm"
  name		"WinMM"
}
END
      when /darwin/
        f.write <<-END

audio_output {
  type "osx"
  name "Core Audio"
  mixer_type "software"
}
END
      else
        f.write <<-END

audio_output {
  type		"alsa"
  name		"ALSA"
}
END
      end
    end
  end

  def upload_playlist
    connect_to_hub do |http|
      r = Net::HTTP::Put.new(hub_path('host'))

      r['Content-Type'] = 'application/json'
      r.body = {
        'playlist' => @mpd.queue.map { |song| format_mpd_song(song) }
      }.to_json

      res = http.request(r)

      @log.debug "Playlist uploaded, response = #{res.inspect}"
    end
  end

  def send_position
    connect_to_hub do |http|
      status = @mpd.status

      r = Net::HTTP::Put.new(hub_path('host/position'))

      r['Content-Type'] = 'application/json'
      r.body = {
        'position' => status[:song],
        'elapsed'  => status[:time][0]
      }.to_json

      res = http.request(r)

      @log.debug "Position sent, response = #{res.inspect}"
    end
  end

  private

  def connect_to_hub
    Net::HTTP.start(@hub_uri.host, @hub_uri.port) do |http|
      yield http
    end
  end

  def hub_path(path)
    URI.join(@hub_uri, path).path
  end

  def format_mpd_song(song)
    {
      'id'       => song.id,
      'title'    => song.title,
      'artist'   => song.artist,
      'album'    => song.album,
      'duration' => song.time
    }
  end

  def data(path="")
    File.expand_path(File.join(@config['data_dir'], path))
  end
end

if __FILE__ == $0
  if ARGV.length != 1
    abort "Usage: #$0 <path/to/config.yaml>"
  end

  EpsilonHost.new(YAML.load_file(ARGV[0])).start
end
