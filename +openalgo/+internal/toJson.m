function txt = toJson(value)
%TOJSON Encode a payload as JSON text.
%   TXT = openalgo.internal.toJson(VALUE) uses jsonencode after mapping the
%   MATLAB conventions of this library onto JSON:
%
%     []  (not set)                -> null
%     scalar struct                -> object, fields in order
%     struct array or cell array   -> array (also with one element)
%     char row or string scalar    -> string
%     logical                      -> true or false
%     integer types                -> integer
%     whole double                 -> integer (123456789, never 1.23456789E+8)
%     other double                 -> shortest round-trip text (750.55)
%     NaN or Inf                   -> null
%     openalgo.internal.JsonFloat  -> number with a decimal point (700.0)
%     numeric vector               -> array of numbers
%
%   Numbers are written here rather than by jsonencode, which switches to
%   exponent notation for values from about 1e7 and writes 17 significant
%   digits; here integers are written in full and floats in their
%   shortest form. An empty cell array {} encodes as [] (an empty list)
%   and struct() encodes as {} (an empty object).

numbers = {};
prepared = prep(value);
txt = jsonencode(prepared);
for k = numel(numbers):-1:1
    txt = strrep(txt, ['"' token(k) '"'], numbers{k});
end

    function v = prep(v)
        if isa(v, 'openalgo.internal.JsonFloat')
            v = number(jsonText(v));
        elseif openalgo.internal.isNone(v)
            v = NaN;   % jsonencode writes NaN as null
        elseif isfloat(v) && isreal(v)
            if isscalar(v)
                v = numberText(v);
            elseif isvector(v)
                c = cell(1, numel(v));
                for i = 1:numel(v)
                    c{i} = numberText(v(i));
                end
                v = c;
            elseif ismatrix(v)
                rows = cell(1, size(v, 1));
                for r = 1:size(v, 1)
                    c = cell(1, size(v, 2));
                    for i = 1:size(v, 2)
                        c{i} = numberText(v(r, i));
                    end
                    rows{r} = c;
                end
                v = rows;
            end
        elseif isstruct(v)
            if isscalar(v)
                f = fieldnames(v);
                for i = 1:numel(f)
                    v.(f{i}) = prep(v.(f{i}));
                end
            else
                c = num2cell(v(:)');
                for i = 1:numel(c)
                    c{i} = prep(c{i});
                end
                v = c;
            end
        elseif iscell(v)
            v = v(:)';
            for i = 1:numel(v)
                v{i} = prep(v{i});
            end
        end
    end

    function out = numberText(x)
        % A placeholder for one double, replaced by its JSON text after encoding.
        if isnan(x) || isinf(x)
            out = NaN;
        elseif x == fix(x) && abs(x) < 1e16
            out = number(sprintf('%.0f', double(x)));
            if x == 0
                numbers{end} = '0';
            end
        else
            out = number(openalgo.internal.pyStr(x));
        end
    end

    function t = number(text)
        numbers{end+1} = text;
        t = token(numel(numbers));
    end
end

function t = token(k)
t = sprintf('__openalgo_json_number_%d__', k);
end
