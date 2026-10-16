function T = concatTables(tables)
%CONCATTABLES Stack tables whose columns may differ.
%   T = openalgo.internal.concatTables(TABLES) vertically concatenates the
%   tables in the cell array TABLES. The result has the union of the
%   columns in order of first appearance; a column missing from a table is
%   filled with missing values (NaN, <missing> or an empty cell). Columns
%   whose types disagree between tables become cell columns.

tables = tables(~cellfun(@isempty, tables));
if isempty(tables)
    T = table();
    return
end
if isscalar(tables)
    T = tables{1};
    return
end

names = {};
for i = 1:numel(tables)
    v = tables{i}.Properties.VariableNames;
    names = [names, v(~ismember(v, names))]; %#ok<AGROW>
end

% Pick one type per column.
kinds = cell(1, numel(names));
for j = 1:numel(names)
    classes = {};
    absent = false;
    for i = 1:numel(tables)
        if ismember(names{j}, tables{i}.Properties.VariableNames)
            classes{end+1} = class(tables{i}.(names{j})); %#ok<AGROW>
        else
            absent = true;
        end
    end
    classes = unique(classes);
    if isscalar(classes) && any(strcmp(classes{1}, {'double', 'string', 'cell'}))
        kinds{j} = classes{1};
    elseif isscalar(classes) && strcmp(classes{1}, 'logical') && ~absent
        kinds{j} = 'logical';
    elseif all(ismember(classes, {'double', 'logical'}))
        kinds{j} = 'double';
    else
        kinds{j} = 'cell';
    end
end

parts = cell(numel(tables), 1);
for i = 1:numel(tables)
    t = tables{i};
    h = height(t);
    cols = cell(1, numel(names));
    for j = 1:numel(names)
        if ismember(names{j}, t.Properties.VariableNames)
            cols{j} = convert(t.(names{j}), kinds{j});
        else
            cols{j} = filler(h, kinds{j});
        end
    end
    parts{i} = table(cols{:}, 'VariableNames', names);
end
T = vertcat(parts{:});
end

function c = convert(c, kind)
switch kind
    case 'double'
        c = double(c);
    case 'cell'
        if ~iscell(c)
            c = num2cell(c);
        end
end
end

function c = filler(h, kind)
switch kind
    case 'double'
        c = NaN(h, 1);
    case 'string'
        c = strings(h, 1);
        c(:) = missing;
    case 'logical'
        c = false(h, 1);
    otherwise
        c = cell(h, 1);
end
end
