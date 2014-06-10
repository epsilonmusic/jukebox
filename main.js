var appConfig = require('./config.js');

$(function () {
  var loginController = new LoginController({
    hub: appConfig.hub
  });

  loginController.loginView(
    function () {
      var registeredHostController = new RegisteredHostController;

      registeredHostController.selectionView();
    }
  );
});

$(document).keyup(function (e) {
  if (e.ctrlKey && e.which === 73) {
    e.preventDefault();
    require('nw.gui').Window.get().showDevTools();
  }
});
