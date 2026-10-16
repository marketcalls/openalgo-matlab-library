classdef FeedAPITest < matlab.unittest.TestCase
    %FEEDAPITEST Tests for openalgo.FeedAPI and the WebSocket client.
    %   The tests start tests/support/mock_ws_server.py (a mock of the
    %   OpenAlgo WebSocket proxy) and drive it through FeedTestClient, a
    %   minimal subclass of openalgo.FeedAPI, so openalgo.api is not needed.
    %
    %   Run from the repository folder:
    %       results = runtests('tests/FeedAPITest.m'); disp(table(results))
    %
    %   The mock server needs Python 3 with the websockets package. The
    %   interpreter is 'python' on the PATH unless OPENALGO_TEST_PYTHON
    %   names another one.
    %   Temporary files (certificates, frame record, server log) go to
    %   OPENALGO_TEST_TMP when set, else tempdir, and are removed afterwards.
    %
    %   The feed scenarios run once per transport (test parameter
    %   Transport): ws (tcpclient) and wss over the .NET, Python interface
    %   and Java TLS transports. The mock server makes a test CA at start-up
    %   and serves wss:// with a certificate it signed for localhost and
    %   127.0.0.1. The wss clients keep certificate verification on and
    %   trust that CA through tls_ca_file. Further tests check that the
    %   default trust store rejects the certificate, that an unrelated CA
    %   file does too, that a certificate for another host name is refused
    %   even though its CA is trusted, and that tls_verify = false (not
    %   possible with Java) accepts it. A transport that is not available in
    %   the session is skipped (the test is marked incomplete by an
    %   assumption). For the Python transport the
    %   tests configure pyenv when Python is not loaded yet: the
    %   interpreter in OPENALGO_TEST_PYENV, else a supported default, else a
    %   Python 3.13 or 3.12 found in the usual Windows locations.

    properties (Constant)
        ApiKey = 'mock-api-key-0123456789abcdef'
    end

    properties
        WorkDir = ''
        RecordFile = ''
        ReadyFile = ''
        PidFile = ''
        LogFile = ''
        Url = ''
        TlsUrl = ''
        WrongNameUrl = ''
        TlsDir = ''
        PythonReady = false
    end

    properties (TestParameter)
        Transport = struct('ws', 'ws', 'wss_dotnet', 'dotnet', 'wss_python', 'python', 'wss_java', 'java')
        TlsTransport = struct('dotnet', 'dotnet', 'python', 'python', 'java', 'java')
    end

    %% Setup and teardown

    methods (TestClassSetup)
        function startServer(tc)
            here = fileparts(mfilename('fullpath'));
            root = fileparts(here);
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(root));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(here, 'support')));
            tc.addTeardown(@FeedAPITest.cleanupTimers);

            base = getenv('OPENALGO_TEST_TMP');
            if isempty(base)
                base = tempdir;
            end
            [~, name] = fileparts(tempname);
            tc.WorkDir = fullfile(base, ['feedtest_' name]);
            mkdir(tc.WorkDir);
            tc.TlsDir = fullfile(tc.WorkDir, 'tls');
            tc.addTeardown(@() FeedAPITest.removeDir(tc.WorkDir));
            tc.RecordFile = fullfile(tc.WorkDir, 'frames.jsonl');
            tc.ReadyFile = fullfile(tc.WorkDir, 'ready.txt');
            tc.PidFile = fullfile(tc.WorkDir, 'server.pid');
            tc.LogFile = fullfile(tc.WorkDir, 'server.log');

            py = getenv('OPENALGO_TEST_PYTHON');
            if isempty(py)
                py = 'python';
            end
            script = fullfile(here, 'support', 'mock_ws_server.py');
            args = {py, '-u', script, '--port', '0', '--ready-file', tc.ReadyFile, ...
                '--pid-file', tc.PidFile, '--record', tc.RecordFile, ...
                '--api-key', tc.ApiKey, '--lifetime', '1800', ...
                '--tls-port', '0', '--tls-dir', tc.TlsDir};
            proc = FeedAPITest.launch(args, tc.LogFile);
            tc.addTeardown(@FeedAPITest.stopServer, proc, tc.ReadyFile, tc.PidFile);

            started = tic;
            while ~isfile(tc.ReadyFile) && toc(started) < 30
                pause(0.1);
            end
            tc.assertTrue(isfile(tc.ReadyFile), sprintf('Mock server did not start. Log:\n%s', ...
                FeedAPITest.readText(tc.LogFile)));
            ports = str2double(splitlines(strtrim(fileread(tc.ReadyFile))));
            tc.Url = sprintf('ws://127.0.0.1:%d', ports(1));
            if numel(ports) >= 3 && ports(2) > 0
                tc.TlsUrl = sprintf('wss://127.0.0.1:%d', ports(2));
                tc.WrongNameUrl = sprintf('wss://127.0.0.1:%d', ports(3));
            end
            tc.PythonReady = FeedAPITest.preparePython();
        end
    end

    methods (TestMethodSetup)
        function resetRecord(tc)
            for k = 1:50
                if ~isfile(tc.RecordFile)
                    break
                end
                warnState = warning('off', 'all');
                try
                    delete(tc.RecordFile);
                catch
                end
                warning(warnState);
                if isfile(tc.RecordFile)
                    pause(0.05);
                end
            end
        end
    end

    %% Tests that need no server

    methods (Test)
        function testWsUrlDerivationAndDefaults(tc)
            c = FeedTestClient('k');
            tc.verifyEqual(c.ws_url, 'ws://127.0.0.1:8765');
            tc.verifyEqual(c.ws_host, '127.0.0.1');
            tc.verifyEqual(c.ws_port, 8765);
            tc.verifyEqual(c.verbose, 0);
            tc.verifyTrue(c.auto_reconnect);
            tc.verifyEmpty(c.ws);
            tc.verifyFalse(c.connected);
            tc.verifyFalse(c.authenticated);
            tc.verifyClass(c.ltp_data, 'containers.Map');
            tc.verifyEqual(c.ltp_data.Count, uint64(0));
            tc.verifyEqual(c.order_data, {});
            tc.verifyEqual(numel(c.active_subs), 3);

            % https:// hosts (server hosted OpenAlgo) use wss://HOST[:PORT]/ws
            c.reinit('https://example.com:5000/api/v1', 9000);
            tc.verifyEqual(c.ws_url, 'wss://example.com:5000/ws');
            tc.verifyEqual(c.ws_host, 'example.com');
            c.reinit('https://algo.example.com', 8765);
            tc.verifyEqual(c.ws_url, 'wss://algo.example.com/ws');
            c.reinit('https://sub.example.com/', 8765);
            tc.verifyEqual(c.ws_url, 'wss://sub.example.com/ws');

            c.reinit('http://example.com:5000/api/v1', 9000);
            tc.verifyEqual(c.ws_url, 'ws://example.com:9000');
            tc.verifyEqual(c.ws_host, 'example.com');

            c.reinit('http://10.0.0.5:5000', 8765);
            tc.verifyEqual(c.ws_url, 'ws://10.0.0.5:8765');

            c.reinit('myhost/some/path', 8000);
            tc.verifyEqual(c.ws_url, 'ws://myhost:8000');

            c.reinit("http://127.0.0.1:5000", 8765, "wss://feed.example.com/ws");
            tc.verifyEqual(c.ws_url, 'wss://feed.example.com/ws');

            c.reinit([], [], '', true);
            tc.verifyEqual(c.ws_url, 'ws://127.0.0.1:8765');
            tc.verifyEqual(c.verbose, 1);
            c.reinit([], [], [], 2);
            tc.verifyEqual(c.verbose, 2);
            c.reinit([], [], [], false, false);
            tc.verifyEqual(c.verbose, 0);
            tc.verifyFalse(c.auto_reconnect);
        end

        function testSha1AndAcceptKey(tc)
            WS = 'openalgo.internal.WebSocketClient';
            hex = @(b) lower(reshape(dec2hex(b, 2).', 1, []));
            sha = @(t) hex(feval([WS '.sha1Matlab'], uint8(t)));
            tc.verifyEqual(sha('abc'), 'a9993e364706816aba3e25717850c26c9cd0d89d');
            tc.verifyEqual(sha(''), 'da39a3ee5e6b4b0d3255bfef95601890afd80709');
            tc.verifyEqual(sha('abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq'), ...
                '84983e441c3bd26ebaae4aa1f95129e5e54670f1');
            tc.verifyEqual(sha(repmat('a', 1, 1000)), '291e9a6c66994949b57ba5e650361e98fc36b1ba');
            % RFC 6455 section 1.3 example
            tc.verifyEqual(openalgo.internal.WebSocketClient.acceptKey('dGhlIHNhbXBsZSBub25jZQ=='), ...
                's3pPLMBiTxaQ9kYGzzhZRbK+xOo=');
            bytes = uint8(0:255);
            tc.verifyEqual(openalgo.internal.WebSocketClient.sha1(bytes), ...
                openalgo.internal.WebSocketClient.sha1Matlab(bytes));
        end

        function testBadUrlAndTransportOptions(tc)
            tc.verifyError(@() openalgo.internal.WebSocketClient('http://x:1'), ...
                'openalgo:WebSocketClient:badUrl');
            w = openalgo.internal.WebSocketClient('wss://127.0.0.1:1', 'TlsTransport', 'carrier-pigeon');
            tc.verifyError(@() w.open(1), 'openalgo:WebSocketClient:badOption');
            if ~usejava('jvm')
                w = openalgo.internal.WebSocketClient('wss://127.0.0.1:1', 'TlsTransport', 'java');
                tc.verifyError(@() w.open(1), 'openalgo:WebSocketClient:transportUnavailable');
                tc.verifyTrue(w.isClosed());
            end
            w = openalgo.internal.WebSocketClient('wss://127.0.0.1:1', 'CaFile', 'no-such-file.pem');
            tc.verifyError(@() w.open(1), 'openalgo:WebSocketClient:badOption');
            w = openalgo.internal.WebSocketClient('wss://127.0.0.1:1');
            tc.verifyTrue(w.VerifyCertificate);   % verification is on by default
            tc.verifyEqual(w.TlsTransport, 'auto');
            tc.verifyEqual(w.CaFile, '');
            c = FeedTestClient('k');
            tc.verifyTrue(c.tls_verify);
            tc.verifyEqual(c.tls_transport, 'auto');
            tc.verifyEqual(c.tls_ca_file, '');
        end

        function testGuardsWhenNotConnected(tc)
            c = FeedTestClient('k', [], [], tc.urlOrDefault(), 1, false);
            ins = {struct('exchange', 'NSE', 'symbol', 'INFY')};
            ok = true;
            out = evalc('ok = c.subscribe_ltp(ins);');
            tc.verifyFalse(ok);
            tc.verifyEqual(out, sprintf('[ERROR]  Not connected to WebSocket server\n'));
            out = evalc('ok = c.subscribe_quote(ins);');
            tc.verifyFalse(ok);
            tc.verifySubstring(out, 'Not connected to WebSocket server');
            out = evalc('ok = c.subscribe_depth(ins);');
            tc.verifyFalse(ok);
            tc.verifySubstring(out, 'Not connected to WebSocket server');
            out = evalc('ok = c.subscribe_orders();');
            tc.verifyFalse(ok);
            tc.verifySubstring(out, 'Not connected to WebSocket server');

            out = evalc('ok = c.unsubscribe_ltp(ins);');
            tc.verifyFalse(ok);
            tc.verifyEmpty(out);
            tc.verifyFalse(c.unsubscribe_quote(ins));
            tc.verifyFalse(c.unsubscribe_depth(ins));
            tc.verifyFalse(c.unsubscribe_orders());

            c.connected = true;
            out = evalc('ok = c.subscribe_ltp(ins);');
            tc.verifyFalse(ok);
            tc.verifySubstring(out, '[ERROR]  Not authenticated with WebSocket server');
            out = evalc('ok = c.subscribe_orders(@disp);');
            tc.verifyFalse(ok);
            tc.verifySubstring(out, 'Not authenticated with WebSocket server');
            tc.verifyFalse(c.unsubscribe_ltp(ins));
            c.connected = false;

            tc.verifyEqual(c.get_ltp(), struct('ltp', struct()));
            tc.verifyEqual(c.get_quotes(), struct('quote', struct()));
            tc.verifyEqual(c.get_depth(), struct('depth', struct()));
            tc.verifyEqual(c.get_orders(), struct('orders', {{}}));
            tc.verifyEmpty(c.active_subs{1}.entries);
        end

        function testArgumentParsing(tc)
            c = FeedTestClient('k');
            tc.verifyError(@() c.subscribe_ltp(), 'openalgo:FeedAPI:missingArgument');
            tc.verifyError(@() c.get_ltp('NSE', 'A', 'extra'), 'openalgo:FeedAPI:badArgument');
            tc.verifyError(@() c.get_ltp('NSE', 'bogus', 1), 'openalgo:FeedAPI:badArgument');
            c.feedProcessMessage('{"type":"market_data","symbol":"A","exchange":"NSE","mode":1,"data":{"ltp":1,"timestamp":5}}');
            c.feedProcessMessage('{"type":"market_data","symbol":"B","exchange":"BSE","mode":1,"data":{"ltp":2,"timestamp":6}}');
            r = c.get_ltp(exchange="NSE");
            tc.verifyEqual(fieldnames(r.ltp), {'NSE'});
            r = c.get_ltp('exchange', 'BSE', 'symbol', 'B');
            tc.verifyEqual(r.ltp.BSE.B.ltp, 2);
            r = c.get_ltp('BSE', symbol="A");
            tc.verifyEqual(r, struct('ltp', struct()));
            r = c.get_ltp('NSE');
            tc.verifyEqual(r.ltp.NSE.A, struct('timestamp', 5, 'ltp', 1));
        end

        function testProcessMessageDirect(tc)
            c = FeedTestClient('k', [], [], [], 2, false);
            cap = LogCapture();
            c.log_sink = @(line) cap.add(line);
            store = containers.Map();

            % Invalid JSON, truncated to 100 characters
            c.feedProcessMessage('not json {');
            tc.verifyEqual(cap.Lines{end}, '[ERROR]  Invalid JSON message: not json {...');
            long = repmat('z', 1, 150);
            c.feedProcessMessage(long);
            tc.verifyEqual(cap.Lines{end}, ['[ERROR]  Invalid JSON message: ' repmat('z', 1, 100) '...']);

            % Valid JSON that is not an object
            c.feedProcessMessage('123');
            tc.verifyEqual(cap.Lines{end}, '[ERROR]  Error handling message: ''int'' object has no attribute ''get''');

            % Auth success and failure
            cap.clear();
            c.feedProcessMessage('{"type":"auth","status":"success","broker":"b1","user_id":"u1"}');
            tc.verifyTrue(c.authenticated);
            tc.verifyEqual(cap.Lines{1}, '[AUTH]   Success | Broker: b1 | User: u1');
            tc.verifyEqual(cap.Lines{2}, ...
                '[AUTH]   Full response: {''type'': ''auth'', ''status'': ''success'', ''broker'': ''b1'', ''user_id'': ''u1''}');
            c.feedProcessMessage('{"type":"auth","status":"success"}');
            tc.verifyTrue(cap.has('Success | Broker: unknown | User: unknown'));
            c.feedProcessMessage('{"type":"auth","status":"error","message":"bad key"}');
            tc.verifyEqual(cap.Lines{end}, '[ERROR]  Authentication failed: bad key');
            c.feedProcessMessage('{"type":"auth","status":"error"}');
            tc.verifyEqual(cap.Lines{end}, '[ERROR]  Authentication failed: Unknown error');

            % Subscribe and order acks
            cap.clear();
            c.feedProcessMessage(['{"type":"subscribe","status":"partial","subscriptions":[' ...
                '{"symbol":"INFY","exchange":"NSE","status":"success","mode":1},' ...
                '{"symbol":"SBIN","exchange":"NSE","status":"success","mode":"depth"},' ...
                '{"symbol":"TCS","exchange":"NSE","status":"error","message":"Depth level 50 is not supported by this broker"},' ...
                '{"symbol":"X","exchange":"NSE","status":"success","mode":"Bogus"}]}']);
            tc.verifyEqual(cap.Lines{1}, '[SUB]    NSE:INFY | Mode: LTP | Status: success');
            tc.verifyEqual(cap.Lines{2}, '[SUB]    NSE:SBIN | Mode: Depth | Status: success');
            tc.verifyEqual(cap.Lines{3}, '[SUB]    NSE:TCS | Mode: Unknown | Status: error');
            tc.verifyEqual(cap.Lines{4}, ...
                '[ERROR]  Subscription failed for NSE:TCS: Depth level 50 is not supported by this broker');
            tc.verifyEqual(cap.Lines{5}, '[SUB]    NSE:X | Mode: Unknown | Status: success');
            tc.verifySubstring(cap.Lines{6}, '[SUB]    Full response: {''type'': ''subscribe''');

            % Unsubscribe acknowledgement (successful and failed items)
            cap.clear();
            c.feedProcessMessage(['{"type":"unsubscribe","status":"partial","successful":[' ...
                '{"symbol":"RELIANCE","exchange":"NSE","mode":"Quote","status":"success"}],' ...
                '"failed":[{"symbol":"A","exchange":"NSE","mode":null,"status":"error","message":"Invalid mode"}]}']);
            tc.verifyEqual(cap.Lines{1}, '[UNSUB]  NSE:RELIANCE | Mode: Quote | Status: success');
            tc.verifyEqual(cap.Lines{2}, '[ERROR]  Unsubscribe failed for NSE:A | Mode: Unknown: Invalid mode');
            tc.verifySubstring(cap.Lines{3}, '[UNSUB]  Full response: {''type'': ''unsubscribe''');

            % Server errors, with and without a type field
            cap.clear();
            c.feedProcessMessage('{"status":"error","code":"INVALID_ACTION","message":"Invalid action: bogus"}');
            tc.verifyEqual(cap.Lines{end}, '[ERROR]  Server error INVALID_ACTION: Invalid action: bogus');
            c.feedProcessMessage('{"type":"error","message":"Something broke"}');
            tc.verifyEqual(cap.Lines{end}, '[ERROR]  Server error: Something broke');
            c.feedProcessMessage('{"type":"subscribe_orders","status":"success"}');
            tc.verifyTrue(cap.has('[SUB]    Order updates | subscribe_orders | Status: success'));
            c.feedProcessMessage('{"type":"unsubscribe_orders"}');
            tc.verifyTrue(cap.has('[SUB]    Order updates | unsubscribe_orders | Status: ?'));

            % LTP with ltt nested under data.data and a default timestamp
            cap.clear();
            c.ltp_callback = @(d) FeedAPITest.collect(store, 'ltp', d);
            before = floor(posixtime(datetime('now', 'TimeZone', 'UTC')) * 1000);
            c.feedProcessMessage('{"type":"market_data","symbol":"A","exchange":"NSE","mode":1,"data":{"ltp":10.5,"data":{"ltt":42}}}');
            after = floor(posixtime(datetime('now', 'TimeZone', 'UTC')) * 1000);
            rec = c.ltp_data('NSE:A');
            tc.verifyEqual(rec.price, 10.5);
            tc.verifyGreaterThanOrEqual(rec.timestamp, before);
            tc.verifyLessThanOrEqual(rec.timestamp, after);
            tc.verifyEqual(cap.Lines{1}, sprintf('%-8s %-20s | LTP: 10.5', '[LTP]', 'NSE:A'));
            d = store('ltp');
            d = d{end};
            tc.verifyEqual(fieldnames(d), {'type'; 'symbol'; 'exchange'; 'mode'; 'data'});
            tc.verifyEqual(d.type, 'market_data');
            tc.verifyEqual(d.mode, 1);
            tc.verifyEqual(d.data.ltt, 42);
            tc.verifyEqual(fieldnames(d.data), {'ltp'; 'timestamp'; 'ltt'});

            % Mode 1 without ltp, and messages without symbol, are ignored
            n = c.ltp_data.Count;
            c.feedProcessMessage('{"type":"market_data","symbol":"B","exchange":"NSE","mode":1,"data":{"open":1}}');
            c.feedProcessMessage('{"type":"market_data","exchange":"NSE","mode":1,"data":{"ltp":1}}');
            c.feedProcessMessage('{"type":"market_data","symbol":"","exchange":"NSE","mode":1,"data":{"ltp":1}}');
            tc.verifyEqual(c.ltp_data.Count, n);

            % Callback errors are caught and logged
            c.ltp_callback = @(d) error('boom');
            c.feedProcessMessage('{"type":"market_data","symbol":"A","exchange":"NSE","mode":1,"data":{"ltp":11,"timestamp":1}}');
            tc.verifyEqual(cap.Lines{end}, '[ERROR]  LTP callback error: boom');
            tc.verifyEqual(c.ltp_data('NSE:A').price, 11);
            c.quote_callback = @(d) error('qboom');
            c.feedProcessMessage('{"type":"market_data","symbol":"Q","exchange":"NSE","mode":2,"data":{}}');
            tc.verifyEqual(cap.Lines{end}, '[ERROR]  Quote callback error: qboom');
            c.depth_callback = @(d) error('dboom');
            c.feedProcessMessage('{"type":"market_data","symbol":"D","exchange":"NSE","mode":3,"data":{"depth":{}}}');
            tc.verifyEqual(cap.Lines{end}, '[ERROR]  Depth callback error: dboom');

            % Quote with missing fields defaults to 0, timestamp to now
            q = c.quotes_data('NSE:Q');
            tc.verifyEqual(fieldnames(q), {'open'; 'high'; 'low'; 'close'; 'ltp'; 'volume'; ...
                'last_trade_quantity'; 'avg_trade_price'; 'change'; 'change_percent'; 'timestamp'});
            tc.verifyEqual(q.open, 0);
            tc.verifyEqual(q.change_percent, 0);
            tc.verifyGreaterThan(q.timestamp, 1.6e12);

            % Depth: empty and partial books, strings and nulls
            r = c.get_depth('NSE', 'D');
            tc.verifyEqual(r.depth.NSE.D.buyBook, repmat(struct('price', 0, 'qty', 0, 'orders', 0), 1, 5));
            tc.verifyEqual(r.depth.NSE.D.sellBook, repmat(struct('price', 0, 'qty', 0, 'orders', 0), 1, 5));
            cap.clear();
            c.depth_callback = [];
            c.feedProcessMessage(['{"type":"market_data","symbol":"E","exchange":"NSE","mode":3,"data":{"ltp":5,"timestamp":9,' ...
                '"depth":{"buy":[{"price":null,"quantity":"7","orders":2},{"price":"4.5"}],"sell":[]}}}']);
            r = c.get_depth('NSE', 'E');
            book = r.depth.NSE.E.buyBook;
            tc.verifySize(book, [1 5]);
            tc.verifyEqual(book(1), struct('price', 0, 'qty', 7, 'orders', 2));
            tc.verifyEqual(book(2), struct('price', 4.5, 'qty', 0, 'orders', 0));
            tc.verifyEqual(r.depth.NSE.E.ltp, 5);
            tc.verifyEqual(r.depth.NSE.E.timestamp, 9);
            % Verbose 2 depth table
            tc.verifyEqual(cap.Lines{1}, sprintf('%-8s %-20s | LTP: 5', '[DEPTH]', 'NSE:E'));
            tc.verifyEqual(cap.Lines{2}, sprintf('         %-30s | %-30s', 'BUY', 'SELL'));
            tc.verifyEqual(cap.Lines{4}, ['         ' repmat('-', 1, 62)]);
            tc.verifyEqual(cap.Lines{5}, sprintf('         %-10s %-10s %-8s | %-10s %-10s %-8s', 'None', '7', '2', '-', '-', '-'));
            tc.verifyEqual(cap.Lines{6}, sprintf('         %-10s %-10s %-8s | %-10s %-10s %-8s', '4.5', '-', '-', '-', '-', '-'));

            % Symbol names that are not valid MATLAB identifiers
            c.feedProcessMessage('{"type":"market_data","symbol":"M&M","exchange":"NSE","mode":1,"data":{"ltp":3,"timestamp":2}}');
            c.feedProcessMessage('{"type":"market_data","symbol":"BAJAJ-AUTO","exchange":"NSE","mode":1,"data":{"ltp":4,"timestamp":2}}');
            r = c.get_ltp('NSE');
            tc.verifyEqual(r.ltp.NSE.M_M.ltp, 3);
            tc.verifyEqual(r.ltp.NSE.BAJAJ_AUTO.ltp, 4);
            r = c.get_ltp('NSE', 'M&M');
            tc.verifyEqual(fieldnames(r.ltp.NSE), {'M_M'});
            tc.verifyTrue(c.ltp_data.isKey('NSE:M&M'));
        end

        function testOrderHistoryCap(tc)
            c = FeedTestClient('k');
            for i = 1:505
                c.feedProcessMessage(sprintf('{"type":"order_update","orderid":"ID%d","order_status":"open"}', i));
            end
            r = c.get_orders();
            tc.verifyEqual(numel(r.orders), 500);
            tc.verifyEqual(r.orders{1}.orderid, 'ID505');
            tc.verifyEqual(r.orders{end}.orderid, 'ID6');

            cap = LogCapture();
            c.log_sink = @(line) cap.add(line);
            c.verbose = 2;
            c.feedProcessMessage(['{"type":"order_update","orderid":"X1","symbol":"SBIN","order_status":"complete",' ...
                '"filled_quantity":5,"quantity":10,"average_price":101.25}']);
            tc.verifyEqual(cap.Lines{end}, sprintf('%-8s %-20s | %-10s | Qty: 5/10 | Avg: 101.25 | ID: X1', ...
                '[ORDER]', 'SBIN', 'complete'));
        end
    end

    %% Tests against the mock server

    methods (Test)
        function testConnectAndAuthenticate(tc, Transport)
            [c, cap] = tc.newClient(Transport);
            ok = false;
            out = evalc('ok = c.connect();');
            tc.verifyTrue(ok);
            tc.verifyTrue(c.connected);
            tc.verifyTrue(c.authenticated);
            tc.verifyClass(c.ws, 'openalgo.internal.WebSocketClient');
            tc.verifyEmpty(out);  % logs go to the sink
            tc.verifyTrue(cap.has(['[WS]     Connected to ' c.ws_url]));
            tc.verifyTrue(cap.has('[AUTH]   Authenticating with API key: mock-api...89abcdef'));
            tc.verifyTrue(cap.has('[AUTH]   Success | Broker: mockbroker | User: mockuser'));
            frames = tc.waitFrames(c, 0, 1);
            tc.verifyEqual(frames{1}, ['{"action":"authenticate","api_key":"' tc.ApiKey '"}']);
        end

        function testLogFormatOnStdout(tc)
            c = FeedTestClient(tc.ApiKey, [], [], tc.Url, 1, false);
            tc.addTeardown(@FeedAPITest.destroyClient, c);
            out = evalc('c.connect();');
            tc.verifySubstring(out, sprintf('[WS]     Connected to %s\n', tc.Url));
            tc.verifySubstring(out, sprintf('[AUTH]   Authenticating with API key: mock-api...89abcdef\n'));
        end

        function testAuthenticationFailure(tc)
            [c, cap] = tc.newClient('ws', 'Key', 'wrong-key-123456789');
            started = tic;
            ok = c.connect();
            tc.verifyFalse(ok);
            tc.verifyGreaterThan(toc(started), 4.5);   % waits the full 5 s
            tc.verifyFalse(c.authenticated);
            tc.verifyTrue(c.connected);
            tc.verifyTrue(cap.has('[ERROR]  Authentication failed: Invalid API key'));
            tc.verifyTrue(cap.has('Authenticating with API key: wrong-ke...23456789'));
        end

        function testRequestGuardsAndTimeout(tc)
            [c, cap] = tc.newClient('ws');
            r = c.get_broker_info();
            tc.verifyEqual(r, struct('status', 'error', 'message', 'Not connected to WebSocket server'));
            r = c.ws_ping(1);
            tc.verifyEqual(r.status, 'error');
            r = c.get_supported_brokers();
            tc.verifyEqual(r.status, 'error');
            tc.verifyFalse(c.unsubscribe_all());
            tc.verifyTrue(cap.has('[ERROR]  Not connected to WebSocket server'));

            tc.assertTrue(c.connect());
            tc.mock(c, 'silence', struct('count', 1));
            started = tic;
            r = c.get_broker_info(timeout=0.5);
            tc.verifyLessThan(toc(started), 3);
            tc.verifyEqual(r.status, 'error');
            tc.verifyEqual(r.message, 'Timed out waiting for the broker_info reply');
            tc.verifyTrue(cap.has('[ERROR]  Timed out waiting for the broker_info reply'));
            tc.verifyEmpty(c.pending_replies);
            r = c.get_broker_info();   % the next request is answered again
            tc.verifyEqual(r.broker, 'mockbroker');
        end

        function testConnectFailure(tc)
            [c, cap] = tc.newClient('ws', 'Url', 'ws://127.0.0.1:1');
            ok = c.connect();
            tc.verifyFalse(ok);
            tc.verifyFalse(c.connected);
            tc.verifyTrue(cap.has('[ERROR]  WebSocket error: '));
            tc.verifyTrue(cap.has('[WS]     Disconnected from ws://127.0.0.1:1'));
            tc.verifyEqual(cap.Lines{end}, '[ERROR]  Failed to connect to WebSocket server');
            tc.verifyFalse(cap.has('Reconnect attempt'));

            % With auto_reconnect the failed connect arms the reconnect loop
            [c2, cap2] = tc.newClient('ws', 'Url', 'ws://127.0.0.1:1', 'AutoReconnect', true);
            tc.verifyFalse(c2.connect());
            tc.verifyTrue(cap2.has('[WS]     Reconnect attempt 1 in 1s...'));
            tc.verifyTrue(c2.reconnect_active);
            c2.disconnect();
            tc.verifyFalse(c2.reconnect_active);
            tc.verifyEmpty(c2.reconnect_timer);
            cap2.clear();
            c2.wait(1.5);
            tc.verifyFalse(cap2.has('Reconnect attempt'));
        end

        function testSubscribeLtp(tc, Transport)
            [c, cap] = tc.connectedClient(Transport);
            store = containers.Map();
            cb = @(d) FeedAPITest.collect(store, 'ltp', d);
            ins = {struct('exchange', 'NSE', 'symbol', 'RELIANCE')};
            tc.verifyTrue(c.subscribe_ltp(ins, cb));
            tc.verifyTrue(cap.has('[SUB]    Subscribing NSE:RELIANCE LTP...'));
            tc.verifyTrue(tc.waitUntil(c, @() c.ltp_data.isKey('NSE:RELIANCE') && store.isKey('ltp'), 5));
            tc.verifyTrue(cap.has('[SUB]    NSE:RELIANCE | Mode: LTP | Status: success'));

            frames = tc.waitFrames(c, 0, 2);
            tc.verifyEqual(frames{2}, '{"action":"subscribe","symbols":[{"symbol":"RELIANCE","exchange":"NSE"}],"mode":1,"depth":5}');

            rec = c.ltp_data('NSE:RELIANCE');
            tc.verifyEqual(rec, struct('price', 1234.5, 'timestamp', 1700000000123));
            r = c.get_ltp();
            tc.verifyEqual(fieldnames(r), {'ltp'});
            tc.verifyEqual(r.ltp.NSE.RELIANCE, struct('timestamp', 1700000000123, 'ltp', 1234.5));
            tc.verifyEqual(c.get_ltp('NSE', 'RELIANCE'), r);
            tc.verifyEqual(c.get_ltp('BSE'), struct('ltp', struct()));

            d = store('ltp');
            d = d{1};
            tc.verifyEqual(d.type, 'market_data');
            tc.verifyEqual(d.symbol, 'RELIANCE');
            tc.verifyEqual(d.exchange, 'NSE');
            tc.verifyEqual(d.mode, 1);
            tc.verifyEqual(d.data, struct('ltp', 1234.5, 'timestamp', 1700000000123, 'ltt', 1700000000));

            % Struct array input, several symbols in one frame, name=value callback
            tc.verifyTrue(c.subscribe_ltp(struct('exchange', {'NSE', 'NSE'}, 'symbol', {'INFY', 'TCS'}), ...
                on_data_received=cb));
            frames = tc.waitFrames(c, 0, 3);
            tc.verifyEqual(frames{3}, ['{"action":"subscribe","symbols":[{"symbol":"INFY","exchange":"NSE"},' ...
                '{"symbol":"TCS","exchange":"NSE"}],"mode":1,"depth":5}']);
            tc.verifyTrue(tc.waitUntil(c, @() c.ltp_data.Count == 3, 5));
            tc.verifyEqual(numel(c.active_subs{1}.entries), 3);
        end

        function testSubscribeQuote(tc, Transport)
            [c, ~] = tc.connectedClient(Transport);
            store = containers.Map();
            ins = {struct('exchange', 'NSE', 'symbol', 'TCS')};
            tc.verifyTrue(c.subscribe_quote(ins, @(d) FeedAPITest.collect(store, 'q', d)));
            tc.verifyTrue(tc.waitUntil(c, @() c.quotes_data.isKey('NSE:TCS') && store.isKey('q'), 5));
            frames = tc.waitFrames(c, 0, 2);
            tc.verifyEqual(frames{2}, '{"action":"subscribe","symbols":[{"symbol":"TCS","exchange":"NSE"}],"mode":2,"depth":5}');

            r = c.get_quotes();
            q = r.quote.NSE.TCS;
            tc.verifyEqual(fieldnames(q), {'timestamp'; 'open'; 'high'; 'low'; 'close'; 'ltp'; 'volume'; ...
                'last_trade_quantity'; 'avg_trade_price'; 'change'; 'change_percent'});
            tc.verifyEqual(q.timestamp, 1700000000234);
            tc.verifyEqual(q.open, 100.5);
            tc.verifyEqual(q.high, 110.25);
            tc.verifyEqual(q.low, 95.75);
            tc.verifyEqual(q.close, 99.5);
            tc.verifyEqual(q.ltp, 105.25);
            tc.verifyEqual(q.volume, 123456);
            tc.verifyEqual(q.last_trade_quantity, 10);
            tc.verifyEqual(q.avg_trade_price, 104.1);
            tc.verifyEqual(q.change, 5.75);
            tc.verifyEqual(q.change_percent, 5.78);
            tc.verifyEqual(c.get_quotes(exchange='NSE', symbol='TCS'), r);

            d = store('q');
            d = d{1};
            tc.verifyEqual(d.mode, 2);
            tc.verifyEqual(d.data, c.quotes_data('NSE:TCS'));
        end

        function testSubscribeDepth(tc, Transport)
            [c, ~] = tc.connectedClient(Transport);
            store = containers.Map();
            ins = {struct('exchange', 'NSE', 'symbol', 'SBIN')};
            tc.verifyTrue(c.subscribe_depth(ins, @(d) FeedAPITest.collect(store, 'd', d)));
            tc.verifyTrue(tc.waitUntil(c, @() c.depth_data.isKey('NSE:SBIN') && store.isKey('d'), 5));
            frames = tc.waitFrames(c, 0, 2);
            tc.verifyEqual(frames{2}, '{"action":"subscribe","symbols":[{"symbol":"SBIN","exchange":"NSE"}],"mode":3,"depth":5}');

            r = c.get_depth();
            e = r.depth.NSE.SBIN;
            tc.verifyEqual(fieldnames(e), {'timestamp'; 'ltp'; 'buyBook'; 'sellBook'});
            tc.verifyEqual(e.timestamp, 1700000000345);
            tc.verifyEqual(e.ltp, 105.25);
            tc.verifySize(e.buyBook, [1 5]);
            tc.verifySize(e.sellBook, [1 5]);
            tc.verifyEqual(e.buyBook(1), struct('price', 105.2, 'qty', 100, 'orders', 3));
            tc.verifyEqual(e.buyBook(3), struct('price', 105.1, 'qty', 25, 'orders', 1));
            tc.verifyEqual(e.buyBook(4), struct('price', 0, 'qty', 0, 'orders', 0));
            tc.verifyEqual(e.buyBook(5), struct('price', 0, 'qty', 0, 'orders', 0));
            tc.verifyEqual(e.sellBook(2), struct('price', 105.35, 'qty', 40, 'orders', 2));
            tc.verifyEqual(e.sellBook(3), struct('price', 0, 'qty', 0, 'orders', 0));

            d = store('d');
            d = d{1};
            tc.verifyEqual(d.mode, 3);
            tc.verifyEqual(fieldnames(d.data), {'ltp'; 'timestamp'; 'depth'});
            tc.verifySize(d.data.depth.buy, [1 3]);
            tc.verifyEqual(d.data.depth.buy{1}.quantity, 100);
            tc.verifySize(d.data.depth.sell, [1 2]);
        end

        function testUnsubscribeCleanup(tc, Transport)
            [c, cap] = tc.connectedClient(Transport);
            ins = {struct('exchange', 'NSE', 'symbol', 'RELIANCE'), struct('exchange', 'NSE', 'symbol', 'INFY')};
            tc.verifyTrue(c.subscribe_ltp(ins));
            tc.verifyTrue(c.subscribe_quote(ins(1)));
            tc.verifyTrue(c.subscribe_depth(ins(2)));
            tc.verifyTrue(tc.waitUntil(c, @() c.ltp_data.Count == 2 && c.quotes_data.Count == 1 && ...
                c.depth_data.Count == 1, 5));

            tc.verifyTrue(c.unsubscribe_ltp(ins(1)));
            tc.verifyTrue(cap.has('[UNSUB]  Unsubscribing NSE:RELIANCE LTP'));
            tc.verifyFalse(c.ltp_data.isKey('NSE:RELIANCE'));
            tc.verifyTrue(c.ltp_data.isKey('NSE:INFY'));
            tc.verifyEqual(numel(c.active_subs{1}.entries), 1);
            tc.verifyEqual(c.active_subs{1}.entries{1}.symbol, 'INFY');

            tc.verifyTrue(c.unsubscribe_quote(ins(1)));
            tc.verifyEqual(c.quotes_data.Count, uint64(0));
            tc.verifyEmpty(c.active_subs{2}.entries);
            tc.verifyTrue(c.unsubscribe_depth(ins(2)));
            tc.verifyEqual(c.depth_data.Count, uint64(0));
            tc.verifyEmpty(c.active_subs{3}.entries);
            tc.verifyTrue(cap.has('[UNSUB]  Unsubscribing NSE:INFY Depth'));

            frames = tc.waitFrames(c, 0, 7);
            tc.verifyEqual(frames{5}, '{"action":"unsubscribe","symbols":[{"symbol":"RELIANCE","exchange":"NSE","mode":1}]}');
            tc.verifyEqual(frames{6}, '{"action":"unsubscribe","symbols":[{"symbol":"RELIANCE","exchange":"NSE","mode":2}]}');
            tc.verifyEqual(frames{7}, '{"action":"unsubscribe","symbols":[{"symbol":"INFY","exchange":"NSE","mode":3}]}');
            r = c.get_ltp();
            tc.verifyEqual(fieldnames(r.ltp.NSE), {'INFY'});
        end

        function testInvalidInstrumentsAndTokenFallback(tc, Transport)
            [c, cap] = tc.connectedClient(Transport);
            ins = {struct('exchange', 'NSE'), struct('symbol', 'X'), 'garbage', ...
                struct('exchange', 'NSE', 'symbol', 'INFY')};
            tc.verifyTrue(c.subscribe_ltp(ins));
            tc.verifyTrue(cap.has('[ERROR]  Invalid instrument: {''exchange'': ''NSE''}'));
            tc.verifyTrue(cap.has('[ERROR]  Invalid instrument: {''symbol'': ''X''}'));
            tc.verifyTrue(cap.has('[ERROR]  Invalid instrument: ''garbage'''));
            frames = tc.waitFrames(c, 0, 2);
            tc.verifyEqual(frames{2}, '{"action":"subscribe","symbols":[{"symbol":"INFY","exchange":"NSE"}],"mode":1,"depth":5}');

            % All invalid: no frame is sent
            tc.verifyFalse(c.subscribe_quote({struct('exchange', '', 'symbol', 'A')}));
            tc.verifyFalse(c.unsubscribe_quote({struct('symbol', 'A')}));
            tc.verifyFalse(c.subscribe_depth({}));

            % exchange_token stands in for an empty symbol
            tc.verifyTrue(c.subscribe_ltp({struct('exchange', 'NSE', 'symbol', '', 'exchange_token', '2885')}));
            tc.verifyTrue(cap.has('[SUB]    Subscribing NSE:2885 LTP...'));
            frames = tc.waitFrames(c, 0, 3);
            tc.verifyEqual(numel(frames), 3);
            tc.verifyEqual(frames{3}, '{"action":"subscribe","symbols":[{"symbol":"2885","exchange":"NSE"}],"mode":1,"depth":5}');
            tc.verifyTrue(c.unsubscribe_ltp({struct('exchange', 'NSE', 'exchange_token', '2885')}));
            frames = tc.waitFrames(c, 0, 4);
            tc.verifyEqual(frames{4}, '{"action":"unsubscribe","symbols":[{"symbol":"2885","exchange":"NSE","mode":1}]}');
        end

        function testOrderUpdates(tc, Transport)
            [c, cap] = tc.connectedClient(Transport);
            store = containers.Map();
            tc.verifyTrue(c.subscribe_orders(@(o) FeedAPITest.collect(store, 'o', o)));
            tc.verifyTrue(c.orders_subscribed);
            tc.verifyTrue(cap.has('[SUB]    Subscribing to order updates...'));
            frames = tc.waitFrames(c, 0, 2);
            tc.verifyEqual(frames{2}, '{"action":"subscribe_orders"}');
            tc.verifyTrue(tc.waitUntil(c, @() cap.has('Order updates | subscribe_orders | Status: success'), 5));

            tc.mock(c, 'order');
            tc.mock(c, 'order', struct('order', struct('orderid', 'SB-0002', 'order_status', 'rejected')));
            tc.verifyTrue(tc.waitUntil(c, @() numel(c.order_data) == 2, 5));
            r = c.get_orders();
            tc.verifyEqual(r.orders{1}.orderid, 'SB-0002');
            tc.verifyEqual(r.orders{2}.orderid, 'SB-0001');
            tc.verifyEqual(r.orders{2}.average_price, 2450.5);
            tc.verifyTrue(tc.waitUntil(c, @() store.isKey('o') && numel(store('o')) == 2, 5));
            o = store('o');
            tc.verifyEqual(o{1}.type, 'order_update');

            tc.verifyTrue(c.unsubscribe_orders());
            tc.verifyFalse(c.orders_subscribed);
            tc.verifyTrue(cap.has('[UNSUB]  Unsubscribing from order updates'));
            frames = tc.framesOf(0);
            tc.verifyEqual(frames{end}, '{"action":"unsubscribe_orders"}');
        end

        function testFragmentedAndLargeMessages(tc, Transport)
            [c, ~] = tc.connectedClient(Transport);
            msg = '{"type":"market_data","symbol":"FRAG","exchange":"NSE","mode":1,"data":{"ltp":7.25,"timestamp":3}}';
            tc.mock(c, 'fragment', struct('parts', {{msg(1:20), msg(21:50), msg(51:end)}}));
            mid = sprintf('{"type":"market_data","symbol":"MID","exchange":"NSE","mode":1,"data":{"ltp":8,"timestamp":4,"pad":"%s"}}', ...
                repmat('m', 1, 300));
            big = sprintf('{"type":"market_data","symbol":"BIG","exchange":"NSE","mode":1,"data":{"ltp":9,"timestamp":5,"pad":"%s"}}', ...
                repmat('b', 1, 70000));
            tc.mock(c, 'push', struct('text', mid));
            tc.mock(c, 'push', struct('text', big));   % client frame above 65535 bytes as well
            tc.verifyTrue(tc.waitUntil(c, @() c.ltp_data.isKey('NSE:BIG'), 10));
            tc.verifyEqual(c.ltp_data('NSE:FRAG').price, 7.25);
            tc.verifyEqual(c.ltp_data('NSE:MID').price, 8);
            tc.verifyEqual(c.ltp_data('NSE:BIG').price, 9);
            tc.verifyTrue(c.connected);
        end

        function testServerPingIsAnswered(tc, Transport)
            [c, ~] = tc.connectedClient(Transport);
            conn = tc.lastConn();
            tc.mock(c, 'ping');
            tc.verifyTrue(tc.waitUntil(c, @() any(strcmp(tc.eventsOf(conn), 'pong')), 5));
        end

        function testReconnectAndReplay(tc, Transport)
            [c, cap] = tc.connectedClient(Transport, 'AutoReconnect', true);
            store = containers.Map();
            c.subscribe_ltp({struct('exchange', 'NSE', 'symbol', 'RELIANCE'), struct('exchange', 'NSE', 'symbol', 'INFY')}, ...
                @(d) FeedAPITest.collect(store, 'ltp', d));
            c.subscribe_quote({struct('exchange', 'NSE', 'symbol', 'TCS')});
            c.subscribe_depth({struct('exchange', 'NSE', 'symbol', 'SBIN')});
            c.subscribe_depth({struct('exchange', 'NSE', 'symbol', 'DEEP')}, depth=20);
            c.subscribe_orders();
            tc.verifyTrue(tc.waitUntil(c, @() store.isKey('ltp') && numel(store('ltp')) == 2 && ...
                c.depth_data.Count == 2, 5));
            firstConn = tc.lastConn();

            tc.mock(c, 'reject', struct('count', 1));   % the first attempt fails
            cap.clear();
            tc.mock(c, 'close');
            tc.verifyTrue(tc.waitUntil(c, @() ~c.connected, 5));
            done = @() c.authenticated && tc.lastConn() > firstConn && ...
                numel(tc.framesOf(tc.lastConn())) >= 6;
            tc.verifyTrue(tc.waitUntil(c, done, 20), cap.all());

            tc.verifyTrue(cap.has(['[WS]     Disconnected from ' c.ws_url]));
            tc.verifyTrue(cap.has('[WS]     Reconnect attempt 1 in 1s...'));
            tc.verifyTrue(cap.has('[ERROR]  WebSocket error: Handshake status 503'));
            tc.verifyTrue(cap.has('[WS]     Reconnect attempt 2 in 2s...'));
            tc.verifyTrue(cap.has('[WS]     Reconnected and re-authenticated.'));
            tc.verifyTrue(cap.has('[SUB]    Replaying 2 LTP subscription(s) after reconnect'));
            tc.verifyTrue(cap.has('[SUB]    Replaying 1 Quote subscription(s) after reconnect'));
            tc.verifyTrue(cap.has('[SUB]    Replaying 2 Depth subscription(s) after reconnect'));
            tc.verifyTrue(cap.has('[SUB]    Replaying order-update subscription after reconnect'));
            tc.verifyFalse(c.reconnect_active);

            frames = tc.framesOf(tc.lastConn());
            tc.verifyEqual(frames{1}, ['{"action":"authenticate","api_key":"' tc.ApiKey '"}']);
            tc.verifyEqual(frames{2}, ['{"action":"subscribe","symbols":[{"symbol":"RELIANCE","exchange":"NSE"},' ...
                '{"symbol":"INFY","exchange":"NSE"}],"mode":1,"depth":5}']);
            tc.verifyEqual(frames{3}, '{"action":"subscribe","symbols":[{"symbol":"TCS","exchange":"NSE"}],"mode":2,"depth":5}');
            tc.verifyEqual(frames{4}, '{"action":"subscribe","symbols":[{"symbol":"SBIN","exchange":"NSE"}],"mode":3,"depth":5}');
            tc.verifyEqual(frames{5}, '{"action":"subscribe","symbols":[{"symbol":"DEEP","exchange":"NSE"}],"mode":3,"depth":20}');
            tc.verifyEqual(frames{6}, '{"action":"subscribe_orders"}');

            % Callbacks keep firing on the new connection
            tc.verifyTrue(tc.waitUntil(c, @() numel(store('ltp')) >= 4, 5));
        end

        function testDisconnectSuppressesReconnect(tc, Transport)
            [c, cap] = tc.connectedClient(Transport, 'AutoReconnect', true);
            firstConn = tc.lastConn();
            c.disconnect();
            tc.verifyFalse(c.connected);
            tc.verifyFalse(c.authenticated);
            tc.verifyEmpty(c.ws);
            tc.verifyTrue(c.shutting_down);
            tc.verifyEmpty(c.poll_timer);
            tc.verifyTrue(cap.has(['[WS]     Disconnected from ' c.ws_url]));
            pause(2.5);
            tc.verifyFalse(cap.has('Reconnect attempt'));
            tc.verifyFalse(c.reconnect_active);
            tc.verifyEqual(tc.lastConn(), firstConn);
            tc.verifyTrue(tc.waitUntil([], @() any(strcmp(tc.eventsOf(firstConn), 'close')), 5));

            % connect() re-arms the client
            tc.verifyTrue(c.connect());
            tc.verifyFalse(c.shutting_down);
        end

        function testServerCloseWithoutAutoReconnect(tc, Transport)
            [c, cap] = tc.connectedClient(Transport, 'AutoReconnect', false);
            firstConn = tc.lastConn();
            tc.mock(c, 'close');
            tc.verifyTrue(tc.waitUntil(c, @() ~c.connected, 5));
            tc.verifyFalse(c.authenticated);
            tc.verifyTrue(cap.has(['[WS]     Disconnected from ' c.ws_url]));
            c.wait(2);
            tc.verifyFalse(cap.has('Reconnect attempt'));
            tc.verifyEqual(tc.lastConn(), firstConn);
            tc.verifyFalse(c.subscribe_ltp({struct('exchange', 'NSE', 'symbol', 'A')}));
        end

        function testPingTimeoutDetectsDeadConnection(tc, Transport)
            [c, cap] = tc.newClient(Transport, 'AutoReconnect', false);
            c.ping_interval = 0.5;
            c.ping_timeout = 1;
            tc.assertTrue(c.connect());
            tc.mock(c, 'abort');
            tc.verifyTrue(tc.waitUntil(c, @() ~c.connected, 10), cap.all());
            tc.verifyTrue(cap.has('[ERROR]  WebSocket error: '));
            tc.verifyTrue(cap.has(['[WS]     Disconnected from ' c.ws_url]));
        end

        function testDepthLevels(tc, Transport)
            [c, cap] = tc.connectedClient(Transport);
            ins = {struct('exchange', 'NSE', 'symbol', 'DEEP')};
            tc.verifyTrue(c.subscribe_depth(ins, depth=20));
            tc.verifyTrue(tc.waitUntil(c, @() c.depth_data.isKey('NSE:DEEP'), 5));
            frames = tc.waitFrames(c, 0, 2);
            tc.verifyEqual(frames{2}, '{"action":"subscribe","symbols":[{"symbol":"DEEP","exchange":"NSE"}],"mode":3,"depth":20}');
            r = c.get_depth('NSE', 'DEEP');
            tc.verifySize(r.depth.NSE.DEEP.buyBook, [1 20]);
            tc.verifySize(r.depth.NSE.DEEP.sellBook, [1 20]);
            tc.verifyEqual(r.depth.NSE.DEEP.buyBook(20).qty, 200);
            tc.verifyEqual(c.active_subs{3}.depths, 20);

            % Positional depth and a level the broker refuses
            tc.verifyTrue(c.subscribe_depth({struct('exchange', 'NSE', 'symbol', 'TOODEEP')}, [], 50));
            tc.verifyTrue(tc.waitUntil(c, @() cap.has('Subscription failed for NSE:TOODEEP'), 5), cap.all());
            tc.verifyTrue(cap.has('[ERROR]  Subscription failed for NSE:TOODEEP: Depth level 50 is not supported by this broker'));
            frames = tc.waitFrames(c, 0, 3);
            tc.verifySubstring(frames{3}, '"mode":3,"depth":50}');
            tc.verifyError(@() c.subscribe_depth(ins, depth=0), 'openalgo:FeedAPI:badArgument');
            tc.verifyTrue(cap.has('[SUB]    NSE:DEEP | Mode: Depth | Status: success'));
        end

        function testServerRequests(tc, Transport)
            [c, cap] = tc.connectedClient(Transport);
            store = containers.Map();
            c.subscribe_ltp({struct('exchange', 'NSE', 'symbol', 'RELIANCE')}, @(d) FeedAPITest.collect(store, 'ltp', d));
            c.subscribe_quote({struct('exchange', 'NSE', 'symbol', 'TCS')});
            c.subscribe_depth({struct('exchange', 'NSE', 'symbol', 'SBIN')});

            info = c.get_broker_info();
            tc.verifyEqual(info.type, 'broker_info');
            tc.verifyEqual(info.broker, 'mockbroker');
            tc.verifyEqual(info.adapter_status, 'connected');
            % Market data that arrived while waiting was processed
            tc.verifyTrue(tc.waitUntil(c, @() store.isKey('ltp'), 5));

            brokers = c.get_supported_brokers(timeout=3);
            tc.verifyEqual(brokers.type, 'supported_brokers');
            tc.verifyEqual(brokers.brokers, {'mockbroker'; 'otherbroker'});
            tc.verifyEqual(brokers.count, 2);

            before = floor(posixtime(datetime('now', 'TimeZone', 'UTC')) * 1000);
            pong = c.ws_ping();
            tc.verifyEqual(pong.type, 'pong');
            tc.verifyEqual(pong.status, 'success');
            tc.verifyGreaterThanOrEqual(pong.client_timestamp, before);
            tc.verifyGreaterThanOrEqual(pong.latency_ms, 0);
            tc.verifyLessThan(pong.latency_ms, 5000);
            frames = tc.framesOf(0);
            tc.verifyEqual(frames{end}, sprintf('{"action":"ping","timestamp":%d}', pong.client_timestamp));
            tc.verifyEmpty(c.pending_replies);

            % unsubscribe_all
            tc.verifyTrue(tc.waitUntil(c, @() c.quotes_data.Count == 1 && c.depth_data.Count == 1, 5));
            tc.verifyTrue(c.unsubscribe_all());
            tc.verifyTrue(cap.has('[UNSUB]  Unsubscribing from all symbols'));
            tc.verifyEmpty(c.active_subs{1}.entries);
            tc.verifyEmpty(c.active_subs{2}.entries);
            tc.verifyEmpty(c.active_subs{3}.entries);
            tc.verifyEqual(c.ltp_data.Count, uint64(0));
            tc.verifyEqual(c.quotes_data.Count, uint64(0));
            tc.verifyEqual(c.depth_data.Count, uint64(0));
            frames = tc.waitFrames(c, 0, 1);
            tc.verifyEqual(frames{end}, '{"action":"unsubscribe_all"}');
            tc.verifyTrue(tc.waitUntil(c, @() cap.has('[UNSUB]  NSE:SBIN | Mode: Depth | Status: success'), 5), cap.all());
            tc.verifyTrue(cap.has('[UNSUB]  NSE:RELIANCE | Mode: LTP | Status: success'));

            % A server error answers the waiting request and is logged
            c.ws.send('{"action":"bogus"}');
            tc.verifyTrue(tc.waitUntil(c, @() cap.has('[ERROR]  Server error INVALID_ACTION: Invalid action: bogus'), 5));
        end

        function testTlsVerifiesCertificateByDefault(tc, TlsTransport)
            % Without the test CA the system trust store must refuse the server.
            [c, cap] = tc.newClient(['wss_' TlsTransport]);
            c.tls_ca_file = '';
            tc.verifyTrue(c.tls_verify);
            tc.verifyFalse(c.connect());
            tc.verifyFalse(c.connected);
            tc.verifyTrue(cap.has('[ERROR]  WebSocket error: '), cap.all());
            tc.verifyTrue(cap.has('[ERROR]  Failed to connect to WebSocket server'));
        end

        function testTlsRejectsUnrelatedCaFile(tc, TlsTransport)
            [c, cap] = tc.newClient(['wss_' TlsTransport]);
            c.tls_ca_file = fullfile(tc.TlsDir, 'other-ca.pem');
            tc.verifyFalse(c.connect());
            tc.verifyTrue(cap.has('[ERROR]  WebSocket error: '), cap.all());
        end

        function testTlsVerifiesHostName(tc, TlsTransport)
            % The CA is trusted, but the certificate names another host.
            [c, cap] = tc.newClient(['wss_' TlsTransport], 'Url', tc.WrongNameUrl);
            tc.verifyFalse(c.connect());
            tc.verifyFalse(c.connected);
            tc.verifyTrue(cap.has('[ERROR]  WebSocket error: '), cap.all());
        end

        function testTlsWithoutVerification(tc, TlsTransport)
            % tls_verify = false accepts any certificate, here one for
            % another host from an untrusted CA. Java cannot do this.
            [c, cap] = tc.newClient(['wss_' TlsTransport], 'Url', tc.WrongNameUrl);
            c.tls_ca_file = '';
            c.tls_verify = false;
            if strcmp(TlsTransport, 'java')
                tc.verifyFalse(c.connect());
                tc.verifyTrue(cap.has( ...
                    '[ERROR]  WebSocket error: Certificate verification cannot be disabled on the Java transport.'), cap.all());
            else
                tc.verifyTrue(c.connect(), cap.all());
                tc.verifyEqual(c.ws.TransportName, TlsTransport);
            end
        end

        function testTlsAutoSelection(tc)
            tc.assumeNotEmpty(tc.TlsUrl, 'mock server has no wss:// listener');
            w = openalgo.internal.WebSocketClient(tc.TlsUrl, 'CaFile', fullfile(tc.TlsDir, 'ca.pem'));
            cleanup = onCleanup(@() w.abort());
            w.open(5);
            if openalgo.internal.DotNetTlsTransport.isAvailable()
                expected = 'dotnet';
            elseif openalgo.internal.PythonTlsTransport.isAvailable()
                expected = 'python';
            else
                expected = 'java';
            end
            tc.verifyEqual(w.TransportName, expected);
            tc.verifyTrue(w.isOpen());
            w.send('{"action":"authenticate","api_key":"mock-api-key-0123456789abcdef"}');
            got = {};
            started = tic;
            while isempty(got) && toc(started) < 5
                got = w.poll();
                pause(0.02);
            end
            tc.assertNotEmpty(got);
            tc.verifySubstring(got{1}, '"status": "success"');
            w.close();
            started = tic;
            while ~w.isClosed() && toc(started) < 3
                w.poll();
                pause(0.02);
            end
            tc.verifyTrue(w.isClosed());
            tc.verifyEqual(w.CloseCode, 1000);
            clear cleanup
        end

        function testPauseDrivesCallbacks(tc, Transport)
            % The poll timer delivers data during pause().
            [c, ~] = tc.connectedClient(Transport);
            c.subscribe_ltp({struct('exchange', 'NSE', 'symbol', 'PAUSE')});
            started = tic;
            while ~c.ltp_data.isKey('NSE:PAUSE') && toc(started) < 5
                pause(0.1);
            end
            tc.verifyTrue(c.ltp_data.isKey('NSE:PAUSE'));
        end
    end

    %% Helpers

    methods (Access = private)
        function url = urlOrDefault(tc)
            url = tc.Url;
            if isempty(url)
                url = 'ws://127.0.0.1:8765';
            end
        end

        function [c, cap] = newClient(tc, transport, varargin)
            % transport: 'ws', or 'dotnet' / 'python' / 'java' (optionally
            % prefixed with 'wss_') for wss:// through that TLS transport.
            transport = regexprep(char(transport), '^wss_', '');
            if strcmp(transport, 'ws')
                url = tc.Url;
            else
                tc.assumeNotEmpty(tc.TlsUrl, 'mock server has no wss:// listener');
                tc.assumeNotEmpty(tc.WrongNameUrl, 'mock server has no wss:// listener');
                switch transport
                    case 'dotnet'
                        tc.assumeTrue(openalgo.internal.DotNetTlsTransport.isAvailable(), ...
                            '.NET is not available in this MATLAB session');
                    case 'python'
                        tc.assumeTrue(tc.PythonReady, ...
                            'no usable Python interface (see pyenv and OPENALGO_TEST_PYENV)');
                    case 'java'
                        tc.assumeTrue(openalgo.internal.JavaTlsTransport.isAvailable(), ...
                            'MATLAB runs without the JVM');
                end
                url = tc.TlsUrl;
            end
            p = inputParser;
            p.addParameter('Verbose', 1);
            p.addParameter('AutoReconnect', false);
            p.addParameter('Url', url);
            p.addParameter('Key', tc.ApiKey);
            p.parse(varargin{:});
            c = FeedTestClient(p.Results.Key, [], [], p.Results.Url, p.Results.Verbose, p.Results.AutoReconnect);
            if ~strcmp(transport, 'ws')
                c.tls_transport = transport;
                c.tls_ca_file = fullfile(tc.TlsDir, 'ca.pem');   % test CA; verification stays on
            end
            cap = LogCapture();
            c.log_sink = @(line) cap.add(line);
            tc.addTeardown(@FeedAPITest.destroyClient, c);
        end

        function [c, cap] = connectedClient(tc, transport, varargin)
            [c, cap] = tc.newClient(transport, varargin{:});
            tc.assertTrue(c.connect(), sprintf('connect failed:\n%s', cap.all()));
            if ~strcmp(transport, 'ws')
                tc.verifyEqual(c.ws.TransportName, regexprep(char(transport), '^wss_', ''));
            end
        end

        function ok = waitUntil(~, c, cond, timeout)
            started = tic;
            while ~cond() && toc(started) < timeout
                if isempty(c)
                    pause(0.05);
                else
                    c.wait(0.05);
                end
            end
            ok = cond();
        end

        function mock(~, c, cmd, extra)
            if nargin < 4
                extra = struct();
            end
            m = struct('action', 'mock', 'cmd', cmd);
            f = fieldnames(extra);
            for i = 1:numel(f)
                m.(f{i}) = extra.(f{i});
            end
            c.ws.send(jsonencode(m));
        end

        function recs = records(tc)
            recs = {};
            if ~isfile(tc.RecordFile)
                return
            end
            try
                txt = fileread(tc.RecordFile);
            catch
                return
            end
            lines = splitlines(txt);
            for i = 1:numel(lines)
                if isempty(strtrim(lines{i}))
                    continue
                end
                try
                    recs{end + 1} = jsondecode(lines{i}); %#ok<AGROW>
                catch
                end
            end
        end

        function frames = framesOf(tc, conn)
            % Raw text frames received on connection conn (0 = all), without mock control frames.
            frames = {};
            recs = tc.records();
            for i = 1:numel(recs)
                r = recs{i};
                if isfield(r, 'frame') && (conn == 0 || r.conn == conn) && ...
                        ~startsWith(r.frame, '{"action":"mock"')
                    frames{end + 1} = r.frame; %#ok<AGROW>
                end
            end
        end

        function frames = waitFrames(tc, c, conn, n)
            tc.waitUntil(c, @() numel(tc.framesOf(conn)) >= n, 5);
            frames = tc.framesOf(conn);
            tc.assertGreaterThanOrEqual(numel(frames), n, 'frames not recorded in time');
        end

        function events = eventsOf(tc, conn)
            events = {};
            recs = tc.records();
            for i = 1:numel(recs)
                r = recs{i};
                if isfield(r, 'event') && r.conn == conn
                    events{end + 1} = r.event; %#ok<AGROW>
                end
            end
        end

        function conn = lastConn(tc)
            conn = 0;
            recs = tc.records();
            for i = 1:numel(recs)
                r = recs{i};
                if isfield(r, 'event') && strcmp(r.event, 'open')
                    conn = max(conn, r.conn);
                end
            end
        end
    end

    methods (Static)
        function collect(store, key, value)
            if store.isKey(key)
                store(key) = [store(key), {value}];
            else
                store(key) = {value};
            end
        end
    end

    methods (Static, Access = private)
        function proc = launch(args, logFile)
            proc = [];
            if usejava('jvm')
                jargs = javaArray('java.lang.String', numel(args));
                for i = 1:numel(args)
                    jargs(i) = java.lang.String(args{i});
                end
                pb = java.lang.ProcessBuilder(jargs);
                pb.redirectErrorStream(true);
                pb.redirectOutput(java.io.File(logFile));
                proc = pb.start();
            else
                quoted = cellfun(@(a) ['"' a '"'], args, 'UniformOutput', false);
                cmd = strjoin(quoted, ' ');
                if ispc
                    system(['start "" /B ' cmd ' > "' logFile '" 2>&1']);
                else
                    system([cmd ' > "' logFile '" 2>&1 &']);
                end
            end
        end

        function stopServer(proc, readyFile, pidFile)
            try
                if isfile(readyFile)
                    port = str2double(strtrim(fileread(readyFile)));
                    w = openalgo.internal.WebSocketClient(sprintf('ws://127.0.0.1:%d', port));
                    w.open(3);
                    w.send('{"action":"mock","cmd":"shutdown"}');
                    pause(0.3);
                    w.abort();
                end
            catch
            end
            if ~isempty(proc)
                try
                    proc.destroy();
                catch
                end
            elseif isfile(pidFile)
                pause(0.5);
                pid = strtrim(fileread(pidFile));
                if ispc
                    [~, ~] = system(['taskkill /F /PID ' pid ' >NUL 2>&1']);
                else
                    [~, ~] = system(['kill ' pid ' 2>/dev/null']);
                end
            end
        end

        function ok = preparePython()
            % Make the Python interface usable for the Python TLS transport
            % tests without loading an unsupported interpreter.
            ok = false;
            try
                pe = pyenv;
                if ~strcmp(string(pe.Status), "Loaded")
                    candidates = {getenv('OPENALGO_TEST_PYENV')};
                    if any(strcmp(char(pe.Version), openalgo.internal.PythonTlsTransport.SupportedVersions))
                        candidates{end + 1} = char(pe.Executable);
                    end
                    local = getenv('LOCALAPPDATA');
                    candidates = [candidates, { ...
                        fullfile(local, 'Programs', 'Python', 'Python313', 'python.exe'), ...
                        'C:\Python313\python.exe', ...
                        fullfile(local, 'Programs', 'Python', 'Python312', 'python.exe'), ...
                        'C:\Python312\python.exe'}];
                    chosen = '';
                    for i = 1:numel(candidates)
                        if ~isempty(candidates{i}) && isfile(candidates{i})
                            chosen = candidates{i};
                            break
                        end
                    end
                    if isempty(chosen)
                        return
                    end
                    pyenv(Version=chosen);
                end
                ok = openalgo.internal.PythonTlsTransport.isAvailable(true);
            catch
                ok = false;
            end
        end

        function destroyClient(c)
            try
                c.verbose = 0;
                c.disconnect();
            catch
            end
            try
                delete(c);
            catch
            end
        end

        function cleanupTimers()
            try
                t = timerfindall('Name', 'openalgo-feed-poll');
                t = [t, timerfindall('Name', 'openalgo-feed-reconnect')]; %#ok<AGROW>
                if ~isempty(t)
                    stop(t);
                    delete(t);
                end
            catch
            end
        end

        function removeDir(folder)
            if isfolder(folder)
                warnState = warning('off', 'all');
                try
                    rmdir(folder, 's');
                catch
                end
                warning(warnState);
            end
        end

        function text = readText(file)
            text = '';
            if isfile(file)
                text = fileread(file);
            end
        end
    end
end
