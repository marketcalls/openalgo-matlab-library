function tf = isNone(x)
%ISNONE True for the values that mean "not set".
%   TF = openalgo.internal.isNone(X) is true when X is an empty numeric or
%   logical array (for example []) or a missing value. Empty text ('' or
%   ""), empty cell arrays ({}) and empty structs are set: they stand for
%   an empty string, list or object.

tf = ((isnumeric(x) || islogical(x)) && isempty(x)) || isa(x, 'missing');
end
