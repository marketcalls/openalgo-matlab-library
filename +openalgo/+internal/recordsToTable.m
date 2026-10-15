function T = recordsToTable(records)
%RECORDSTOTABLE Convert a decoded list of JSON records into a table.
%   T = openalgo.internal.recordsToTable(RECORDS) works like
%   pandas.DataFrame(list_of_dicts). RECORDS is what jsondecode returns for
%   a JSON array of objects: a struct array (all objects share their keys)
%   or a cell array of structs (keys differ). Columns appear in order of
%   first appearance and a key missing from a record becomes a missing
%   value.
%
%   Column types:
%     numbers, logicals and nulls  -> double (null as NaN); all logical
%                                     values without nulls stay logical
%     text and nulls               -> string (null as <missing>)
%     anything else                -> cell
%
%   An empty input gives an empty table. Raises openalgo:processingError
%   when an entry is not a JSON object.

if istable(records)
    T = records;
    return
end
if isempty(records)
    T = table();
    return
end

if isstruct(records)
    cols = fieldnames(records)';
    n = numel(records);
    columns = cell(1, numel(cols));
    for j = 1:numel(cols)
        vals = reshape({records.(cols{j})}, [], 1);
        columns{j} = makeColumn(vals);
    end
elseif iscell(records)
    recs = records(:);
    n = numel(recs);
    cols = {};
    for i = 1:n
        r = recs{i};
        if ~(isstruct(r) && isscalar(r))
            error('openalgo:processingError', ...
                'Each record must be a JSON object, got %s', class(r));
        end
        f = fieldnames(r)';
        cols = [cols, f(~ismember(f, cols))]; %#ok<AGROW>
    end
    columns = cell(1, numel(cols));
    for j = 1:numel(cols)
        vals = cell(n, 1);
        name = cols{j};
        for i = 1:n
            if isfield(recs{i}, name)
                vals{i} = recs{i}.(name);
            else
                vals{i} = [];
            end
        end
        columns{j} = makeColumn(vals);
    end
else
    error('openalgo:processingError', ...
        'Expected a list of JSON objects, got %s', class(records));
end

if isempty(cols)
    T = table('Size', [n 0], 'VariableTypes', {});
    return
end
T = table(columns{:}, 'VariableNames', cols);
end

function col = makeColumn(vals)
n = numel(vals);

% Fast paths for the common homogeneous columns.
isScalar = cellfun('prodofsize', vals) == 1;
if all(isScalar & cellfun('isclass', vals, 'double'))
    col = reshape([vals{:}], n, 1);
    return
end
isChar = cellfun('isclass', vals, 'char');
if all(isChar) && all(cellfun('size', vals, 1) <= 1)
    col = reshape(string(vals), n, 1);
    return
end

isNull = cellfun(@(v) openalgo.internal.isNone(v), vals);
isNum = cellfun(@(v) (isnumeric(v) || islogical(v)) && isscalar(v), vals);
isLog = cellfun(@(v) islogical(v) && isscalar(v), vals);
isTxt = cellfun(@(v) (ischar(v) && size(v, 1) <= 1) || (isstring(v) && isscalar(v)), vals);

if all(isLog)
    col = reshape(logical(cell2mat(vals)), n, 1);
elseif all(isNum | isNull) && any(isNum)
    col = NaN(n, 1);
    col(isNum) = cellfun(@double, vals(isNum));
elseif all(isTxt | isNull) && any(isTxt)
    col = strings(n, 1);
    col(isNull) = missing;
    col(isTxt) = reshape(string(vals(isTxt)), [], 1);
elseif all(isNull)
    col = NaN(n, 1);
else
    col = vals;
end
end
