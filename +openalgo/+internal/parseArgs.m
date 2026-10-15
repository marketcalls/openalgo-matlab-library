function [p, kw] = parseArgs(fname, args, params, required, nPositional, allowKwargs)
%PARSEARGS Parse Python-style positional and name=value arguments.
%   [P, KW] = openalgo.internal.parseArgs(FNAME, ARGS, PARAMS, REQUIRED,
%   NPOSITIONAL, ALLOWKWARGS) parses the cell array ARGS (usually varargin)
%   against the declared parameters of the Python method FNAME.
%
%   PARAMS is an N-by-2 cell array {name, default; ...} in Python order.
%   A default of [] stands for Python None. REQUIRED is a cell array of the
%   names that must be supplied. The first NPOSITIONAL names may also be
%   given as leading positional values; every other parameter is
%   name=value only (Python keyword-only). Names are exact and
%   case-sensitive.
%
%   When ALLOWKWARGS is true, name=value pairs whose name is not declared
%   are returned in KW, a K-by-2 cell array {name, value; ...} in the order
%   given (Python **kwargs). When it is false they raise
%   openalgo:unexpectedArgument.
%
%   P is a struct with one field per declared parameter, holding the given
%   value or the default.
%
%   Errors:
%     openalgo:missingArgument    a required parameter was not supplied
%     openalgo:unexpectedArgument an undeclared name on a method without **kwargs
%     openalgo:duplicateArgument  the same parameter was supplied twice
%     openalgo:invalidArguments   the argument list cannot be parsed

if isempty(params)
    names = {};
    p = struct();
else
    names = params(:, 1)';
    p = cell2struct(params(:, 2), params(:, 1), 1);
end
given = false(1, numel(names));
kw = cell(0, 2);

n = numel(args);
maxK = min(nPositional, n);

% Choose the smallest number of leading positional values that leaves a
% well formed list of name=value pairs. A declared parameter name that
% starts a well formed name=value tail is a name, never a positional
% value: otherwise a misspelled name later in the list, as in
% api(api_key="k", hots="x"), would shift every pair into the positional
% slots instead of raising the error Python raises.
k = -1;
for cand = 0:maxK
    if pairsValid(args(cand+1:end), names, allowKwargs, true) && ...
            ~swallowsName(args, cand, names)
        k = cand;
        break
    end
end

if k < 0
    diagnose(fname, args, names, nPositional, maxK, allowKwargs);
end

for i = 1:k
    p.(names{i}) = args{i};
    given(i) = true;
end

for i = k+1:2:n
    nm = char(args{i});
    value = args{i+1};
    idx = find(strcmp(nm, names), 1);
    if ~isempty(idx)
        if given(idx)
            error('openalgo:duplicateArgument', ...
                '%s() got multiple values for argument ''%s''', fname, nm);
        end
        p.(nm) = value;
        given(idx) = true;
    else
        if any(strcmp(nm, kw(:, 1)))
            error('openalgo:duplicateArgument', ...
                '%s() got multiple values for argument ''%s''', fname, nm);
        end
        kw(end+1, :) = {nm, value}; %#ok<AGROW>
    end
end

% Required parameters: Python reports missing positional ones first.
missPos = {};
missKw = {};
for r = 1:numel(required)
    idx = find(strcmp(required{r}, names), 1);
    if isempty(idx) || given(idx)
        continue
    end
    if idx <= nPositional
        missPos{end+1} = names{idx}; %#ok<AGROW>
    else
        missKw{end+1} = names{idx}; %#ok<AGROW>
    end
end
if ~isempty(missPos)
    error('openalgo:missingArgument', '%s() missing %d required positional argument%s: %s', ...
        fname, numel(missPos), plural(numel(missPos)), joinNames(missPos));
end
if ~isempty(missKw)
    error('openalgo:missingArgument', '%s() missing %d required keyword-only argument%s: %s', ...
        fname, numel(missKw), plural(numel(missKw)), joinNames(missKw));
end
end

function tf = pairsValid(rest, names, allowKwargs, strict)
% TRUE when REST is a list of name=value pairs. In strict mode an undeclared
% name is only accepted when the method takes **kwargs.
tf = false;
if mod(numel(rest), 2) ~= 0
    return
end
for i = 1:2:numel(rest)
    t = rest{i};
    if ~isNameToken(t)
        return
    end
    if strict && ~allowKwargs && ~any(strcmp(char(t), names))
        return
    end
end
tf = true;
end

function tf = swallowsName(args, k, names)
% TRUE when one of the first K values is a declared parameter name that
% starts a well formed list of name=value pairs, i.e. taking K positional
% values would read a name=value pair as two positional values.
tf = false;
for p = 1:k
    t = args{p};
    if isNameToken(t) && any(strcmp(char(t), names)) && ...
            pairsValid(args(p:end), names, true, false)
        tf = true;
        return
    end
end
end

function tf = isNameToken(t)
tf = false;
if ischar(t)
    if ~(isrow(t) && ~isempty(t))
        return
    end
elseif isstring(t)
    if ~isscalar(t) || ismissing(t)
        return
    end
else
    return
end
tf = isvarname(char(t));
end

function diagnose(fname, args, names, nPositional, maxK, allowKwargs)
% Raise the most helpful error for an argument list that does not parse.
for cand = 0:maxK
    rest = args(cand+1:end);
    if pairsValid(rest, names, allowKwargs, false)
        for i = 1:2:numel(rest)
            nm = char(rest{i});
            if ~any(strcmp(nm, names))
                error('openalgo:unexpectedArgument', ...
                    '%s() got an unexpected keyword argument ''%s''', fname, nm);
            end
        end
    end
end
nLead = 0;
while nLead < numel(args) && ~isNameToken(args{nLead+1})
    nLead = nLead + 1;
end
if nLead > nPositional
    error('openalgo:invalidArguments', ...
        '%s() takes %d positional argument%s but %d were given', ...
        fname, nPositional, plural(nPositional), nLead);
end
error('openalgo:invalidArguments', ...
    ['%s() expects at most %d positional argument%s followed by name=value pairs ', ...
     '(names are exact and case-sensitive)'], fname, nPositional, plural(nPositional));
end

function s = plural(n)
if n == 1
    s = '';
else
    s = 's';
end
end

function s = joinNames(c)
% Python style: 'a', 'a' and 'b', 'a', 'b', and 'c'
q = cellfun(@(x) ['''' x ''''], c, 'UniformOutput', false);
switch numel(q)
    case 1
        s = q{1};
    case 2
        s = [q{1} ' and ' q{2}];
    otherwise
        s = [strjoin(q(1:end-1), ', ') ', and ' q{end}];
end
end
