classdef AdditionalEndpointsTest < RestTestCase
    %ADDITIONALENDPOINTSTEST Methods for server endpoints that the Python
    %   SDK lacks: ping, pnlsymbols, multioptiongreeks, ticker, chart,
    %   updatechart and the Telegram management surface.

    methods (Test)
        function pingAndPnlsymbols(tc)
            tc.respond('{"status":"success","data":{"message":"pong","broker":"sandbox"}}');
            r = tc.Client.ping();
            tc.verifySinglePost('ping', '{"apikey":"test-api-key"}');
            tc.verifyEqual(r.data.message, 'pong');
            tc.Server.reset();
            tc.Client.pnlsymbols();
            tc.verifySinglePost('pnl/symbols', '{"apikey":"test-api-key"}');
            tc.respond('{"status":"error","message":"Invalid openalgo apikey"}', 403);
            r = tc.Client.ping();
            tc.verifyErrorStruct(r, 'http_error');
            tc.verifyEqual(r.code, 403);
        end

        function multioptiongreeksPayload(tc)
            one = struct('symbol', 'NIFTY25AUG2625000CE', 'exchange', 'NFO');
            tc.Client.multioptiongreeks(symbols=one, interest_rate=7, expiry_time="15:30");
            tc.verifySinglePost('multioptiongreeks', ['{"apikey":"test-api-key","symbols":[' ...
                '{"symbol":"NIFTY25AUG2625000CE","exchange":"NFO"}],"interest_rate":7,"expiry_time":"15:30"}']);
            tc.Server.reset();
            two = {one, struct('symbol', 'NIFTY25AUG2625000PE', 'exchange', 'NFO', ...
                'underlying_symbol', 'NIFTY', 'underlying_exchange', 'NSE_INDEX')};
            tc.Client.multioptiongreeks(symbols=two);
            tc.verifySinglePost('multioptiongreeks', ['{"apikey":"test-api-key","symbols":[' ...
                '{"symbol":"NIFTY25AUG2625000CE","exchange":"NFO"},{"symbol":"NIFTY25AUG2625000PE",' ...
                '"exchange":"NFO","underlying_symbol":"NIFTY","underlying_exchange":"NSE_INDEX"}]}']);
        end

        function multioptiongreeksValidation(tc)
            c = tc.Client;
            tc.verifyEqual(c.multioptiongreeks(symbols="NIFTY"), struct('status', 'error', ...
                'message', 'Symbols must be an array', 'error_type', 'validation_error'));
            tc.verifyErrorStruct(c.multioptiongreeks(symbols=[]), 'validation_error', 'Symbols must be an array');
            tc.verifyErrorStruct(c.multioptiongreeks(symbols={}), 'validation_error', 'Symbols array cannot be empty');
            many = repmat({struct('symbol', 'X', 'exchange', 'NFO')}, 1, 51);
            tc.verifyErrorStruct(c.multioptiongreeks(symbols=many), 'validation_error', 'Maximum 50 symbols allowed');
            tc.verifyError(@() c.multioptiongreeks(), 'openalgo:missingArgument');
            tc.verifyNoRequest();
        end

        function tickerJson(tc)
            tc.respond('{"status":"success","data":[{"timestamp":1735790400,"open":1,"high":2,"low":0.5,"close":1.5,"volume":10}]}');
            r = tc.Client.ticker(symbol="RELIANCE", exchange="NSE", start_date="2026-07-01", end_date="2026-07-10");
            tc.verifySingleGet('/api/v1/ticker/NSE:RELIANCE', ...
                'apikey=test-api-key&interval=D&from=2026-07-01&to=2026-07-10&format=json');
            tc.verifyEqual(r.status, 'success');
            tc.verifyEqual(r.data.close, 1.5);
            tc.respond('{"status":"error","message":"Invalid symbol"}');
            r = tc.Client.ticker(symbol="X", exchange="NSE", start_date="a", end_date="b");
            tc.verifyErrorStruct(r, 'api_error', 'Invalid symbol');
        end

        function tickerText(tc)
            body = sprintf('RELIANCE,2026-07-01,1,2,0.5,1.5,10\nRELIANCE,2026-07-02,1,2,0.5,1.5,11');
            tc.respondText(body);
            r = tc.Client.ticker(symbol="RELIANCE", exchange="NSE", interval="5m", ...
                start_date="2026-07-01", end_date="2026-07-02", format="txt", adjusted=true);
            tc.verifySingleGet('/api/v1/ticker/NSE:RELIANCE', ...
                'apikey=test-api-key&interval=5m&from=2026-07-01&to=2026-07-02&format=txt&adjusted=true');
            tc.verifyEqual(r, body);
            tc.respondText('Invalid date', 400);
            r = tc.Client.ticker(symbol="RELIANCE", exchange="NSE", start_date="x", end_date="y", format="txt");
            tc.verifyEqual(r, struct('status', 'error', 'message', 'HTTP 400: Invalid date', ...
                'code', 400, 'error_type', 'http_error'));
        end

        function tickerPathEncoding(tc)
            cases = {'M&M', 'NSE', '/api/v1/ticker/NSE:M&M', '/api/v1/ticker/NSE:M&M'; ...
                     'NIFTY 50', 'NSE_INDEX', '/api/v1/ticker/NSE_INDEX:NIFTY%2050', '/api/v1/ticker/NSE_INDEX:NIFTY 50'; ...
                     'A/B', 'NSE', '/api/v1/ticker/NSE:A%2FB', '/api/v1/ticker/NSE:A/B'; ...
                     'BAJAJ-AUTO', 'NSE', '/api/v1/ticker/NSE:BAJAJ-AUTO', '/api/v1/ticker/NSE:BAJAJ-AUTO'};
            for i = 1:size(cases, 1)
                tc.Server.reset();
                tc.Client.ticker(symbol=cases{i, 1}, exchange=cases{i, 2}, start_date="a", end_date="b");
                r = tc.Server.lastRequest();
                tc.verifyEqual(r.raw_path, cases{i, 3}, cases{i, 1});
                tc.verifyEqual(r.path, cases{i, 4}, cases{i, 1});
            end
        end

        function chartReadAndUpdate(tc)
            tc.respond('{"status":"success","data":{"tv_theme":"dark"}}');
            r = tc.Client.chart();
            tc.verifySingleGet('/api/v1/chart', 'apikey=test-api-key');
            tc.verifyEqual(r.data.tv_theme, 'dark');
            tc.Server.reset();
            tc.Client.updatechart(tv_theme="dark", skip=[], tv_chart_layout=struct('interval', '15m', 'n', 2));
            tc.verifySinglePost('chart', ['{"apikey":"test-api-key","tv_theme":"dark",' ...
                '"tv_chart_layout":{"interval":"15m","n":2}}']);
        end

        function updatechartValidation(tc)
            c = tc.Client;
            tc.verifyEqual(c.updatechart(), struct('status', 'error', ...
                'message', 'No preferences provided to update', 'error_type', 'validation_error'));
            tc.verifyErrorStruct(c.updatechart(a=[]), 'validation_error', 'No preferences provided to update');
            args = cell(1, 102);
            for i = 1:51
                args{2*i - 1} = sprintf('k%d', i);
                args{2*i} = i;
            end
            tc.verifyErrorStruct(c.updatechart(args{:}), 'validation_error', 'Too many preference keys (max 50)');
            longKey = ['a' repmat('b', 1, 50)];   % 51 characters
            tc.verifyErrorStruct(c.updatechart(longKey, 1), 'validation_error', ...
                ['Preference key too long: ' longKey(1:20) '... (max 50 chars)']);
            tc.verifyNoRequest();
            c.updatechart(args{1:100});   % exactly 50 keys is accepted
            r = tc.Server.lastRequest();
            tc.verifyNumElements(fieldnames(jsondecode(r.body)), 51);
        end

        function telegramConfig(tc)
            tc.respond('{"status":"success","data":{"bot_token":"1234567890...","is_active":false}}');
            r = tc.Client.telegramconfig();
            tc.verifySingleGet('/api/v1/telegram/config', 'apikey=test-api-key');
            tc.verifyEqual(r.data.is_active, false);
            tc.Server.reset();
            tc.Client.updatetelegramconfig(polling_mode=true, rate_limit_per_minute=30, token=[]);
            tc.verifySinglePost('telegram/config', ...
                '{"apikey":"test-api-key","polling_mode":true,"rate_limit_per_minute":30}');
            tc.Server.reset();
            tc.Client.updatetelegramconfig(rate_limit_per_minute=30, token="t", broadcast_enabled=false, x="y");
            tc.verifySinglePost('telegram/config', ['{"apikey":"test-api-key","token":"t",' ...
                '"broadcast_enabled":false,"rate_limit_per_minute":30,"x":"y"}']);
        end

        function telegramStartStop(tc)
            tc.Client.telegramstart();
            tc.verifySinglePost('telegram/start', '{"apikey":"test-api-key"}');
            tc.Server.reset();
            tc.Client.telegramstop();
            tc.verifySinglePost('telegram/stop', '{"apikey":"test-api-key"}');
            tc.respond('{"status":"error","message":"Bot token not configured"}', 400);
            r = tc.Client.telegramstart();
            tc.verifyErrorStruct(r, 'http_error');
            tc.verifyEqual(r.code, 400);
        end

        function telegramUsersStatsPreferences(tc)
            tc.Client.telegramusers();
            tc.verifySingleGet('/api/v1/telegram/users', 'apikey=test-api-key');
            tc.Server.reset();
            tc.Client.telegramusers(notifications_enabled=true, broker="zz");
            tc.verifySingleGet('/api/v1/telegram/users', 'apikey=test-api-key&broker=zz&notifications_enabled=true');
            tc.Server.reset();
            tc.Client.telegramstats(30);
            tc.verifySingleGet('/api/v1/telegram/stats', 'apikey=test-api-key&days=30');
            tc.Server.reset();
            tc.Client.telegramstats();
            tc.verifySingleGet('/api/v1/telegram/stats', 'apikey=test-api-key');
            tc.Server.reset();
            tc.Client.telegrampreferences(123456789);
            tc.verifySingleGet('/api/v1/telegram/preferences', 'apikey=test-api-key&telegram_id=123456789');
            tc.verifyError(@() tc.Client.telegrampreferences(), 'openalgo:missingArgument');
        end

        function updateTelegramPreferences(tc)
            tc.Client.updatetelegrampreferences(123456789, daily_summary=true, summary_time="18:00");
            tc.verifySinglePost('telegram/preferences', ['{"apikey":"test-api-key","telegram_id":123456789,' ...
                '"daily_summary":true,"summary_time":"18:00"}']);
            tc.Server.reset();
            tc.Client.updatetelegrampreferences(telegram_id=1, timezone="Asia/Kolkata", order_notifications=false);
            tc.verifySinglePost('telegram/preferences', ['{"apikey":"test-api-key","telegram_id":1,' ...
                '"order_notifications":false,"timezone":"Asia/Kolkata"}']);
        end

        function telegramBroadcast(tc)
            c = tc.Client;
            tc.verifyEqual(c.telegrambroadcast(message=""), struct('status', 'error', ...
                'message', 'Message is required', 'error_type', 'validation_error'));
            tc.verifyErrorStruct(c.telegrambroadcast(message=[]), 'validation_error', 'Message is required');
            tc.verifyErrorStruct(c.telegrambroadcast(message=repmat('x', 1, 4097)), 'validation_error', ...
                'Message must not exceed 4096 characters');
            tc.verifyError(@() c.telegrambroadcast(), 'openalgo:missingArgument');
            tc.verifyNoRequest();
            c.telegrambroadcast(message="Markets open", filters=struct('broker', 'zz'));
            tc.verifySinglePost('telegram/broadcast', ['{"apikey":"test-api-key","message":"Markets open",' ...
                '"filters":{"broker":"zz"}}']);
            tc.Server.reset();
            c.telegrambroadcast(message=repmat('x', 1, 4096));
            r = tc.Server.lastRequest();
            tc.verifyEqual(r.body, ['{"apikey":"test-api-key","message":"' repmat('x', 1, 4096) '"}']);
        end
    end
end
