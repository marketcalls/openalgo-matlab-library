classdef StrategyWebhookTest < RestTestCase
    %STRATEGYWEBHOOKTEST openalgo.Strategy: token rules, URL, redacted
    %   display, payloads and response handling of the public webhook.

    properties (Constant)
        Token = 'oaws_secret_token_123'
    end

    methods
        function s = sender(tc, varargin)
            s = openalgo.Strategy(tc.Server.Url, tc.Token, varargin{:});
        end

        function r = verifyWebhookPost(tc, expectedBody)
            reqs = tc.Server.requests();
            tc.verifyNumElements(reqs, 1);
            r = reqs{end};
            tc.verifyEqual(r.method, 'POST');
            tc.verifyEqual(r.path, ['/strategy/webhook/' tc.Token]);
            tc.verifyEqual(r.headers.content_type, 'application/json');
            tc.verifyEqual(r.body, expectedBody);
        end
    end

    methods (Test)
        function tokenRules(tc)
            u = tc.Server.Url;
            tc.verifyError(@() openalgo.Strategy(u), 'openalgo:valueError');
            tc.verifyError(@() openalgo.Strategy(u, ''), 'openalgo:valueError');
            tc.verifyError(@() openalgo.Strategy(u, webhook_token=""), 'openalgo:valueError');
            tc.verifyError(@() openalgo.Strategy(), 'openalgo:missingArgument');
            tc.verifyError(@() openalgo.Strategy(u, 1, 2), 'openalgo:invalidArguments');
            tc.verifyError(@() openalgo.Strategy(u, 'a', nope=1), 'openalgo:unexpectedArgument');
            s = openalgo.Strategy(u, webhook_id="a", webhook_token="b");   % webhook_token wins
            tc.verifyEqual(s.webhook_url, [u '/strategy/webhook/b']);
            s = openalgo.Strategy(host_url=u, webhook_id="a");
            tc.verifyEqual(s.webhook_url, [u '/strategy/webhook/a']);
            % webhook_token="" is set (not []), so it wins and is rejected as empty
            tc.verifyError(@() openalgo.Strategy(u, 'a', webhook_token=''), 'openalgo:valueError');
        end

        function urlAndDefaults(tc)
            s = openalgo.Strategy([tc.Server.Url '//'], tc.Token);   % trailing slashes stripped
            tc.verifyEqual(s.webhook_url, [tc.Server.Url '/strategy/webhook/' tc.Token]);
            tc.verifyEqual(s.timeout, 30);
            s = tc.sender(timeout=5);
            tc.verifyEqual(s.timeout, 5);
            tc.verifyError(@() setfield(s, 'webhook_url', 'x'), ?MException);
        end

        function displayRedactsToken(tc)
            s = tc.sender(); %#ok<NASGU> used inside evalc
            text = evalc('disp(s)');
            tc.verifySubstring(text, ['Strategy(host_url=''' tc.Server.Url ''', webhook_token=<redacted>)']);
            tc.verifyFalse(contains(text, tc.Token));
            tc.verifyFalse(contains(evalc('display(s)'), tc.Token));
        end

        function startAndStop(tc)
            tc.respond('{"status":"success","result":"accepted","run_id":4}');
            s = tc.sender();
            r = s.start("sandbox");
            tc.verifyWebhookPost('{"action":"start","mode":"sandbox"}');
            tc.verifyEqual(r, struct('status', 'success', 'result', 'accepted', 'run_id', 4));
            tc.Server.reset();
            s.start(mode="live");
            tc.verifyWebhookPost('{"action":"start","mode":"live"}');
            tc.Server.reset();
            tc.respond('{"status":"error","result":"rejected_cooling_off"}', 409);
            r = s.stop();
            tc.verifyWebhookPost('{"action":"stop"}');
            tc.verifyEqual(r, struct('status', 'error', 'result', 'rejected_cooling_off', 'code', 409));
            tc.verifyError(@() s.start(), 'openalgo:missingArgument');
            tc.verifyError(@() s.stop("x"), 'openalgo:invalidArguments');
        end

        function signals(tc)
            s = tc.sender();
            s.signal("long_entry", leg_id="3", symbol="SBIN", exchange="NSE");
            tc.verifyWebhookPost('{"action":"long_entry","leg_id":3,"symbol":"SBIN","exchange":"NSE"}');
            names = {'long_entry', 'long_exit', 'short_entry', 'short_exit'};
            for i = 1:numel(names)
                tc.Server.reset();
                feval(names{i}, s, symbol="SBIN");
                tc.verifyWebhookPost(['{"action":"' names{i} '","symbol":"SBIN"}']);
            end
            tc.Server.reset();
            s.short_exit(leg_id=2);
            tc.verifyWebhookPost('{"action":"short_exit","leg_id":2}');
            tc.verifyError(@() s.long_entry(1), 'openalgo:invalidArguments');
        end

        function sendRawPayload(tc)
            s = tc.sender();
            s.send(struct('action', 'stop', 'note', 'x'));
            tc.verifyWebhookPost('{"action":"stop","note":"x"}');
        end

        function responseHandling(tc)
            s = tc.sender();
            tc.respondText('ok');
            r = s.stop();
            tc.verifyEqual(r, struct('status', 'error', 'message', 'HTTP 200: ok', ...
                'raw_response', 'ok', 'code', 200, 'error_type', 'http_error'));
            tc.respondText('boom', 500);
            r = s.stop();
            tc.verifyEqual(r, struct('status', 'error', 'message', 'HTTP 500: boom', ...
                'raw_response', 'boom', 'code', 500, 'error_type', 'http_error'));
            tc.respond('[1]');
            r = s.stop();
            tc.verifyEqual(r, struct('status', 'error', 'message', 'Unexpected JSON response from server', ...
                'raw_response', 1, 'code', 200, 'error_type', 'json_error'));
        end

        function transportErrors(tc)
            s = openalgo.Strategy(tc.Server.ClosedUrl, tc.Token);
            r = s.stop();
            tc.verifyEqual(r, struct('status', 'error', 'message', ...
                'Failed to connect to the server. Please check if the server is running.', ...
                'error_type', 'connection_error'));
            tc.Server.enqueue(struct('delay', 3, 'body', '{}'));
            s = tc.sender(timeout=1);
            r = s.stop();
            tc.verifyEqual(r, struct('status', 'error', 'message', ...
                'Request timed out. The server took too long to respond.', 'error_type', 'timeout_error'));
        end

        function removedAndClosed(tc)
            s = tc.sender();
            tc.verifyError(@() s.strategyorder("SBIN", "BUY", 1), 'openalgo:notImplemented');
            s.close();
            tc.verifyError(@() s.stop(), 'openalgo:clientClosed');
            tc.verifyNoRequest();
        end
    end
end
