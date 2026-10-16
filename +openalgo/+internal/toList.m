function [c, isList] = toList(x)
%TOLIST Normalize a list-like value to a 1-by-N cell array.
%   [C, ISLIST] = openalgo.internal.toList(X) accepts the MATLAB spellings
%   of a list of objects or values:
%
%     cell array {s1, s2}      -> {s1, s2}
%     struct array [s1 s2]     -> {s1, s2}   (a 1-by-1 struct gives {s1})
%     string array ["a" "b"]   -> {"a", "b"}
%     numeric or logical array -> one element per entry
%
%   ISLIST is false (and C is {}) for values that are not list-like, such
%   as [], a char vector or a scalar string. A list encodes as a
%   JSON array even when it has one element.

isList = true;
if iscell(x)
    c = x(:)';
elseif isstruct(x)
    c = num2cell(x(:)');
elseif isstring(x) && ~isscalar(x)
    c = num2cell(x(:)');
elseif (isnumeric(x) || islogical(x)) && ~isempty(x)
    c = num2cell(x(:)');
else
    c = {};
    isList = false;
end
end
