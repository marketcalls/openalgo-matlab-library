function tf = isNone(x)
%ISNONE True for the values that stand for Python None.
%   TF = openalgo.internal.isNone(X) is true when X is an empty numeric or
%   logical array (for example []) or a missing value. Empty text ('' or
%   ""), empty cell arrays ({}) and empty structs are not None: they stand
%   for an empty Python string, list or dict.

tf = ((isnumeric(x) || islogical(x)) && isempty(x)) || isa(x, 'missing');
end
