// Imports
var url   = require("url")
  , fs    = require("fs")
  , http  = require("http")
  , mpd   = require("mpd")
  , spawn = require("child_process").spawn
  , path  = require("path")
  ;

var DEFAULT_CONFIG = {
  library: "~/Music/Epsilon Library",
  data_dir: "data",
  hub: "http://epsilon.ideahack.devyn.me"
};

function EpsilonJukebox(config) {
  this.config = Object.create(DEFAULT_CONFIG);

  // Merge into config
  for (var key in config) {
    if (config.hasOwnProperty(key)) {
      this.config[key] = config[key];
    }
  }

  this.id = this.config.id;
  this.token = this.config.token;

  if (typeof this.id === 'undefined') {
    throw "id missing from config";
  }

  if (typeof this.token === 'undefined') {
    throw "token missing from config";
  }
}

EpsilonJukebox.prototype.start = function (callback) {
  var self = this;

  try {
    var dataDirContents = fs.readdirSync(this.data());
  } catch (e) {
    this.initializeDataDir();
  }

  this.writeMPDConfig();

  // Start MPD

  console.log("Starting MPD");

  this.mpdProcess = spawn(this.mpdPath(), 
                          ['--no-daemon', this.data('mpd.conf')]);

  this.mpdProcess.stdout.on('data', function (data) {
    console.log('mpd stdout: ' + data);
  });

  this.mpdProcess.stderr.on('data', function (data) {
    console.log('mpd stderr: ' + data);
  });

  this.mpdProcess.on('exit', function (code, signal) {
    console.log('mpd exited: ', [code, signal]);
  });

  process.on('exit', function () {
    self.stop();
  });

  process.on('SIGINT', function () {
    self.stop();
    process.exit();
  });

  process.on('SIGTERM', function () {
    self.stop();
    process.exit();
  });

  this.connectToMPD(callback);
};

EpsilonJukebox.prototype.stop = function (callback) {
  if (typeof callback === 'function') {
    this.mpdProcess.on('exit', function () { callback(); });
  }

  if (typeof this.mpdProcess !== 'undefined') {
    this.mpdProcess.kill('SIGINT');
    delete this.mpdProcess;
  }

  if (typeof this.commandStreamRequest !== 'undefined') {
    this.commandStreamRequest.abort();
    delete this.commandStreamRequest;
  }
};

EpsilonJukebox.prototype.connectToMPD = function (callback) {
  var self = this;

  // Connect to MPD (repeatedly), tell it to update
  console.log("Connecting to MPD");

  this.mpdClient = mpd.connect({host: 'localhost', port: 6616});

  this.mpdClient.on("error", function () {
    setTimeout(function () {
      self.connectToMPD(callback);
    }, 100);
  });

  this.mpdClient.on("ready", function () {
    console.log("Connected to MPD");

    if (typeof callback === 'function') callback();

    self.requeue();
  });
};

EpsilonJukebox.prototype.requeue = function () {
  var self = this;

  console.log("Updating database");

  this.mpdClient.on("system-update", function () {
    self.mpdStatus(function (status) {
      if (typeof status.updating_db === 'undefined') {
        console.log("Database updated. Generating queue");

        self.mpdClient.sendCommand(mpd.cmd("clear", []));

        self.mpdClient.sendCommand(mpd.cmd("add", ['/']), function () {
          self.uploadQueue();

          self.mpdClient.sendCommand(mpd.cmd("play", []));
        });
      }
    });
  });

  this.mpdClient.sendCommand(mpd.cmd("update", []));
};

EpsilonJukebox.prototype.mpdStatus = function (callback) {
  this.mpdClient.sendCommand(mpd.cmd("status", []), function (err, msg) {
    if (err) throw err;

    var status = {};

    msg.split("\n").forEach(function (line) {
      var md = line.match(/^([^:]+): (.*)$/);

      if (md !== null) {
        status[md[1]] = md[2];
      }
    });

    callback(status);
  });
};

EpsilonJukebox.prototype.mpdPlaylistInfo = function (callback) {
  this.mpdClient.sendCommand(mpd.cmd("playlistinfo", []), function (err, msg) {
    if (err) throw err;

    var queue = [];
    var currentSong;

    msg.split("\n").forEach(function (line) {
      var md = line.match(/^([^:]+): (.*)$/);

      if (md !== null) {
        if (md[1] == "file") {
          if (typeof currentSong !== 'undefined') {
            queue.push(currentSong);
          }
          currentSong = {};
          currentSong["file"] = md[1];
        } else {
          currentSong[md[1]] = md[2];
        }
      }
    });

    callback(queue);
  });
};

EpsilonJukebox.prototype.initializeDataDir = function () {
  console.log("Initializing data directory");

  fs.mkdirSync(this.data());
  fs.mkdirSync(this.data("mpd"));
  fs.mkdirSync(this.data("mpd/playlists"));
  fs.writeFileSync(this.data("mpd/database"), "");
};

EpsilonJukebox.prototype.writeMPDConfig = function () {
  console.log("Writing MPD config");

  var mpdConf = fs.openSync(this.data("mpd.conf"), "w");

  fs.writeSync(mpdConf,
      ['music_directory    "' + this.config.library + '"',
       'playlist_directory "' + this.dataEsc("mpd/playlists") + '"',
       'db_file            "' + this.dataEsc("mpd/database") + '"',
       'log_file           "' + this.dataEsc("mpd/log.txt") + '"',
       'pid_file           "' + this.dataEsc("mpd/pid") + '"',
       'state_file         "' + this.dataEsc("mpd/state") + '"',
       'sticker_file       "' + this.dataEsc("mpd/sticker.sql") + '"',
       'port               "6616"',
       'auto_update        "yes"'].join("\n"));

  switch (process.platform) {
    case "win32":
      fs.writeSync(mpdConf,
          ['',
           'audio_output {',
           '  type "winmm"',
           '  name "WinMM"',
           '}'].join("\n"));
      break;
    case "darwin":
      fs.writeSync(mpdConf,
          ['',
           'audio_output {',
           '  type "osx"',
           '  name "Core Audio"',
           '  mixer_type "software"',
           '}'].join("\n"));
      break;
    default:
      fs.writeSync(mpdConf,
          ['',
           'audio_output {',
           '  type "alsa"',
           '  name "ALSA"',
           '}'].join("\n"));
  }

  fs.closeSync(mpdConf);
};

EpsilonJukebox.prototype.uploadQueue = function () {
  var self = this;

  this.mpdPlaylistInfo(function (queue) {
    var data = {
      queue: queue.map(function (song) {
        return EpsilonJukebox.formatMPDSong(song);
      })
    };

    self.hubRequest("PUT", "host/" + self.id, data,
      function (res) {
        console.log("Queue uploaded, response = ", res.statusCode);

        self.openCommandStream();

        self.sendPosition();

        self.mpdClient.on("system-player", function () {
          self.sendPosition();
        });
      });
  });
};

EpsilonJukebox.prototype.sendPosition = function () {
  var self = this;

  this.mpdStatus(function (status) {
    var data = {
      position: +status.song,
      elapsed:  +status.elapsed
    };

    if (status.state === 'play') {
      console.log("Sending position: ", data);

      self.hubRequest("PUT", "host/" + self.id + "/position", data,
        function (res) {
          console.log("Position sent, response = ", res.statusCode);
        });
    }
  });
};

EpsilonJukebox.prototype.openCommandStream = function () {
  var self = this;

  console.log("Connecting to command stream");

  if (typeof this.commandStreamRequest !== 'undefined') {
    this.commandStreamRequest.abort();
    delete this.commandStreamRequest;
  }

  this.hubRequest("GET", "host/" + this.id + "/commands.stream", null,
    function (commandStream, commandStreamRequest) {
      if (commandStream.statusCode === 200) {
        console.log("Connected to command stream");

        self.commandStreamRequest = commandStreamRequest;

        var buffer = "";

        commandStream.setEncoding('utf8');

        commandStream.on('end', function () {
          console.log("Command stream ended!");

          delete self.commandStream;
        });

        commandStream.on('data', function (chunk) {
          buffer += chunk;

          for (;;) {
            var messageMatch = buffer.match(/\r?\n\r?\n/m);

            if (messageMatch === null) break;

            var message =
              buffer.slice(0, messageMatch.index + messageMatch[0].length);

            buffer = buffer.slice(message.length);

            var event = message.match(/(?:^|\n)event: (.*)/)[1]
              , data  = JSON.parse(message.match(/(?:^|\n)data: (.*)/)[1]);

            self.handleCommand(event, data);
          }
        });

        commandStream.resume();
      } else {
        console.log("Failed to connect to command stream");
      }
    });
};

EpsilonJukebox.prototype.handleCommand = function (event, data) {
  switch (event) {
    case "movesong":
      console.log("Move #", data.src_pos, " => #", data.dest_pos, " requested");
      this.mpdClient.sendCommand(
        mpd.cmd("move", [data.src_pos, data.dest_pos]));
      break;
    case "setposition":
      console.log("Set position = #", data.position, " requested");
      this.mpdClient.sendCommand(mpd.cmd("play", [data.position]));
      break;
    case "pause":
      this.pause();
      break;
    case "unpause":
      this.unpause();
      break;
    default:
      console.log("Unknown event received: ", event, data);
  }
};

EpsilonJukebox.prototype.pause = function () {
  var self = this;

  this.mpdStatus(function (status) {
    if (status.state === 'pause') {
      console.log("Pause requested, but already paused");
    } else {
      console.log("Pause requested");
      self.mpdClient.sendCommand(mpd.cmd("pause", []));
    }
  });
};

EpsilonJukebox.prototype.unpause = function () {
  var self = this;

  this.mpdStatus(function (status) {
    if (status.state !== 'pause') {
      console.log("Unpause requested, but not paused");
    } else {
      console.log("Unpause requested");
      self.mpdClient.sendCommand(mpd.cmd("play", []));
    }
  });
};

EpsilonJukebox.prototype.hubRequest = function(method, endpoint, data, callback) {
  var requestData = new Buffer(JSON.stringify(data), 'utf8');

  var targetUrl = url.parse(
    url.resolve(this.config.hub, endpoint));

  var requestOptions = {
    hostname: targetUrl.hostname,
    port: targetUrl.port,
    path: targetUrl.path,
    method: method,
    headers: {
      "X-Host-Token": this.token
    }
  };

  if (method !== "GET") {
    requestOptions.headers["Content-Type"] = "application/json";
    requestOptions.headers["Content-Length"] = requestData.length;
  }

  var request = http.request(requestOptions, function (res) {
    callback(res, request);
  });

  if (method === "GET") {
    request.end();
  }
  else {
    request.end(requestData);
  }
};

EpsilonJukebox.prototype.data = function (subpath) {
  if (typeof subpath !== 'undefined') {
    return path.resolve(this.config.data_dir, subpath);
  }
  else {
    return path.resolve(this.config.data_dir);
  }
};

EpsilonJukebox.prototype.dataEsc = function (subpath) {
  return this.data(subpath).replace(/\\/g, "\\\\").replace(/"/g, "\\\"");
};

EpsilonJukebox.prototype.mpdPath = function () {
  try {
    // Ain't this robust? ;)
    // XXX
    var execDir = path.dirname(process.execPath);

    console.log(execDir);

    fs.readdirSync(path.resolve(execDir, "mpd"));

    return path.resolve(execDir, "mpd/bin/mpd");
  } catch (ex) {
    return "mpd";
  }
};

EpsilonJukebox.formatMPDSong = function (song) {
  return {
    id:       +song.Id,
    title:     song.Title,
    artist:    song.Artist,
    album:     song.Album,
    duration: +song.Time
  };
};

module.exports = EpsilonJukebox;
