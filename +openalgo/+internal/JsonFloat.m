classdef JsonFloat
%JSONFLOAT Marks a number that the Python SDK sends as a float.
%   F = openalgo.internal.JsonFloat(V) wraps the double V for a request
%   payload. openalgo.internal.toJson writes it the way Python json.dumps
%   writes a float, so a whole number keeps its decimal point (700.0, not
%   700). The Python SDK produces floats with float() in the GTT payload
%   and in the option legs; MATLAB has no separate float type, so this
%   wrapper keeps those payloads identical. It is internal: it never
%   appears in values returned to the caller.

    properties
        %VALUE The wrapped number (double).
        Value double
    end

    methods
        function obj = JsonFloat(v)
            obj.Value = double(v);
        end

        function txt = jsonText(obj)
            %JSONTEXT The JSON number text Python json.dumps writes for this float.
            v = obj.Value;
            if isnan(v) || isinf(v)
                txt = 'null';
            elseif v == fix(v) && abs(v) < 1e16
                if v == 0
                    txt = '0.0';
                else
                    txt = [sprintf('%.0f', v) '.0'];
                end
            else
                txt = openalgo.internal.pyStr(v);
            end
        end
    end
end
