classdef MockHttpServer < handle
    %MOCKHTTPSERVER Controls tests/support/mock_http_server.py from MATLAB.
    %   s = MockHttpServer(); s.start(); ... s.stop();
    %
    %   The server listens on a free port of 127.0.0.1, records every request
    %   and answers with queued responses (see mock_http_server.py). The
    %   interpreter is 'python' on the PATH unless OPENALGO_TEST_PYTHON names
    %   another one. Temporary files (ready file, pid file, log) go to
    %   OPENALGO_TEST_TMP when set, else tempdir, and are removed by stop().
    %
    %   Methods:
    %     start, stop           launch and shut down the server
    %     reset                 clear the queue and the recorded requests
    %     enqueue(spec, ...)    queue response specs (structs)
    %     respond(body, status) queue a raw JSON text answer
    %     respondText(body, status) queue a text/plain answer
    %     requests              recorded requests (cell array of structs)
    %     lastRequest           the most recent recorded request

    properties (SetAccess = private)
        Port = []
        ClosedPort = []
        Url = ''
        ClosedUrl = ''
        WorkDir = ''
        LogFile = ''
    end

    properties (Access = private)
        ReadyFile = ''
        PidFile = ''
    end

    methods
        function start(obj)
            here = fileparts(mfilename('fullpath'));
            base = getenv('OPENALGO_TEST_TMP');
            if isempty(base)
                base = tempdir;
            end
            [~, name] = fileparts(tempname);
            obj.WorkDir = fullfile(base, ['resttest_' name]);
            mkdir(obj.WorkDir);
            obj.ReadyFile = fullfile(obj.WorkDir, 'ready.txt');
            obj.PidFile = fullfile(obj.WorkDir, 'server.pid');
            obj.LogFile = fullfile(obj.WorkDir, 'server.log');

            py = getenv('OPENALGO_TEST_PYTHON');
            if isempty(py)
                py = 'python';
            end
            args = {py, '-u', fullfile(here, 'mock_http_server.py'), '--port', '0', ...
                '--ready-file', obj.ReadyFile, '--pid-file', obj.PidFile, '--lifetime', '3600'};
            quoted = cellfun(@(a) ['"' a '"'], args, 'UniformOutput', false);
            cmd = strjoin(quoted, ' ');
            if ispc
                system(['start "" /B ' cmd ' > "' obj.LogFile '" 2>&1']);
            else
                system([cmd ' > "' obj.LogFile '" 2>&1 &']);
            end

            started = tic;
            while ~isfile(obj.ReadyFile) && toc(started) < 30
                pause(0.1);
            end
            if ~isfile(obj.ReadyFile)
                error('MockHttpServer:start', 'Mock HTTP server did not start. Log:\n%s', obj.log());
            end
            ports = str2double(splitlines(strtrim(fileread(obj.ReadyFile))));
            obj.Port = ports(1);
            obj.ClosedPort = ports(2);
            obj.Url = sprintf('http://127.0.0.1:%d', obj.Port);
            obj.ClosedUrl = sprintf('http://127.0.0.1:%d', obj.ClosedPort);
        end

        function stop(obj)
            if isempty(obj.WorkDir)
                return
            end
            try
                obj.control('POST', 'shutdown', '{}');
            catch
            end
            pause(0.3);
            if isfile(obj.PidFile)
                pid = strtrim(fileread(obj.PidFile));
                if ispc
                    [~, ~] = system(['taskkill /F /PID ' pid ' >NUL 2>&1']);
                else
                    [~, ~] = system(['kill ' pid ' 2>/dev/null']);
                end
            end
            if isfolder(obj.WorkDir)
                warnState = warning('off', 'all');
                for k = 1:20
                    try
                        rmdir(obj.WorkDir, 's');
                    catch
                    end
                    if ~isfolder(obj.WorkDir)
                        break
                    end
                    pause(0.1);
                end
                warning(warnState);
            end
            obj.WorkDir = '';
        end

        function delete(obj)
            obj.stop();
        end

        function reset(obj)
            obj.control('POST', 'reset', '{}');
        end

        function enqueue(obj, varargin)
            %ENQUEUE Queue response specs, answered in order.
            %   s.enqueue(struct('status', 409, 'body', '{"a":1}', ...
            %       'content_type', 'application/json'))
            specs = varargin;
            obj.control('POST', 'enqueue', jsonencode(struct('responses', {specs})));
        end

        function respond(obj, body, status)
            %RESPOND Queue an answer whose body is the given JSON text.
            if nargin < 3
                status = 200;
            end
            obj.enqueue(struct('status', status, 'body', char(body), ...
                'content_type', 'application/json'));
        end

        function respondText(obj, body, status)
            %RESPONDTEXT Queue a text/plain answer.
            if nargin < 3
                status = 200;
            end
            obj.enqueue(struct('status', status, 'body', char(body), ...
                'content_type', 'text/plain'));
        end

        function reqs = requests(obj)
            %REQUESTS Recorded requests, a cell array of structs with the
            %   fields method, raw_path, path, raw_query, query, headers,
            %   body and seq.
            text = obj.control('GET', 'requests', []);
            data = jsondecode(text);
            r = data.requests;
            if isempty(r)
                reqs = {};
            elseif isstruct(r)
                reqs = num2cell(r(:)');
            else
                reqs = r(:)';
            end
        end

        function r = lastRequest(obj)
            reqs = obj.requests();
            if isempty(reqs)
                r = [];
            else
                r = reqs{end};
            end
        end

        function text = log(obj)
            text = '';
            if isfile(obj.LogFile)
                text = fileread(obj.LogFile);
            end
        end
    end

    methods (Access = private)
        function text = control(obj, method, cmd, body)
            [code, text] = openalgo.internal.httpRequest(method, ...
                [obj.Url '/__mock__/' cmd], body, 10, [], []);
            if code ~= 200
                error('MockHttpServer:control', 'Control %s failed with HTTP %d: %s', cmd, code, text);
            end
        end
    end
end
