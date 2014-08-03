#!/usr/bin/env node

if (process.argv.length >= 7) {
  var rcedit = require('rcedit');

  rcedit(process.argv[2], {
    "version-string":  process.argv[3],
    "file-version":    process.argv[4],
    "product-version": process.argv[5],
    "icon":            process.argv[6]
  }, function () {
    process.exit();
  });
} else {
  console.log("Usage: " + process.argv[1] + " <exe> <version-string> <file-version> <product-version> <icon>");
}
