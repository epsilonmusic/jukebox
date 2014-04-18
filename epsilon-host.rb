#!/usr/bin/env ruby

require 'rubygems'
require 'bundler'
Bundler.setup(:default)

require 'fileutils'
require 'yaml'
require 'ruby-mpd'

class EpsilonHost
  def initialize(config: {})
    @config = config.dup

    @config['library']  ||= "~/Music/Epsilon Library"
    @config['data_dir'] ||= "data"
  end

  def start
    # Make MPD data dir

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

    # Start MPD

    @mpd_pid = Process.spawn("mpd --no-daemon #{data("mpd.conf")}")

    [:INT, :TERM].each do |signal|
      trap signal do
        Process.kill("INT", @mpd_pid)
        Process.waitall
        exit
      end
    end

    # Connect to MPD, tell it to update

    sleep 1

    @mpd = MPD.new 'localhost', 6616
    @mpd.connect
    @mpd.update

    @mpd.add '/'
    @mpd.play

    sleep
  end

  private

  def data(path)
    File.expand_path(File.join(@config['data_dir'], path))
  end
end

if __FILE__ == $0
  if ARGV.length != 1
    abort "Usage: #$0 <path/to/config.yaml>"
  end

  EpsilonHost.new(config: YAML.load_file(ARGV[0])).start
end
