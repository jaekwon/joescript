(function() {
  var BANNER, EventEmitter, JoeScript, SWITCHES, compileJoin, compileOptions, compilePath, compileScript, compileStdio, exec, forkNode, fs, helpers, hidden, inspect, joinTimeout, lint, loadRequires, notSources, optionParser, optparse, opts, outputPath, parseOptions, path, printLine, printWarn, removeSource, sourceCode, sources, spawn, timeLog, unwatchDir, usage, version, wait, watch, watchDir, watchers, writeJs, _ref;

  fs = require('fs');

  path = require('path');

  helpers = require('joeson/lib/helpers');

  optparse = require('joeson/lib/optparse');

  JoeScript = require('joeson/src/joescript');

  inspect = require('util').inspect;

  _ref = require('child_process'), spawn = _ref.spawn, exec = _ref.exec;

  EventEmitter = require('events').EventEmitter;

  helpers.extend(JoeScript, new EventEmitter);

  printLine = function(line) {
    return process.stdout.write(line + '\n');
  };

  printWarn = function(line) {
    return process.stderr.write(line + '\n');
  };

  hidden = function(file) {
    return /^\.|~$/.test(file);
  };

  BANNER = 'Usage: coffee [options] path/to/script.coffee -- [args]\n\nIf called without options, `coffee` will run your script.';

  SWITCHES = [['-b', '--bare', 'compile without a top-level function wrapper'], ['-c', '--compile', 'compile to JavaScript and save as .js files'], ['-d', '--debug', 'show parsing process debug output'], ['-e', '--eval', 'pass a string from the command line as input'], ['-h', '--help', 'display this help message'], ['-j', '--join [FILE]', 'concatenate the source JoeScript before compiling'], ['-l', '--lint', 'pipe the compiled JavaScript through JavaScript Lint'], ['-n', '--nodes', 'print out the parse tree that the parser produces'], ['--nodejs [ARGS]', 'pass options directly to the "node" binary'], ['-o', '--output [DIR]', 'set the output directory for compiled JavaScript'], ['-p', '--print', 'print out the compiled JavaScript'], ['-r', '--require [FILE*]', 'require a library before executing your script'], ['-s', '--stdio', 'listen for and compile scripts over stdio'], ['-v', '--version', 'display the version number'], ['-w', '--watch', 'watch scripts for changes and rerun commands']];

  opts = {};

  sources = [];

  sourceCode = [];

  notSources = {};

  watchers = {};

  optionParser = null;

  exports.run = function() {
    var literals, source, _i, _len, _results;
    parseOptions();
    if (opts.nodejs) return forkNode();
    if (opts.help) return usage();
    if (opts.version) return version();
    if (opts.require) loadRequires();
    if (opts.watch && !fs.watch) {
      return printWarn("The --watch feature depends on Node v0.6.0+. You are running " + process.version + ".");
    }
    if (opts.stdio) return compileStdio();
    if (opts.eval) return compileScript(null, sources[0]);
    literals = opts.run ? sources.splice(1) : [];
    process.argv = process.argv.slice(0, 2).concat(literals);
    process.argv[0] = 'coffee';
    process.execPath = require.main.filename;
    _results = [];
    for (_i = 0, _len = sources.length; _i < _len; _i++) {
      source = sources[_i];
      _results.push(compilePath(source, true, path.normalize(source)));
    }
    return _results;
  };

  compilePath = function(source, topLevel, base) {
    return fs.stat(source, function(err, stats) {
      if (err && err.code !== 'ENOENT') throw err;
      if ((err != null ? err.code : void 0) === 'ENOENT') {
        if (topLevel && source.slice(-7) !== '.coffee') {
          source = sources[sources.indexOf(source)] = "" + source + ".coffee";
          return compilePath(source, topLevel, base);
        }
        if (topLevel) {
          console.error("File not found: " + source);
          process.exit(1);
        }
        return;
      }
      if (stats.isDirectory()) {
        if (opts.watch) watchDir(source, base);
        return fs.readdir(source, function(err, files) {
          var file, index, _ref2, _ref3;
          if (err && err.code !== 'ENOENT') throw err;
          if ((err != null ? err.code : void 0) === 'ENOENT') return;
          index = sources.indexOf(source);
          files = files.filter(function(file) {
            return !hidden(file);
          });
          [].splice.apply(sources, [index, index - index + 1].concat(_ref2 = (function() {
            var _i, _len, _results;
            _results = [];
            for (_i = 0, _len = files.length; _i < _len; _i++) {
              file = files[_i];
              _results.push(path.join(source, file));
            }
            return _results;
          })())), _ref2;
          [].splice.apply(sourceCode, [index, index - index + 1].concat(_ref3 = files.map(function() {
            return null;
          }))), _ref3;
          return files.forEach(function(file) {
            return compilePath(path.join(source, file), false, base);
          });
        });
      } else if (topLevel || path.extname(source) === '.coffee') {
        if (opts.watch) watch(source, base);
        return fs.readFile(source, function(err, code) {
          if (err && err.code !== 'ENOENT') throw err;
          if ((err != null ? err.code : void 0) === 'ENOENT') return;
          return compileScript(source, code.toString(), base);
        });
      } else {
        notSources[source] = true;
        return removeSource(source, base);
      }
    });
  };

  compileScript = function(file, input, base) {
    var o, options, t, task;
    o = opts;
    options = compileOptions(file);
    try {
      t = task = {
        file: file,
        input: input,
        options: options
      };
      JoeScript.emit('compile', task);
      if (o.nodes || o.debug) {
        return printLine(JoeScript.parse(t.input, {
          debug: o.debug
        }).serialize());
      } else if (o.run) {
        return JoeScript.run(t.input, t.options);
      } else if (o.join && t.file !== o.join) {
        sourceCode[sources.indexOf(t.file)] = t.input;
        return compileJoin();
      } else {
        t.output = JoeScript.compile(t.input, t.options);
        JoeScript.emit('success', task);
        if (o.print) {
          return printLine(t.output.trim());
        } else if (o.compile) {
          return writeJs(t.file, t.output, base);
        } else if (o.lint) {
          return lint(t.file, t.output);
        }
      }
    } catch (err) {
      JoeScript.emit('failure', err, task);
      if (JoeScript.listeners('failure').length) return;
      if (o.watch) return printLine(err.message + '\x07');
      printWarn(err instanceof Error && err.stack || ("ERROR: " + err));
      return process.exit(1);
    }
  };

  compileStdio = function() {
    var code, stdin;
    code = '';
    stdin = process.openStdin();
    stdin.on('data', function(buffer) {
      if (buffer) return code += buffer.toString();
    });
    return stdin.on('end', function() {
      return compileScript(null, code);
    });
  };

  joinTimeout = null;

  compileJoin = function() {
    if (!opts.join) return;
    if (!sourceCode.some(function(code) {
      return code === null;
    })) {
      clearTimeout(joinTimeout);
      return joinTimeout = wait(100, function() {
        return compileScript(opts.join, sourceCode.join('\n'), opts.join);
      });
    }
  };

  loadRequires = function() {
    var realFilename, req, _i, _len, _ref2;
    realFilename = module.filename;
    module.filename = '.';
    _ref2 = opts.require;
    for (_i = 0, _len = _ref2.length; _i < _len; _i++) {
      req = _ref2[_i];
      require(req);
    }
    return module.filename = realFilename;
  };

  watch = function(source, base) {
    var compile, compileTimeout, prevStats, rewatch, watchErr, watcher;
    prevStats = null;
    compileTimeout = null;
    watchErr = function(e) {
      if (e.code === 'ENOENT') {
        if (sources.indexOf(source) === -1) return;
        try {
          rewatch();
          return compile();
        } catch (e) {
          removeSource(source, base, true);
          return compileJoin();
        }
      } else {
        throw e;
      }
    };
    compile = function() {
      clearTimeout(compileTimeout);
      return compileTimeout = wait(25, function() {
        return fs.stat(source, function(err, stats) {
          if (err) return watchErr(err);
          if (prevStats && stats.size === prevStats.size && stats.mtime.getTime() === prevStats.mtime.getTime()) {
            return rewatch();
          }
          prevStats = stats;
          return fs.readFile(source, function(err, code) {
            if (err) return watchErr(err);
            compileScript(source, code.toString(), base);
            return rewatch();
          });
        });
      });
    };
    try {
      watcher = fs.watch(source, compile);
    } catch (e) {
      watchErr(e);
    }
    return rewatch = function() {
      if (watcher != null) watcher.close();
      return watcher = fs.watch(source, compile);
    };
  };

  watchDir = function(source, base) {
    var readdirTimeout, watcher;
    readdirTimeout = null;
    try {
      return watcher = fs.watch(source, function() {
        clearTimeout(readdirTimeout);
        return readdirTimeout = wait(25, function() {
          return fs.readdir(source, function(err, files) {
            var file, _i, _len, _results;
            if (err) {
              if (err.code !== 'ENOENT') throw err;
              watcher.close();
              return unwatchDir(source, base);
            }
            _results = [];
            for (_i = 0, _len = files.length; _i < _len; _i++) {
              file = files[_i];
              if (!(!hidden(file) && !notSources[file])) continue;
              file = path.join(source, file);
              if (sources.some(function(s) {
                return s.indexOf(file) >= 0;
              })) {
                continue;
              }
              sources.push(file);
              sourceCode.push(null);
              _results.push(compilePath(file, false, base));
            }
            return _results;
          });
        });
      });
    } catch (e) {
      if (e.code !== 'ENOENT') throw e;
    }
  };

  unwatchDir = function(source, base) {
    var file, prevSources, toRemove, _i, _len;
    prevSources = sources.slice(0);
    toRemove = (function() {
      var _i, _len, _results;
      _results = [];
      for (_i = 0, _len = sources.length; _i < _len; _i++) {
        file = sources[_i];
        if (file.indexOf(source) >= 0) _results.push(file);
      }
      return _results;
    })();
    for (_i = 0, _len = toRemove.length; _i < _len; _i++) {
      file = toRemove[_i];
      removeSource(file, base, true);
    }
    if (!sources.some(function(s, i) {
      return prevSources[i] !== s;
    })) {
      return;
    }
    return compileJoin();
  };

  removeSource = function(source, base, removeJs) {
    var index, jsPath;
    index = sources.indexOf(source);
    sources.splice(index, 1);
    sourceCode.splice(index, 1);
    if (removeJs && !opts.join) {
      jsPath = outputPath(source, base);
      return path.exists(jsPath, function(exists) {
        if (exists) {
          return fs.unlink(jsPath, function(err) {
            if (err && err.code !== 'ENOENT') throw err;
            return timeLog("removed " + source);
          });
        }
      });
    }
  };

  outputPath = function(source, base) {
    var baseDir, dir, filename, srcDir;
    filename = path.basename(source, path.extname(source)) + '.js';
    srcDir = path.dirname(source);
    baseDir = base === '.' ? srcDir : srcDir.substring(base.length);
    dir = opts.output ? path.join(opts.output, baseDir) : srcDir;
    return path.join(dir, filename);
  };

  writeJs = function(source, js, base) {
    var compile, jsDir, jsPath;
    jsPath = outputPath(source, base);
    jsDir = path.dirname(jsPath);
    compile = function() {
      if (js.length <= 0) js = ' ';
      return fs.writeFile(jsPath, js, function(err) {
        if (err) {
          return printLine(err.message);
        } else if (opts.compile && opts.watch) {
          return timeLog("compiled " + source);
        }
      });
    };
    return path.exists(jsDir, function(exists) {
      if (exists) {
        return compile();
      } else {
        return exec("mkdir -p " + jsDir, compile);
      }
    });
  };

  wait = function(milliseconds, func) {
    return setTimeout(func, milliseconds);
  };

  timeLog = function(message) {
    return console.log("" + ((new Date).toLocaleTimeString()) + " - " + message);
  };

  lint = function(file, js) {
    var conf, jsl, printIt;
    printIt = function(buffer) {
      return printLine(file + ':\t' + buffer.toString().trim());
    };
    conf = __dirname + '/../../extras/jsl.conf';
    jsl = spawn('jsl', ['-nologo', '-stdin', '-conf', conf]);
    jsl.stdout.on('data', printIt);
    jsl.stderr.on('data', printIt);
    jsl.stdin.write(js);
    return jsl.stdin.end();
  };

  parseOptions = function() {
    var i, o, source, _i, _len;
    optionParser = new optparse.OptionParser(SWITCHES, BANNER);
    o = opts = optionParser.parse(process.argv.slice(2));
    o.compile || (o.compile = !!o.output);
    o.run = !(o.compile || o.print || o.lint);
    o.print = !!(o.print || (o.eval || o.stdio && o.compile));
    sources = o.arguments;
    for (i = _i = 0, _len = sources.length; _i < _len; i = ++_i) {
      source = sources[i];
      sourceCode[i] = null;
    }
  };

  compileOptions = function(filename) {
    return {
      filename: filename,
      bare: opts.bare,
      header: opts.compile
    };
  };

  forkNode = function() {
    var args, nodeArgs;
    nodeArgs = opts.nodejs.split(/\s+/);
    args = process.argv.slice(1);
    args.splice(args.indexOf('--nodejs'), 2);
    return spawn(process.execPath, nodeArgs.concat(args), {
      cwd: process.cwd(),
      env: process.env,
      customFds: [0, 1, 2]
    });
  };

  usage = function() {
    return printLine((new optparse.OptionParser(SWITCHES, BANNER)).help());
  };

  version = function() {
    return printLine("JoeScript version " + JoeScript.VERSION);
  };

}).call(this);