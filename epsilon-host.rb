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
require 'thread'

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

    @event_queue = Queue.new
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

    @mpd_pid = Process.spawn("mpd", "--no-daemon", data("mpd.conf"))

    [:INT, :TERM].each do |signal|
      trap signal, :DEFAULT
    end

    # Connect to MPD, tell it to update

    @mpd = MPD.new 'localhost', 6616, :callbacks => true

    proc do
      @log.debug "Connecting to MPD"
      begin
        @mpd.connect
      rescue
        sleep 0.1
        redo
      end
    end.call

    @log.debug "Connected to MPD; clearing state"

    @mpd.clear

    @log.debug "Updating database"

    @mpd.update
    sleep 1 while @mpd.status[:updating_db]

    @log.debug "Database updated"

    # Generate queue and upload

    @log.debug "Generating queue"

    @mpd.add '/'

    upload_queue

    # Open command stream

    open_command_stream

    # Start playing

    @mpd.on :song do |song|
      @log.info "Song changed to #{song.artist} - #{song.title}"
      send_position
    end

    @mpd.on :state do |state|
      if state == :play
        @log.info "Started playing"
        send_position
      end
    end

    @mpd.repeat = true

    @mpd.play

    loop do
      event, data = @event_queue.pop

      case event
      when "movesong"
        @log.info "Move ##{data['src_pos']} => ##{data['dest_pos']} requested"
        @mpd.move data['src_pos'], data['dest_pos']
      when "setposition"
        @log.info "Set position = ##{data['position']} requested"
        @mpd.play data['position']
      when "pause"
        unless @mpd.paused?
          @log.info "Pause requested"
          @mpd.pause = true
        else
          @log.info "Pause requested, but already paused"
        end
      when "unpause"
        if @mpd.paused?
          @log.info "Unpause requested"
          @mpd.pause = false
        else
          @log.info "Unpause requested, but not paused"
        end
      else
        @log.warn "Unknown event received: #{event} #{data.inspect}"
      end
    end
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

  def upload_queue
    connect_to_hub do |http|
      r = Net::HTTP::Put.new(hub_path('host'))

      r['Content-Type'] = 'application/json'
      r.body = {
        'queue' => @mpd.queue.map { |song| format_mpd_song(song) }
      }.to_json

      res = http.request(r)

      @log.debug "Queue uploaded, response = #{res.inspect}"
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

  def open_command_stream
    @command_stream_thread ||= Thread.start do
      @log.debug "Connecting to command stream"

      connect_to_hub do |http|
        req = Net::HTTP::Get.new(hub_path('host/commands.stream'))

        http.request(req) do |res|
          if res.is_a? Net::HTTPOK
            @log.debug "Connected to command stream"

            buffer = ""

            res.read_body do |chunk|
              buffer << chunk

              while message = buffer.slice!(/(?:(?!\r?\n\r?\n).)*\r?\n\r?\n/m)
                p message

                event = message.match(/^event: (.*)/)[1]
                data  = JSON.parse(message.match(/^data: (.*)/)[1])

                @event_queue << [event, data]
              end
            end

            @log.warn "Command stream ended!"
          else
            @log.warn "Failed to connect to command stream"
          end
        end
      end
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
