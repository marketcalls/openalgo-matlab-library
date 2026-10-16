function v = pyInt(x)
%PYINT Convert a scalar value to an integer, as int64.
%   V = openalgo.internal.pyInt(X) truncates a number toward zero, maps
%   true/false to 1/0 and parses integer text, returning int64 so that the
%   value is encoded as a JSON integer. It raises openalgo:valueError for
%   text that is not an integer literal (such as '10.5') or for NaN and
%   Inf, and openalgo:typeError for [] and other types.

if (isnumeric(x) || islogical(x)) && isscalar(x)
    if isinteger(x)
        v = int64(x);
        return
    end
    d = double(x);
    if isnan(d)
        error('openalgo:valueError', 'cannot convert float NaN to integer');
    elseif isinf(d)
        error('openalgo:valueError', 'cannot convert float infinity to integer');
    end
    v = int64(fix(d));
    return
end
if (ischar(x) && size(x, 1) <= 1) || (isstring(x) && isscalar(x) && ~ismissing(x))
    t = strrep(strtrim(char(x)), '_', '');
    if ~isempty(regexp(t, '^[+-]?\d+$', 'once'))
        v = int64(str2double(t));
        if abs(str2double(t)) >= 2^53
            v = sscanf(t, '%ld');
            v = int64(v);
        end
        return
    end
    error('openalgo:valueError', 'invalid literal for int() with base 10: ''%s''', char(x));
end
if openalgo.internal.isNone(x)
    error('openalgo:typeError', 'int() argument must be a string, a bytes-like object or a real number, not ''NoneType''');
end
error('openalgo:typeError', 'int() argument must be a string, a bytes-like object or a real number, not ''%s''', class(x));
end
