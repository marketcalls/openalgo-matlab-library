function v = pyFloat(x)
%PYFLOAT Python float() of a scalar value.
%   V = openalgo.internal.pyFloat(X) converts a number, logical or numeric
%   text to a double, and raises openalgo:valueError (text that is not a
%   number) or openalgo:typeError (anything else, including None) the way
%   Python float() raises ValueError and TypeError.

if (isnumeric(x) || islogical(x)) && isscalar(x)
    v = double(x);
    return
end
if (ischar(x) && size(x, 1) <= 1) || (isstring(x) && isscalar(x) && ~ismissing(x))
    t = strtrim(char(x));
    tl = lower(t);
    if any(strcmp(tl, {'nan', '+nan', '-nan'}))
        v = NaN;
        return
    elseif any(strcmp(tl, {'inf', '+inf', 'infinity', '+infinity'}))
        v = Inf;
        return
    elseif any(strcmp(tl, {'-inf', '-infinity'}))
        v = -Inf;
        return
    end
    t2 = strrep(t, '_', '');
    if ~isempty(regexp(t2, '^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$', 'once'))
        v = str2double(t2);
        return
    end
    error('openalgo:valueError', 'could not convert string to float: ''%s''', char(x));
end
if openalgo.internal.isNone(x)
    error('openalgo:typeError', 'float() argument must be a string or a real number, not ''NoneType''');
end
error('openalgo:typeError', 'float() argument must be a string or a real number, not ''%s''', class(x));
end
