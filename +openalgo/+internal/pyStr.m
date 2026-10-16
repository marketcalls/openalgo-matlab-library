function s = pyStr(x)
%PYSTR Text form of a value, as sent in text payload fields.
%   S = openalgo.internal.pyStr(X) returns a character vector:
%
%     pyStr("SBIN")  -> 'SBIN'      pyStr(10)     -> '10'
%     pyStr(750.5)   -> '750.5'     pyStr(100000) -> '100000'
%     pyStr(true)    -> 'True'      pyStr([])     -> 'None'
%     pyStr(NaN)     -> 'nan'       pyStr(Inf)    -> 'inf'
%
%   Whole numbers are never written in scientific notation (a MATLAB
%   double that holds a whole number is treated as an integer). Other
%   numbers use the shortest text that reads back as the same value.
%   Lists (cell arrays, non-scalar arrays) are rendered as ['a', 1] and
%   objects (structs) as {'key': 'value'}.

if openalgo.internal.isNone(x)
    s = 'None';
elseif ischar(x)
    if size(x, 1) <= 1
        s = x;
        if isempty(s)
            s = '';
        end
    else
        s = listRepr(cellstr(x));
    end
elseif isstring(x) && isscalar(x)
    if ismissing(x)
        s = 'None';
    else
        s = char(x);
    end
elseif (isnumeric(x) || islogical(x)) && isscalar(x)
    s = scalarStr(x);
elseif isa(x, 'datetime') && isscalar(x)
    if isnat(x)
        s = 'NaT';
    else
        s = char(x, 'yyyy-MM-dd HH:mm:ss');
    end
else
    s = pyRepr(x);
end
end

function s = scalarStr(x)
if islogical(x)
    if x
        s = 'True';
    else
        s = 'False';
    end
    return
end
if isinteger(x)
    s = sprintf('%d', x);
    return
end
if ~isreal(x)
    s = ['(' scalarStr(real(x)) signed(imag(x)) 'j)'];
    return
end
if isnan(x)
    s = 'nan';
elseif isinf(x)
    if x > 0
        s = 'inf';
    else
        s = '-inf';
    end
elseif x == fix(x)
    if x == 0
        s = '0';
    else
        s = sprintf('%.0f', double(x));
    end
else
    s = shortest(x);
end
end

function s = signed(v)
t = scalarStr(v);
if v >= 0 || isnan(v)
    s = ['+' t];
else
    s = t;
end
end

function s = shortest(x)
% Shortest text that reads back as the same value.
if isa(x, 'single')
    for prec = 6:9
        s = sprintf('%.*g', prec, x);
        if single(str2double(s)) == x
            break
        end
    end
else
    for prec = 15:17
        s = sprintf('%.*g', prec, x);
        if str2double(s) == x
            break
        end
    end
end
end

function s = pyRepr(x)
% Literal text of a value inside a list or object: text quoted.
if ischar(x)
    if size(x, 1) <= 1
        s = quoteStr(x);
    else
        s = listRepr(cellstr(x));
    end
elseif isstring(x)
    if isscalar(x)
        if ismissing(x)
            s = 'None';
        else
            s = quoteStr(char(x));
        end
    else
        s = listRepr(num2cell(x(:)'));
    end
elseif iscell(x)
    s = listRepr(x(:)');
elseif isstruct(x)
    if isscalar(x)
        f = fieldnames(x);
        parts = cell(1, numel(f));
        for i = 1:numel(f)
            parts{i} = [quoteStr(f{i}) ': ' pyRepr(x.(f{i}))];
        end
        s = ['{' strjoin(parts, ', ') '}'];
    else
        s = listRepr(num2cell(x(:)'));
    end
elseif openalgo.internal.isNone(x)
    s = 'None';
elseif isnumeric(x) || islogical(x)
    if isscalar(x)
        s = scalarStr(x);
    else
        s = listRepr(num2cell(x(:)'));
    end
else
    try
        s = char(string(x));
        if size(s, 1) > 1
            s = class(x);
        end
    catch
        s = class(x);
    end
end
end

function s = listRepr(c)
parts = cell(1, numel(c));
for i = 1:numel(c)
    parts{i} = pyRepr(c{i});
end
s = ['[' strjoin(parts, ', ') ']'];
end

function s = quoteStr(t)
t = char(t);
if any(t == '''') && ~any(t == '"')
    s = ['"' t '"'];
else
    s = ['''' strrep(strrep(t, '\', '\\'), '''', '\''') ''''];
end
end
