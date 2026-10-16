classdef BaseAPITest < RestTestCase
    %BASEAPITEST Client construction, request headers and the response
    %   handling shared by every REST method (handleResponse and the
    %   transport error mapping).

    methods (Test)
        function constructorDefaults(tc)
            c = openalgo.api(api_key='k');
            tc.verifyEqual(c.api_key, 'k');   % stored as given (a string stays a string)
            tc.verifyEqual(c.base_url, 'http://127.0.0.1:5000/api/v1/');
            tc.verifyEqual(c.timeout, 120);
            tc.verifyClass(c.headers, 'dictionary');
            tc.verifyEqual(c.headers("Content-Type"), "application/json");
            tc.verifyEqual(c.ws_url, 'ws://127.0.0.1:8765');
            tc.verifyEqual(c.ws_port, 8765);
            tc.verifyEqual(c.verbose, 0);
            tc.verifyTrue(c.auto_reconnect);
            tc.verifyFalse(c.connected);
            tc.verifyEqual(openalgo.version(), '1.1.0');
        end

        function constructorPositionalAndNamed(tc)
            c = openalgo.api('k', 'http://example.com:5000', 'v2', 15);
            tc.verifyEqual(c.base_url, 'http://example.com:5000/api/v2/');
            tc.verifyEqual(c.timeout, 15);
            tc.verifyEqual(c.ws_url, 'ws://example.com:8765');
            c = openalgo.api("k", host="https://algo.example.com", ws_port=9000, verbose=true, ...
                auto_reconnect=false);
            tc.verifyEqual(c.base_url, 'https://algo.example.com/api/v1/');
            tc.verifyEqual(c.ws_url, 'wss://algo.example.com/ws');
            tc.verifyEqual(c.verbose, 1);
            tc.verifyFalse(c.auto_reconnect);
            c = openalgo.api(api_key="k", ws_url="ws://feed.example.com:7000");
            tc.verifyEqual(c.ws_url, 'ws://feed.example.com:7000');
            b = openalgo.BaseAPI("k");
            tc.verifyEqual(b.base_url, 'http://127.0.0.1:5000/api/v1/');
        end

        function constructorErrors(tc)
            tc.verifyError(@() openalgo.api(), 'openalgo:missingArgument');
            tc.verifyError(@() openalgo.api(host="http://x"), 'openalgo:missingArgument');
            % A misspelled name raises unexpectedArgument. Before the
            % parseArgs fix this built a client with api_key 'api_key'.
            tc.verifyError(@() openalgo.api(api_key="k", hots="http://x"), 'openalgo:unexpectedArgument');
            tc.verifyError(@() openalgo.api(api_key="k", host="http://x", tmeout=5), ...
                'openalgo:unexpectedArgument');
            % After a positional value a name=value pair with an unknown name
            % is indistinguishable from two more positional values, so this
            % is read as api("k", "hots", "http://x").
            c = openalgo.api("k", hots="http://x");
            tc.verifyEqual(c.base_url, 'hots/api/http://x/');
            tc.verifyError(@() openalgo.api("k", api_key="j"), 'openalgo:duplicateArgument');
        end

        function postHeaders(tc)
            tc.Client.funds();
            r = tc.verifySinglePost('funds', '{"apikey":"test-api-key"}');
            tc.verifySubstring(r.headers.user_agent, 'openalgo-matlab/');
        end

        function successReturnsDecodedJson(tc)
            tc.respond('{"status":"success","data":{"availablecash":1000000,"list":[1,2,3],"none":null,"flag":true}}');
            r = tc.Client.funds();
            tc.verifyEqual(r.status, 'success');
            tc.verifyEqual(r.data.availablecash, 1000000);
            tc.verifyEqual(r.data.list, [1; 2; 3]);
            tc.verifyEqual(r.data.none, []);
            tc.verifyEqual(r.data.flag, true);
            tc.verifyFalse(isfield(r, 'code'));
        end

        function unicodeRoundTrip(tc)
            tc.respond('{"status":"success","message":"café ₹"}');
            r = tc.Client.telegram(username="u", message=['caf' char(233) ' ' char(8377)]); %#ok<XCREDS> test data, not a credential
            tc.verifyEqual(r.message, ['caf' char(233) ' ' char(8377)]);
            req = tc.Server.lastRequest();
            tc.verifySubstring(req.body, ['"message":"caf' char(233) ' ' char(8377) '"']);
        end

        function apiError(tc)
            tc.respond('{"status":"error","message":"Invalid openalgo apikey"}');
            r = tc.Client.funds();
            tc.verifyEqual(r, struct('status', 'error', 'message', 'Invalid openalgo apikey', ...
                'code', 200, 'error_type', 'api_error'));
            tc.respond('{"status":"error"}');
            r = tc.Client.funds();
            tc.verifyEqual(r, struct('status', 'error', 'message', 'Unknown error', ...
                'code', 200, 'error_type', 'api_error'));
        end

        function httpError(tc)
            tc.respondText('Internal Server Error', 500);
            r = tc.Client.funds();
            tc.verifyEqual(r, struct('status', 'error', 'message', 'HTTP 500: Internal Server Error', ...
                'code', 500, 'error_type', 'http_error'));
            tc.respond('{"status":"error","message":"Invalid"}', 403);
            r = tc.Client.funds();
            tc.verifyEqual(r, struct('status', 'error', ...
                'message', 'HTTP 403: {"status":"error","message":"Invalid"}', ...
                'code', 403, 'error_type', 'http_error'));
        end

        function jsonError(tc)
            tc.respondText('<html>');
            r = tc.Client.funds();
            tc.verifyEqual(r, struct('status', 'error', 'message', 'Invalid JSON response from server', ...
                'raw_response', '<html>', 'error_type', 'json_error'));
            tc.respondText('');
            r = tc.Client.funds();
            tc.verifyErrorStruct(r, 'json_error', 'Invalid JSON response from server');
        end

        function nonObjectBodies(tc)
            % A top level JSON value that is not an object gives an
            % unknown_error naming its type.
            cases = {'[{"a":1}]', 'list'; '"hello"', 'str'; '5', 'int'; '1.5', 'float'; ...
                'true', 'bool'; 'null', 'NoneType'};
            for i = 1:size(cases, 1)
                tc.respond(cases{i, 1});
                r = tc.Client.funds();
                tc.verifyEqual(r, struct('status', 'error', 'message', ...
                    sprintf('''%s'' object has no attribute ''get''', cases{i, 2}), ...
                    'error_type', 'unknown_error'), cases{i, 1});
            end
        end

        function timeout(tc)
            c = openalgo.api(api_key="k", host=tc.Server.Url, timeout=1);
            tc.Server.enqueue(struct('delay', 3, 'body', '{"status":"success"}'));
            started = tic;
            r = c.funds();
            tc.verifyLessThan(toc(started), 2.9);
            tc.verifyEqual(r, struct('status', 'error', ...
                'message', 'Request timed out. The server took too long to respond.', ...
                'error_type', 'timeout_error'));
            tc.Server.enqueue(struct('delay', 3, 'body', '{}'));
            r = c.gttorderbook();   % BaseAPI._post path
            tc.verifyErrorStruct(r, 'timeout_error');
            tc.Server.enqueue(struct('delay', 3, 'body', '{}'));
            r = c.chart();          % GET path
            tc.verifyErrorStruct(r, 'timeout_error');
        end

        function connectionRefused(tc)
            c = openalgo.api(api_key="k", host=tc.Server.ClosedUrl);
            expected = struct('status', 'error', 'message', ...
                'Failed to connect to the server. Please check if the server is running.', ...
                'error_type', 'connection_error');
            tc.verifyEqual(c.funds(), expected);
            tc.verifyEqual(c.chart(), expected);
            tc.verifyEqual(c.placegttorder(symbol="A", exchange="NSE", action="BUY", triggerprice_sl=1), expected);
        end

        function connectionClosedWithoutResponse(tc)
            % A connection closed without a response -> http_error 'HTTP error occurred: ...'
            tc.Server.enqueue(struct('action', 'close'));
            r = tc.Client.funds();
            tc.verifyErrorStruct(r, 'http_error');
            tc.verifyTrue(startsWith(r.message, 'HTTP error occurred: '), r.message);
        end

        function closedClient(tc)
            c = openalgo.api(api_key="k", host=tc.Server.Url);
            c.close();
            expected = struct('status', 'error', 'message', ...
                'An unexpected error occurred: Cannot send a request, as the client has been closed.', ...
                'error_type', 'unknown_error');
            tc.verifyEqual(c.funds(), expected);
            tc.verifyEqual(c.gttorderbook(), expected);
            tc.verifyEqual(c.instruments(exchange="NSE"), expected);
            tc.verifyEqual(c.instruments(), struct('status', 'error', ...
                'message', 'Failed to fetch instruments from any exchange', 'error_type', 'no_data'));
            tc.verifyNoRequest();
        end
    end
end
