classdef DataTest < RestTestCase
    %DATATEST Market data methods, the history timetable and the
    %   instruments table.

    methods (Test)
        function quotesKwargsAsIs(tc)
            tc.respond('{"status":"success","data":{"ltp":750.5,"volume":100000,"oi":null}}');
            r = tc.Client.quotes(symbol="SBIN", exchange="NSE", extra=5, none=[]);
            tc.verifySinglePost('quotes', '{"apikey":"test-api-key","symbol":"SBIN","exchange":"NSE","extra":5}');
            tc.verifyEqual(r.data.ltp, 750.5);
            tc.verifyEqual(r.data.volume, 100000);
            tc.verifyEqual(r.data.oi, []);   % JSON null decodes to []
        end

        function depthAndSymbol(tc)
            tc.Client.depth(symbol="SBIN", exchange="NSE");
            tc.verifySinglePost('depth', '{"apikey":"test-api-key","symbol":"SBIN","exchange":"NSE"}');
            tc.Server.reset();
            tc.Client.symbol(symbol="NIFTY30DEC25FUT", exchange="NFO");
            tc.verifySinglePost('symbol', '{"apikey":"test-api-key","symbol":"NIFTY30DEC25FUT","exchange":"NFO"}');
            tc.verifyError(@() tc.Client.depth(symbol="SBIN"), 'openalgo:missingArgument');
        end

        function multiquotesAlwaysSendsAnArray(tc)
            expected = '{"apikey":"test-api-key","symbols":[{"symbol":"RELIANCE","exchange":"NSE"}]}';
            one = struct('symbol', 'RELIANCE', 'exchange', 'NSE');
            tc.Client.multiquotes(symbols=one);
            tc.verifySinglePost('multiquotes', expected);
            tc.Server.reset();
            tc.Client.multiquotes(symbols={one});
            tc.verifySinglePost('multiquotes', expected);
            tc.Server.reset();
            syms = struct('symbol', {'RELIANCE', 'NIFTY'}, 'exchange', {'NSE', 'NSE_INDEX'});
            tc.Client.multiquotes(symbols=syms);
            tc.verifySinglePost('multiquotes', ['{"apikey":"test-api-key","symbols":[' ...
                '{"symbol":"RELIANCE","exchange":"NSE"},{"symbol":"NIFTY","exchange":"NSE_INDEX"}]}']);
        end

        function oneElementResponseArrayDecodesToStruct(tc)
            % Documented difference: jsondecode turns a one-element array of
            % objects into a 1x1 struct (Python: a list of one dict).
            tc.respond('{"status":"success","results":[{"symbol":"RELIANCE","data":{"ltp":1}}]}');
            r = tc.Client.multiquotes(symbols={struct('symbol', 'RELIANCE', 'exchange', 'NSE')});
            tc.verifyClass(r.results, 'struct');
            tc.verifySize(r.results, [1 1]);
            tc.verifyEqual(r.results.symbol, 'RELIANCE');
        end

        function searchExchangeOnlyWhenGiven(tc)
            tc.Client.search(query="NIFTY", exchange="");
            tc.verifySinglePost('search', '{"apikey":"test-api-key","query":"NIFTY"}');
            tc.Server.reset();
            tc.Client.search(query="NIFTY");
            tc.verifySinglePost('search', '{"apikey":"test-api-key","query":"NIFTY"}');
            tc.Server.reset();
            tc.Client.search(query="NIFTY 26000 DEC CE", exchange="NFO", limit=10);
            tc.verifySinglePost('search', ['{"apikey":"test-api-key","query":"NIFTY 26000 DEC CE",' ...
                '"exchange":"NFO","limit":10}']);
        end

        function historyPayloadAndIntradayTimetable(tc)
            tc.respond(['{"status":"success","data":[' ...
                '{"timestamp":1735790400,"open":2,"high":3,"low":1,"close":2.5,"volume":200},' ...
                '{"timestamp":1735790100,"open":1,"high":2,"low":0.5,"close":1.5,"volume":100},' ...
                '{"timestamp":1735790400,"open":9,"high":9,"low":9,"close":9,"volume":9}]}']);
            tt = tc.Client.history(symbol="SBIN", exchange="NSE", interval="5m", ...
                start_date="2025-01-01", end_date="2025-01-10");
            tc.verifySinglePost('history', ['{"apikey":"test-api-key","symbol":"SBIN","exchange":"NSE",' ...
                '"interval":"5m","start_date":"2025-01-01","end_date":"2025-01-10","source":"api"}']);
            tc.assertClass(tt, 'timetable');
            % sorted by time, duplicate timestamp removed keeping the first
            tc.verifyEqual(height(tt), 2);
            tc.verifyEqual(tt.Properties.DimensionNames{1}, 'timestamp');
            tc.verifyEqual(tt.Properties.VariableNames, {'open', 'high', 'low', 'close', 'volume'});
            times = tt.Properties.RowTimes;
            % MATLAB reports the zone under its canonical alias Asia/Calcutta
            tc.verifyTrue(ismember(times.TimeZone, {'Asia/Kolkata', 'Asia/Calcutta'}), times.TimeZone);
            tc.verifyEqual(tzoffset(times(1)), hours(5.5));
            tc.verifyEqual(times(1), datetime(2025, 1, 2, 9, 25, 0, 'TimeZone', 'Asia/Kolkata'));
            tc.verifyEqual(times(2), datetime(2025, 1, 2, 9, 30, 0, 'TimeZone', 'Asia/Kolkata'));
            tc.verifyEqual(tt.close, [1.5; 2.5]);
            tc.verifyEqual(tt.volume, [100; 200]);
            tc.verifyEqual(char(times(1)), '2025-01-02 09:25:00+05:30');
        end

        function historyDailyIsZoneless(tc)
            % Python: tz-naive pandas timestamps with the UTC clock time
            tc.respond('{"status":"success","data":[{"timestamp":1735669800,"close":1}]}');
            tt = tc.Client.history(symbol="SBIN", exchange="NSE", interval="D", ...
                start_date="2025-01-01", end_date="2025-01-10", source="db");
            tc.verifySinglePost('history', ['{"apikey":"test-api-key","symbol":"SBIN","exchange":"NSE",' ...
                '"interval":"D","start_date":"2025-01-01","end_date":"2025-01-10","source":"db"}']);
            tc.assertClass(tt, 'timetable');
            times = tt.Properties.RowTimes;
            tc.verifyEqual(times.TimeZone, '');
            tc.verifyEqual(times, datetime(2024, 12, 31, 18, 30, 0));
            tc.verifyEqual(char(times), '2024-12-31 18:30:00');
            for iv = ["W", "M"]
                tc.respond('{"status":"success","data":[{"timestamp":0,"close":1}]}');
                tt = tc.Client.history(symbol="SBIN", exchange="NSE", interval=iv, ...
                    start_date="a", end_date="b");
                tc.verifyEqual(tt.Properties.RowTimes.TimeZone, '');
            end
            tc.respond('{"status":"success","data":[{"timestamp":0,"close":1}]}');
            tt = tc.Client.history(symbol="SBIN", exchange="NSE", interval="1h", start_date="a", end_date="b");
            tc.verifyEqual(tzoffset(tt.Properties.RowTimes), hours(5.5));
        end

        function historyErrors(tc)
            c = tc.Client;
            args = {'symbol', "SBIN", 'exchange', "NSE", 'interval', "5m", 'start_date', "a", 'end_date', "b"};
            tc.respond('{"status":"success","data":[]}');
            r = c.history(args{:});
            tc.verifyEqual(r, struct('status', 'error', ...
                'message', 'No data available for the specified period', 'error_type', 'no_data'));
            tc.respond('{"status":"success","data":[{"close":1}]}');
            r = c.history(args{:});
            tc.verifyErrorStruct(r, 'processing_error', 'Failed to process historical data: ''timestamp''');
            tc.verifyEqual(r.raw_data, struct('close', 1));
            tc.respond('{"status":"error","message":"Invalid symbol"}');
            r = c.history(args{:});
            tc.verifyEqual(r, struct('status', 'error', 'message', 'Invalid symbol', 'code', 200, ...
                'error_type', 'api_error'));
            tc.respond('{"status":"success"}');   % no data key: returned as is
            r = c.history(args{:});
            tc.verifyEqual(r, struct('status', 'success'));
        end

        function intervalsAndLegacyInterval(tc)
            tc.Client.intervals();
            tc.verifySinglePost('intervals', '{"apikey":"test-api-key"}');
            tc.Server.reset();
            tc.Client.interval();
            tc.verifySinglePost('intervals', '{"apikey":"test-api-key"}');
            tc.verifyError(@() tc.Client.interval(x=1), 'openalgo:unexpectedArgument');
        end

        function expiryAndSyntheticfuture(tc)
            tc.Client.expiry(symbol="NIFTY", exchange="NFO", instrumenttype="options");
            tc.verifySinglePost('expiry', ['{"apikey":"test-api-key","symbol":"NIFTY","exchange":"NFO",' ...
                '"instrumenttype":"options"}']);
            tc.Server.reset();
            tc.Client.syntheticfuture(underlying="NIFTY", exchange="NSE_INDEX", expiry_date="28NOV25");
            tc.verifySinglePost('syntheticfuture', ['{"apikey":"test-api-key","underlying":"NIFTY",' ...
                '"exchange":"NSE_INDEX","expiry_date":"28NOV25"}']);
        end

        function instrumentsSingleExchange(tc)
            tc.respond(['{"status":"success","data":[{"symbol":"SBIN","token":"3045","lotsize":1,' ...
                '"expiry":null},{"symbol":"M&M","token":"2031","lotsize":1,"expiry":null}]}']);
            T = tc.Client.instruments(exchange="NSE");
            tc.verifySingleGet('/api/v1/instruments', 'apikey=test-api-key&exchange=NSE');
            tc.assertClass(T, 'table');
            tc.verifyEqual(T.Properties.VariableNames, {'symbol', 'token', 'lotsize', 'expiry'});
            tc.verifyEqual(T.symbol, ["SBIN"; "M&M"]);
            tc.verifyEqual(T.lotsize, [1; 1]);
            tc.verifyEqual(height(T), 2);
        end

        function instrumentsSingleExchangeErrors(tc)
            c = tc.Client;
            tc.respond('{"status":"success","data":[]}');
            r = c.instruments(exchange="NSE");
            tc.verifyEqual(r, struct('status', 'error', ...
                'message', 'No instruments available for the specified exchange', 'error_type', 'no_data'));
            tc.respond('{"status":"error","message":"Invalid exchange"}');
            r = c.instruments(exchange="XYZ");
            tc.verifyErrorStruct(r, 'api_error', 'Invalid exchange');
            tc.respondText('Forbidden', 403);
            r = c.instruments(exchange="NSE");
            tc.verifyEqual(r, struct('status', 'error', 'message', 'HTTP 403: Forbidden', ...
                'code', 403, 'error_type', 'http_error'));
            dead = openalgo.api(api_key="k", host=tc.Server.ClosedUrl);
            r = dead.instruments(exchange="NSE");
            tc.verifyErrorStruct(r, 'connection_error');
            tc.verifyError(@() c.instruments("NSE"), 'openalgo:invalidArguments');
            tc.verifyError(@() c.instruments(exchange="NSE", x=1), 'openalgo:unexpectedArgument');
        end

        function instrumentsAllExchangesSkipsFailures(tc)
            tc.respond('{"status":"success","data":[{"symbol":"A","lotsize":1}]}');   % NSE
            tc.respondText('x', 500);                                                % BSE
            tc.respond('{"status":"error","message":"no"}');                          % NFO
            tc.respond('{"status":"success","data":[]}');                             % BFO
            tc.respond('{"status":"success","data":[{"symbol":"B","expiry":"x"}]}');  % MCX
            tc.respondText('bad');                                                   % CDS
            tc.respond('[1]');                                                       % BCD
            tc.respond('{"status":"success"}');                                       % NSE_INDEX
            tc.respond('{"status":"success","data":[{"symbol":"C","lotsize":2.5}]}'); % BSE_INDEX
            T = tc.Client.instruments();
            reqs = tc.Server.requests();
            exchanges = {'NSE', 'BSE', 'NFO', 'BFO', 'MCX', 'CDS', 'BCD', 'NSE_INDEX', 'BSE_INDEX'};
            tc.assertNumElements(reqs, numel(exchanges));
            for i = 1:numel(exchanges)
                tc.verifyEqual(reqs{i}.method, 'GET');
                tc.verifyEqual(reqs{i}.path, '/api/v1/instruments');
                tc.verifyEqual(reqs{i}.raw_query, ['apikey=test-api-key&exchange=' exchanges{i}]);
            end
            tc.assertClass(T, 'table');
            tc.verifyEqual(T.Properties.VariableNames, {'symbol', 'lotsize', 'expiry'});
            tc.verifyEqual(T.symbol, ["A"; "B"; "C"]);
            tc.verifyEqual(T.lotsize, [1; NaN; 2.5]);
            tc.verifyEqual(T.expiry, [missing; "x"; missing]);
        end

        function instrumentsAllExchangesFail(tc)
            for i = 1:9
                tc.respondText('x', 500);
            end
            r = tc.Client.instruments();
            tc.verifyEqual(r, struct('status', 'error', ...
                'message', 'Failed to fetch instruments from any exchange', 'error_type', 'no_data'));
            tc.verifyNumElements(tc.Server.requests(), 9);
            dead = openalgo.api(api_key="k", host=tc.Server.ClosedUrl);
            r = dead.instruments();
            tc.verifyErrorStruct(r, 'no_data', 'Failed to fetch instruments from any exchange');
        end
    end
end
