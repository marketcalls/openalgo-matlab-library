function payload = addKwargs(payload, kw, stringify, skipExisting)
%ADDKWARGS Merge extra name=value pairs into a payload struct.
%   PAYLOAD = openalgo.internal.addKwargs(PAYLOAD, KW, STRINGIFY,
%   SKIPEXISTING) adds each {name, value} row of KW (from parseArgs) to
%   PAYLOAD in order, skipping unset ([]) values. With STRINGIFY true each
%   value is converted to text with pyStr; otherwise it is sent as is.
%   With SKIPEXISTING true a name already in PAYLOAD is left untouched;
%   otherwise it is overwritten in place, keeping its position.

if nargin < 3
    stringify = false;
end
if nargin < 4
    skipExisting = false;
end
for i = 1:size(kw, 1)
    name = kw{i, 1};
    value = kw{i, 2};
    if openalgo.internal.isNone(value)
        continue
    end
    if skipExisting && isfield(payload, name)
        continue
    end
    if stringify
        payload.(name) = openalgo.internal.pyStr(value);
    else
        payload.(name) = value;
    end
end
end
