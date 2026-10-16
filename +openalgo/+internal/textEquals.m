function tf = textEquals(value, expected)
%TEXTEQUALS True when VALUE is text equal to EXPECTED.
%   Non-text values (numbers, structs, []) never compare equal: only text
%   equals text.

tf = false;
if (ischar(value) && size(value, 1) <= 1) || (isstring(value) && isscalar(value) && ~ismissing(value))
    tf = strcmp(char(value), expected);
end
end
