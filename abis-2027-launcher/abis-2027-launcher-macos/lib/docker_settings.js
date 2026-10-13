// docker_settings.js - Read or change keys in Docker Desktop's settings-store.json.
//
//   osascript -l JavaScript docker_settings.js get <file> <Key>...
//       prints "Key=value" per key ("Key=" if the key is absent)
//   osascript -l JavaScript docker_settings.js set <file> <Key=value>...
//       value: an integer, true or false; "Key=" removes the key
//
// JavaScript for Automation (osascript -l JavaScript) ships with every macOS,
// so editing the JSON needs neither jq nor python3 (which is not there without
// the Command Line Tools). Every other key of the file is left as it was.
// The same file runs under Node.js, which is how it is tested off a Mac.
//
// Docker Desktop must not be running while the file is written: it keeps its
// settings in memory and writes them back on quit.

function parseValue(text) {
    if (text === 'true') return true;
    if (text === 'false') return false;
    if (/^-?\d+$/.test(text)) return parseInt(text, 10);
    throw new Error('unsupported value: ' + text);
}

function getKeys(json, keys) {
    var settings = JSON.parse(json);
    return keys.map(function (key) {
        var v = Object.prototype.hasOwnProperty.call(settings, key) ? settings[key] : '';
        return key + '=' + v;
    }).join('\n');
}

function setKeys(json, assignments) {
    var settings = JSON.parse(json);
    assignments.forEach(function (a) {
        var i = a.indexOf('=');
        if (i <= 0) throw new Error('expected Key=value: ' + a);
        var key = a.slice(0, i), value = a.slice(i + 1);
        if (value === '') {
            delete settings[key];
        } else {
            settings[key] = parseValue(value);
        }
    });
    // Docker Desktop writes the file indented by two spaces.
    return JSON.stringify(settings, null, 2) + '\n';
}

function main(argv, readFile, writeFile) {
    var cmd = argv[0], file = argv[1], rest = argv.slice(2);
    if (cmd === 'get') return getKeys(readFile(file), rest);
    if (cmd === 'set') { writeFile(file, setKeys(readFile(file), rest)); return ''; }
    throw new Error('usage: get|set <file> ...');
}

// osascript entry point: osascript calls the top-level run() and prints its
// return value. Never called under Node.js.
function run(argv) {
    ObjC.import('Foundation');
    return main(argv,
        function (path) {
            var s = $.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null);
            if (s.isNil()) throw new Error('cannot read ' + path);
            return s.js;
        },
        function (path, text) {
            // Atomic: a half-written settings file would keep Docker Desktop from starting.
            if (!$(text).writeToFileAtomicallyEncodingError(path, true, $.NSUTF8StringEncoding, null)) {
                throw new Error('cannot write ' + path);
            }
        });
}

if (typeof ObjC === 'undefined' && typeof module !== 'undefined') {
    // Node.js, for tests.
    var fs = require('fs');
    module.exports = { getKeys: getKeys, setKeys: setKeys };
    if (require.main === module) {
        var out = main(process.argv.slice(2),
            function (p) { return fs.readFileSync(p, 'utf8'); },
            function (p, t) { fs.writeFileSync(p + '.tmp', t); fs.renameSync(p + '.tmp', p); });
        if (out) console.log(out);
    }
}
