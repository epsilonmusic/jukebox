var url            = require("url")
  , fs             = require("fs")
  , gui            = require("nw.gui")
  , path           = require("path")
  , EpsilonJukebox = require("./lib/epsilon-jukebox.js")
  ;

function HostController(config) {
  this.config = config;
}

HostController.prototype.configureAndThen = function (callback) {
  var self = this;

  if (typeof localStorage["id"]    === 'undefined' ||
      typeof localStorage["token"] === 'undefined') {

    var loginController = new LoginController(this.config);

    loginController.loginView(function () {
      $.ajax({
        type: "POST",
        url: url.resolve(self.config.hub, "session/user/registered_hosts"),
        dataType: 'json',

        success: function (registeredHost) {
          localStorage["id"]    = registeredHost.id;
          localStorage["token"] = registeredHost.token;
          callback();
        }
      });
    });
  } else {
    callback();
  }
};

HostController.prototype.unsharedView = function () {
  var self = this;

  // TODO: make UX better with CSS classes
  function setState(name, message) {
    switch (name) {
      case "default":
        $("#dragbox .message").text("drop music folder here");
        $("#share_link").addClass("disabled");
        break;
      case "error":
        $("#dragbox .message").text(message);
        $("#share_link").addClass("disabled");
        break;
      case "ready":
        $("#dragbox .message").text("ready");
        $("#share_link").removeClass("disabled");
        $("#dragbox").addClass("ready");
        break;
    }
  }

  $("#yield").load("views/host_unshared.html", function () {
    if (typeof localStorage["library"] !== 'undefined') {
      setState('ready');
    }
    else {
      setState('default');
    }

    $("#dragbox").on("dragenter", function () {
      $(this).addClass('drag_hover');
    });

    $("#dragbox").on("dragleave dragend drop", function () {
      $(this).removeClass('drag_hover');
    });

    $("#dragbox")[0].addEventListener("drop", function (e) {
      switch (e.dataTransfer.files.length) {
        case 0:
          setState('error', "please drop a folder");
          break;
        case 1:
          var path = e.dataTransfer.files[0].path;
          fs.readdir(path, function (err, files) {
            if (err) {
              setState('error', "please drop a folder");
            }
            else if (files.length < 1) {
              setState('error', "please drop a non-empty folder");
            }
            else {
              setState('ready');
              localStorage["library"] = path;
            }
          });
          break;
        default:
          $("#dragbox .message").text("please drop only one folder");
      }
    });

    $("#share_link").click(function (e) {
      e.preventDefault();

      if (typeof localStorage["library"] !== 'undefined') {
        fs.readdir(localStorage["library"], function (err, files) {
          if (err || files.length < 1) {
            setState('default');
            delete localStorage["library"];
            return;
          }

          self.host = new EpsilonJukebox({
            id:       localStorage["id"],
            token:    localStorage["token"],
            library:  localStorage["library"],
            hub:      self.config.hub,
            data_dir: path.resolve(gui.App.dataPath, "Epsilon Host Data")
          });

          self.host.start(function () {
            self.sharedView();
          });
        });
      }
    });
  });
};

HostController.prototype.sharedView = function () {
  var self = this;

  $("#yield").load("views/host_shared.html", function () {
    $("#host_id").text(localStorage["id"]);

    var playlistUrl =
      url.resolve(self.config.hub, "host/" + localStorage["id"]);

    $("#playlist_link").attr("href", playlistUrl);

    $("#playlist_link").click(function (e) {
      e.preventDefault();

      require('nw.gui').Shell.openExternal(playlistUrl);
    });

    $("#unshare_link").click(function (e) {
      e.preventDefault();

      self.host.stop(function () {
        delete self.host;
        self.unsharedView();
      });
    });
  });
};
