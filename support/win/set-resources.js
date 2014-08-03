#!/usr/bin/env node

if (process.argv.length >= 4) {
  var rcedit = require('rcedit');

  rcedit(process.argv[2], {
    "icon": process.argv[3]
  }, function (error) {
    if (error) {
      console.log(error);
      process.exit(1);
    } else {
      process.exit();
    }
  });
} else {
  console.log("Usage: " + process.argv[1] + " <exe> <icon>");
  process.exit(1);
}
