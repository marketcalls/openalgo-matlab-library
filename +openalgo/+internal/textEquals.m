function tf = textEquals(value, expected)
%TEXTEQUALS True when VALUE is text equal to EXPECTED (Python value == 'str').
%   Non-text values (numbers, structs, None) never compare equal, as in
%   Python where a str only equals a str.

tf = false;
if (ischar(value) && size(value, 1) <= 1) || (isstring(value) && isscalar(value) && ~ismissing(value))
    tf = strcmp(char(value), expected);
end
end
