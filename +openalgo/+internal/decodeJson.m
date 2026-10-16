function [ok, value, typeName] = decodeJson(text)
%DECODEJSON Decode JSON text, reporting the JSON type of the top value.
%   [OK, VALUE, TYPENAME] = openalgo.internal.decodeJson(TEXT) decodes TEXT
%   with jsondecode. OK is false when TEXT is not valid JSON. TYPENAME
%   names the type of the top level value: 'dict' (object), 'list'
%   (array), 'str', 'int', 'float', 'bool' or 'NoneType' (null), the
%   names used in the error messages. It is needed because
%   jsondecode returns the same MATLAB struct for {"a":1} and [{"a":1}].

ok = false;
value = [];
typeName = '';
if isstring(text)
    text = char(text);
end
if ~ischar(text)
    return
end
t = strtrim(text);
if ~isempty(t) && t(1) == char(65279)   % byte order mark
    t = strtrim(t(2:end));
end
if isempty(t)
    return
end
try
    value = jsondecode(t);
catch
    value = [];
    return
end
ok = true;
switch t(1)
    case '{'
        typeName = 'dict';
    case '['
        typeName = 'list';
    case '"'
        typeName = 'str';
    case {'t', 'f'}
        typeName = 'bool';
    case 'n'
        typeName = 'NoneType';
    otherwise
        if any(t == '.' | t == 'e' | t == 'E') || any(strcmpi(t, {'NaN', 'Infinity', '-Infinity'}))
            typeName = 'float';
        else
            typeName = 'int';
        end
end
end
