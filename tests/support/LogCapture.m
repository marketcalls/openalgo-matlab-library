classdef LogCapture < handle
    %LOGCAPTURE Collects feed log lines for the tests (set as log_sink).

    properties
        Lines = {}
    end

    methods
        function add(obj, line)
            obj.Lines{end + 1} = char(line);
        end

        function text = all(obj)
            text = strjoin(obj.Lines, newline);
        end

        function tf = has(obj, part)
            tf = any(contains(obj.Lines, part));
        end

        function clear(obj)
            obj.Lines = {};
        end
    end
end
