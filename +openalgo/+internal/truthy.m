function tf = truthy(x)
%TRUTHY True when a value counts as set.
%   TF = openalgo.internal.truthy(X) is false for [], empty text, empty
%   lists and objects, zero and false; true otherwise (NaN is true).

if openalgo.internal.isNone(x)
    tf = false;
elseif ischar(x)
    tf = ~isempty(x);
elseif isstring(x)
    if isscalar(x)
        tf = ~ismissing(x) && strlength(x) > 0;
    else
        tf = ~isempty(x);
    end
elseif iscell(x)
    tf = ~isempty(x);
elseif isstruct(x)
    if isscalar(x)
        tf = ~isempty(fieldnames(x));
    else
        tf = ~isempty(x);
    end
elseif (isnumeric(x) || islogical(x)) && isscalar(x)
    tf = logical(x ~= 0);
elseif isempty(x)
    tf = false;
else
    tf = true;
end
end
