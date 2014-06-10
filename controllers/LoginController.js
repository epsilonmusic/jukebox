var url = require("url");

function LoginController(config) {
  this.hub = config.hub;
}

LoginController.prototype.loginView = function (success) {
  var self = this;

  $("body").load("views/login.html", function () {

    $("#login").submit(function (e) {
      e.preventDefault();

      self.login(
        $("#login input[name='email']").val(),
        $("#login input[name='password']").val(),
        success
      );
    });

  });
};

LoginController.prototype.login = function (email, password, success) {
  $.ajax({
    type: "POST",
    url: url.resolve(this.hub, "session/authenticate"),
    data: {email: email, password: password},

    headers: {
      "Accept": "application/json; charset=utf-8"
    },

    success: success,

    error: function (xhr, textStatus, errorThrown) {
      switch (textStatus) {
        case "timeout":
          $("#login .error").text("Request timed out.");
          break;
        case "error":
          if (xhr.status === 403) {
            $("#login .error").text(JSON.parse(xhr.responseText).error);
          }
          else {
            $("#login .error").text("HTTP error: " + errorThrown);
          }
          break;
        case "abort":
          $("#login .error").text("Request aborted.");
          break;
        case "parsererror":
          $("#login .error").text("Request failed to parse.");
          break;
        default:
          $("#login .error").text("Unknown error.");
      }
    }
  });
};
