// Imports
var url  = require("url")
  , fs   = require("fs")
  , http = require("http")
  ;

var DEFAULT_CONFIG = {
  library: "~/Music/Epsilon Library",
  data_dir: "data",
  hub: "http://epsilon.ideahack.devyn.me"
};

function EpsilonHost(config) {
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

EpsilonHost.prototype.start = function () {
  try {
    var dataDirContents = fs.readdirSync(this.data());
  } catch (e) {
    this.initializeDataDir();
  }
};

EpsilonHost.prototype.initializeDataDir = function () {
  console.log("Initializing data directory");

  fs.mkdirSync(this.data());
  fs.mkdirSync(this.data("mpd"));
  fs.mkdirSync(this.data("mpd/playlists"));
  fs.writeFileSync(this.data("mpd/database"), "");

  // Write MPD config

  var mpdConf = fs.openSync(this.data("mpd.conf"), "w");

  fs.writeSync(mpdConf,
      ['music_directory    "' + this.config.library + '"',
       'playlist_directory "' + this.data("mpd/playlists") + '"',
       'db_file            "' + this.data("mpd/database") + '"',
       'pid_file           "' + this.data("mpd/pid") + '"',
       'state_file         "' + this.data("mpd/state") + '"',
       'sticker_file       "' + this.data("mpd/sticker.sql") + '"',
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

EpsilonHost.prototype.uploadQueue = function () {
  var requestData = JSON.stringify({
    queue: [] // TODO
  });

  var targetUrl = url.parse(url.resolve(this.config.hub, "host/" + this.id));

  var request = http.request({
    hostname: targetUrl.hostname,
    port: targetUrl.port,
    path: targetUrl.path,
    method: "PUT",
    headers: {
      "Content-Type": "application/json",
      "X-Host-Token": this.token,
      "Content-Length": requestData.length
    }
  }, function (res) {
    console.log("Queue uploaded, response = ", res.statusCode);
  });

  request.end(requestData);
};

EpsilonHost.prototype.data = function (subpath) {
  if (typeof subpath !== 'undefined') {
    return path.join(this.config.data_dir, subpath);
  }
  else {
    return ""+this.config.data_dir;
  }
};

module.exports = EpsilonHost;
