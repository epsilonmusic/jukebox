var appConfig = require('./config.js');

$(function () {
  var hostController = new HostController(appConfig);

  hostController.configureAndThen(function () {
    hostController.unsharedView();
  });
});

// Ctrl-I = DevTools

$(document).keyup(function (e) {
  if (e.ctrlKey && e.which === 73) {
    e.preventDefault();
    require('nw.gui').Window.get().showDevTools();
  }
});

// Prevent default action for file drag-and-drop

window.addEventListener("dragover", function (e) {
  e.preventDefault();
  return false;
});

window.addEventListener("drop", function (e) {
  e.preventDefault();
  return false;
});
