function run_matlab(options)
%RUN_MATLAB Run the parity scenarios against the MATLAB client.
%   Executes every scenario in scenarios.json against the mock server and
%   writes out/matlab.json for compare.py.
%
%   run_matlab                                  spawn the mock server, run all
%   run_matlab(only="gtt.")                     scenario ids containing the text
%   run_matlab(mock_url="http://127.0.0.1:8799") use a running mock server
%   run_matlab(python="C:\Python314\python.exe") interpreter for the helpers
%   run_matlab(lib="D:\src\openalgo-matlab-library") library root
%                                               (default: two folders up)
%
%   From a shell:
%     matlab -batch "cd('<this folder>'); run_matlab"
%
%   scenarios.matlab.json (the type-tagged scenario file) is regenerated with
%   prepare_matlab.py whenever scenarios.json or matlab_calling.json is newer.

arguments
    options.only (1,1) string = ""
    options.out (1,1) string = ""
    options.python (1,1) string = "python"
    options.mock_url (1,1) string = ""
    options.lib (1,1) string = ""
end

here = fileparts(mfilename('fullpath'));
outDir = fullfile(here, 'out');
if ~isfolder(outDir), mkdir(outDir); end
outFile = options.out;
if strlength(outFile) == 0, outFile = string(fullfile(outDir, 'matlab.json')); end

% ---- type-tagged scenarios
tagged = fullfile(here, 'scenarios.matlab.json');
if needsPrepare(here, tagged)
    [st, msg] = system(sprintf('"%s" "%s"', options.python, fullfile(here, 'prepare_matlab.py')));
    if st ~= 0, error('parity:prepare', 'prepare_matlab.py failed: %s', msg); end
end
doc = jsondecode(readUtf8(tagged));
scenarios = doc.scenarios;

% ---- library on the path
libRoot = options.lib;
if strlength(libRoot) == 0, libRoot = string(fullfile(here, '..', '..')); end
libHow = addLibrary(char(libRoot));

% ---- mock server
mock = startMock(here, outDir, options.python, options.mock_url);
cleanup = onCleanup(@() stopMock(mock)); %#ok<NASGU>

warnState = warning('off', 'backtrace');
restoreWarn = onCleanup(@() warning(warnState)); %#ok<NASGU>

entries = strings(0, 1);
t0 = tic;
n = numel(scenarios);
for i = 1:n
    if iscell(scenarios), sc = scenarios{i}; else, sc = scenarios(i); end
    if strlength(options.only) > 0 && ~contains(sc.id, options.only), continue; end
    ts = tic;
    httpPost([mock.base '/__control__/scenario'], sc.control_json);
    [outcome, warns, raised] = runScenario(sc, doc.api_key, mock);
    reqs = httpGet([mock.base '/__control__/requests?bare=1&id=' char(sc.id)]);
    if isempty(strtrim(reqs)), reqs = '[]'; end
    entries(end + 1, 1) = jsonencode(string(sc.id)) + ":{" + ...
        """requests"":" + string(reqs) + "," + ...
        """outcome"":" + outcome + "," + ...
        """warnings"":" + encStrings(warns) + "," + ...
        """seconds"":" + num(toc(ts)) + "}"; %#ok<AGROW>
    if raised, state = 'raised'; else, state = 'ok'; end
    fprintf('%-55s %s\n', sc.id, state);
end

meta = "{""mock_base"":" + jsonencode(string(mock.base)) + ...
    ",""closed_base"":" + jsonencode(string(mock.closed)) + ...
    ",""sdk_version"":" + jsonencode(string(libHow)) + ...
    ",""runtime"":" + jsonencode("MATLAB " + string(version)) + ...
    ",""generated"":" + jsonencode(string(datetime('now', 'Format', 'yyyy-MM-dd''T''HH:mm:ss'))) + ...
    ",""seconds"":" + num(toc(t0)) + "}";
if isempty(entries), body = ""; else, body = strjoin(entries, ","); end
txt = "{""lang"":""matlab"",""meta"":" + meta + ",""results"":{" + body + "}}";
fid = fopen(outFile, 'w');
fwrite(fid, unicode2native(char(txt), 'UTF-8'));
fclose(fid);
fprintf('wrote %s (%d scenarios, %.1fs)\n', outFile, numel(entries), toc(t0));
end

% =====================================================================
function [outcome, warns, raised] = runScenario(sc, apiKey, mock)
warns = strings(0, 1);
raised = false;
value = [];
try
    captured = evalc('value = invokeScenario(sc, apiKey, mock);');
    % Interactive sessions print "Warning: msg", -batch prints "[Warning: msg]"
    % with backspace characters as stderr markup around the brackets.
    captured = strrep(captured, char(8), '');
    tok = regexp(captured, '^\[?Warning: ([^\n]*?)\]?[ \t]*$', 'tokens', 'lineanchors');
    for k = 1:numel(tok), warns(end + 1, 1) = string(strtrim(tok{k}{1})); end %#ok<AGROW>
    outcome = "{""raised"":false,""value"":" + enc(value) + "}";
catch ME
    raised = true;
    outcome = "{""raised"":true,""error_class"":" + jsonencode(string(ME.identifier)) + ...
        ",""message"":" + jsonencode(string(ME.message)) + "}";
end
end

function value = invokeScenario(sc, apiKey, mock)
if strcmp(sc.target, 'strategy')
    ctor = fromTagged(sc.strategy);
    ctor = subHosts(ctor, mock);
    pos = {};
    if isfield(ctor, 'host_url')
        pos{end + 1} = ctor.host_url;
        ctor = rmfield(ctor, 'host_url');
    end
    if isfield(ctor, 'webhook_id')
        pos{end + 1} = ctor.webhook_id;
        ctor = rmfield(ctor, 'webhook_id');
    end
    nv = structToNameValue(ctor);
    obj = openalgo.Strategy(pos{:}, nv{:});
else
    copts = fromTagged(sc.client);
    if ~isfield(copts, 'host'), copts.host = "$MOCK"; end
    copts = subHosts(copts, mock);
    nv = structToNameValue(copts);
    obj = openalgo.api("api_key", string(apiKey), nv{:});
end
method = char(sc.method);
if sc.property
    value = obj.(method);
else
    args = fromTagged(sc.args);
    pos = {};
    names = sc.positional;
    for k = 1:numel(names)
        if iscell(names), nm = names{k}.name; else, nm = names(k).name; end
        if isfield(args, nm)
            pos{end + 1} = args.(nm); %#ok<AGROW>
            args = rmfield(args, nm);
        end
    end
    nv = structToNameValue(args);
    if isempty(pos) && isempty(nv)
        value = obj.(method)();
    else
        value = obj.(method)(pos{:}, nv{:});
    end
end
if isobject(obj) && ismethod(obj, 'close')
    try, obj.close(); catch, end
end
end

function nv = structToNameValue(s)
nv = {};
if isempty(s), return; end
f = fieldnames(s);
for k = 1:numel(f)
    nv(end + 1:end + 2) = {string(f{k}), s.(f{k})}; %#ok<AGROW>
end
end

function s = subHosts(s, mock)
f = fieldnames(s);
for k = 1:numel(f)
    v = s.(f{k});
    if isstring(v) || ischar(v)
        v = replace(string(v), "$MOCK", mock.base);
        v = replace(v, "$CLOSED", mock.closed);
        s.(f{k}) = v;
    end
end
end

% ---------------------------------------------------- tagged argument decoding
% str -> string scalar, num -> double, bool -> logical, null -> [],
% obj -> struct, array -> string array / numeric row / logical row / cell
% array (e.g. cell array of structs), cell ({"$list": ...}) -> cell array.
function v = fromTagged(x)
switch x.t
    case 'str'
        v = string(x.v);
    case 'num'
        v = double(x.v);
    case 'bool'
        v = logical(x.v);
    case 'null'
        v = [];
    case 'obj'
        v = struct();
        p = x.v;
        for k = 1:numel(p)
            if iscell(p), e = p{k}; else, e = p(k); end
            name = e.k;
            if ~isvarname(name), name = matlab.lang.makeValidName(name); end
            v.(name) = fromTagged(e.v);
        end
    case {'array', 'cell'}
        items = x.v;
        vals = cell(1, numel(items));
        for k = 1:numel(items)
            if iscell(items), e = items{k}; else, e = items(k); end
            vals{k} = fromTagged(e);
        end
        if strcmp(x.t, 'cell') || isempty(vals)
            v = vals;
        elseif all(cellfun(@(c) isstring(c) && isscalar(c), vals))
            v = [vals{:}];
        elseif all(cellfun(@(c) islogical(c) && isscalar(c), vals))
            v = [vals{:}];
        elseif all(cellfun(@(c) isnumeric(c) && isscalar(c), vals))
            v = [vals{:}];
        else
            v = vals;
        end
    otherwise
        error('parity:tag', 'unknown tag %s', x.t);
end
end

% ------------------------------------------------------ result normalization
function s = enc(v)
if istimetable(v)
    s = encTable(timetable2table(v));
elseif istable(v)
    s = encTable(v);
elseif isstruct(v)
    if isscalar(v)
        f = fieldnames(v);
        parts = strings(1, numel(f));
        for k = 1:numel(f)
            parts(k) = jsonencode(string(f{k})) + ":" + enc(v.(f{k}));
        end
        s = "{" + joinParts(parts) + "}";
    else
        parts = strings(1, numel(v));
        for k = 1:numel(v), parts(k) = enc(v(k)); end
        s = "[" + joinParts(parts) + "]";
    end
elseif iscell(v)
    parts = strings(1, numel(v));
    for k = 1:numel(v), parts(k) = enc(v{k}); end
    s = "[" + joinParts(parts) + "]";
elseif isa(v, 'dictionary')
    if ~isConfigured(v) || numEntries(v) == 0
        s = "{}";
    else
        ks = keys(v); vs = values(v);
        parts = strings(1, numel(ks));
        for k = 1:numel(ks)
            if iscell(vs), e = vs{k}; else, e = vs(k); end
            parts(k) = jsonencode(string(ks(k))) + ":" + enc(e);
        end
        s = "{" + joinParts(parts) + "}";
    end
elseif isa(v, 'containers.Map')
    ks = keys(v); vs = values(v);
    parts = strings(1, numel(ks));
    for k = 1:numel(ks), parts(k) = jsonencode(string(ks{k})) + ":" + enc(vs{k}); end
    s = "{" + joinParts(parts) + "}";
elseif isstring(v)
    if isscalar(v)
        if ismissing(v), s = "null"; else, s = jsonencode(v); end
    else
        parts = strings(1, numel(v));
        for k = 1:numel(v), parts(k) = enc(v(k)); end
        s = "[" + joinParts(parts) + "]";
    end
elseif ischar(v)
    if isempty(v) || isrow(v)
        s = jsonencode(string(v));
    else
        s = enc(cellstr(v));
    end
elseif isdatetime(v)
    if isscalar(v)
        s = isoTime(v);
    else
        parts = strings(1, numel(v));
        for k = 1:numel(v), parts(k) = isoTime(v(k)); end
        s = "[" + joinParts(parts) + "]";
    end
elseif islogical(v)
    if isscalar(v)
        if v, s = "true"; else, s = "false"; end
    else
        parts = strings(1, numel(v));
        for k = 1:numel(v), parts(k) = enc(v(k)); end
        s = "[" + joinParts(parts) + "]";
    end
elseif isnumeric(v)
    if isscalar(v)
        s = num(v);
    else
        parts = strings(1, numel(v));
        for k = 1:numel(v), parts(k) = num(v(k)); end
        s = "[" + joinParts(parts) + "]";
    end
elseif iscategorical(v) || isduration(v)
    s = enc(string(v));
else
    s = jsonencode(string(['<' class(v) '>']));
end
end

function s = joinParts(parts)
if isempty(parts), s = ""; else, s = strjoin(parts, ","); end
end

function s = num(x)
x = double(x);
if isnan(x) || isinf(x)
    s = "null";
elseif x == fix(x) && abs(x) < 1e15
    s = string(sprintf('%d', x));
else
    s = string(sprintf('%.17g', x));
end
end

function s = isoTime(d)
if isnat(d)
    s = "null";
elseif isempty(d.TimeZone)
    s = jsonencode(string(d, "yyyy-MM-dd'T'HH:mm:ss"));
else
    s = jsonencode(string(d, "yyyy-MM-dd'T'HH:mm:ssxxx"));
end
end

function s = encTable(t)
cols = string(t.Properties.VariableNames);
rn = t.Properties.RowNames;
hasRn = ~isempty(rn);
colList = cols;
if hasRn, colList = ["__rownames__", cols]; end
tzParts = strings(1, 0);
for c = cols
    col = t.(c);
    if isdatetime(col)
        if isempty(col.TimeZone), z = "null"; else, z = jsonencode(string(col.TimeZone)); end
        tzParts(end + 1) = jsonencode(c) + ":" + z; %#ok<AGROW>
    end
end
h = height(t);
recs = strings(1, h);
for i = 1:h
    parts = strings(1, 0);
    if hasRn, parts(end + 1) = """__rownames__"":" + jsonencode(string(rn{i})); end %#ok<AGROW>
    for c = cols
        col = t.(c);
        if iscell(col), val = col{i}; else, val = col(i, :); end
        parts(end + 1) = jsonencode(c) + ":" + enc(val); %#ok<AGROW>
    end
    recs(i) = "{" + joinParts(parts) + "}";
end
colEnc = strings(1, numel(colList));
for k = 1:numel(colList), colEnc(k) = jsonencode(colList(k)); end
s = "{""__type__"":""table"",""columns"":[" + joinParts(colEnc) + "],""nrow"":" + num(h) + ...
    ",""tz"":{" + joinParts(tzParts) + "},""records"":[" + joinParts(recs) + "]}";
end

function s = encStrings(v)
parts = strings(1, numel(v));
for k = 1:numel(v), parts(k) = jsonencode(v(k)); end
s = "[" + joinParts(parts) + "]";
end

% ------------------------------------------------------------- environment
function tf = needsPrepare(here, tagged)
if ~isfile(tagged), tf = true; return; end
t = dir(tagged);
src = [dir(fullfile(here, 'scenarios.json')); dir(fullfile(here, 'matlab_calling.json'))];
tf = any([src.datenum] > t.datenum);
end

function how = addLibrary(root)
hits = dir(fullfile(root, '**', '+openalgo'));
folders = unique({hits.folder});
folders = folders(~contains(folders, [filesep 'tools' filesep]));
pkg = '';
for k = 1:numel(folders)
    [~, leaf] = fileparts(folders{k});
    if strcmp(leaf, '+openalgo'), pkg = folders{k}; break; end
end
if isempty(pkg), error('parity:lib', 'no +openalgo package folder under %s', root); end
parent = fileparts(pkg);
addpath(parent);
how = ['path ' parent];
end

function txt = readUtf8(path)
fid = fopen(path, 'r');
bytes = fread(fid, Inf, '*uint8')';
fclose(fid);
txt = native2unicode(bytes, 'UTF-8');
end

function mock = startMock(here, outDir, python, mockUrl)
mock.proc = [];
mock.spawned = strlength(mockUrl) == 0;
if ~mock.spawned
    mock.base = regexprep(char(mockUrl), '/+$', '');
else
    pf = fullfile(outDir, 'mock_port_matlab.txt');
    if isfile(pf), delete(pf); end
    args = sprintf('"%s" --port 0 --port-file "%s" --log "%s"', fullfile(here, 'mock_server.py'), ...
        pf, fullfile(outDir, 'requests_matlab.jsonl'));
    if ispc
        % A .NET process does not inherit MATLAB's output pipe, so it
        % cannot block this session the way "start /B" under system() can.
        psi = System.Diagnostics.ProcessStartInfo(char(python), args);
        psi.UseShellExecute = false;
        psi.CreateNoWindow = true;
        mock.proc = System.Diagnostics.Process.Start(psi);
    else
        system(sprintf('"%s" %s > "%s" 2>&1 &', python, args, fullfile(outDir, 'mock_server_matlab.log')));
    end
    t0 = tic;
    while ~isfile(pf)
        if toc(t0) > 20, error('parity:mock', 'mock server did not start'); end
        pause(0.05);
    end
    pause(0.05);
    mock.base = sprintf('http://127.0.0.1:%s', strtrim(fileread(pf)));
end
info = jsondecode(httpGet([mock.base '/__control__/ping']));
mock.closed = sprintf('http://127.0.0.1:%d', info.closed_port);
end

function stopMock(mock)
if mock.spawned
    try, httpPost([mock.base '/__control__/shutdown'], '{}'); catch, end
end
end

function txt = httpGet(url)
txt = httpSend(matlab.net.http.RequestMethod.GET, url, []);
end

function txt = httpPost(url, body)
txt = httpSend(matlab.net.http.RequestMethod.POST, url, body);
end

function txt = httpSend(method, url, body)
req = matlab.net.http.RequestMessage(method);
if ~isempty(body)
    req.Header = matlab.net.http.field.ContentTypeField('application/json');
    req.Body = matlab.net.http.MessageBody();
    req.Body.Payload = unicode2native(char(body), 'UTF-8');
end
opts = matlab.net.http.HTTPOptions('ConvertResponse', false, 'ConnectTimeout', 30);
resp = req.send(matlab.net.URI(url), opts);
d = resp.Body.Data;
if isempty(d)
    txt = '';
elseif isa(d, 'uint8')
    txt = native2unicode(d(:)', 'UTF-8');
else
    txt = char(d);
end
if resp.StatusCode ~= matlab.net.http.StatusCode.OK
    error('parity:control', 'control call %s failed: %d', url, double(resp.StatusCode));
end
end
