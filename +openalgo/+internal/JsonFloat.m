classdef JsonFloat
%JSONFLOAT Marks a number that is sent as a JSON float.
%   F = openalgo.internal.JsonFloat(V) wraps the double V for a request
%   payload. openalgo.internal.toJson writes it as a float, so a whole
%   number keeps its decimal point (700.0, not 700). The GTT payload and
%   the option legs send some numbers as floats; MATLAB has no separate
%   float type, so this wrapper marks them. It is internal: it never
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
            %JSONTEXT The JSON number text of this float (shortest form, with a decimal point).
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
