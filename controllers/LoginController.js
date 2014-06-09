function LoginController() {
}

LoginController.prototype.loginView = function () {
  $("body").load("views/login.html", function () {

    $("#login").submit(function (e) {
      e.preventDefault();
      $("body").append("Logging in<br>");
    });

  });
};
