function s = errorResult(message, errorType, varargin)
%ERRORRESULT Build the error struct a REST method returns instead of raising.
%   S = openalgo.internal.errorResult(MESSAGE, ERRORTYPE, NAME1, VALUE1, ...)
%   returns a struct with the fields status ('error'), message, any extra
%   NAME/VALUE fields in the order given, and error_type, in that order.

s = struct();
s.status = 'error';
s.message = message;
for i = 1:2:numel(varargin)
    s.(varargin{i}) = varargin{i+1};
end
s.error_type = errorType;
end
