classdef LiveSandboxTest < matlab.unittest.TestCase
    %LIVESANDBOXTEST Live tests against a running OpenAlgo server in analyzer
    %   (sandbox) mode.
    %
    %   Skipped unless the environment variable OPENALGO_API_KEY is set. The
    %   host is OPENALGO_HOST (default http://127.0.0.1:5000); the feed uses
    %   the WebSocket URL derived from it (ws://<host>:8765), or
    %   OPENALGO_WS_URL when set. Never put the key in a file:
    %
    %     OPENALGO_API_KEY=... matlab -batch "addpath('tests'); runAllTests('', 'LiveSandboxTest')"
    %
    %   The first test asserts that analyzer mode is on; every test that
    %   places, modifies or cancels anything is skipped otherwise, so no
    %   live order can be sent. Orders are CNC LIMIT orders priced at 60
    %   percent of the last price (far from the market), tagged with the
    %   strategy name MatlabLiveTest, and cancelled again. Read-only calls
    %   that the server refuses because the market is closed are tolerated
    %   and recorded; the outcome of every call is printed at the end.
    %
    %   Never called live: analyzertoggle, telegram, whatsapp, updatechart,
    %   updatetelegramconfig, telegramstart, telegramstop, telegrambroadcast
    %   and updatetelegrampreferences (they change settings or send
    %   messages), and the strategy module lifecycle calls.

    properties (Constant)
        Strategy = 'MatlabLiveTest'
        ClosedMarket = ['market (is )?(currently )?closed|closed market|market hours|' ...
            'outside (of )?(the )?(market|trading)|not within (market|trading)|holiday|' ...
            'no data available|after market|pre.?market|market is not open|not open for trading']
    end

    properties
        Client
        AnalyzeMode = false
        Outcomes            % containers.Map (a handle, shared by all tests)
        Ltp = NaN
    end

    methods (TestClassSetup)
        function connectToServer(tc)
            key = getenv('OPENALGO_API_KEY');
            tc.assumeNotEmpty(key, 'OPENALGO_API_KEY is not set: live tests skipped.');
            root = fileparts(fileparts(mfilename('fullpath')));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(root));
            host = getenv('OPENALGO_HOST');
            if isempty(host)
                host = 'http://127.0.0.1:5000';
            end
            wsUrl = getenv('OPENALGO_WS_URL');
            if isempty(wsUrl)
                wsUrl = [];
            end
            tc.Client = openalgo.api(api_key=key, host=host, ws_url=wsUrl, timeout=60);
            tc.Outcomes = containers.Map();
            tc.addTeardown(@() LiveSandboxTest.printOutcomes(tc.Outcomes));

            st = tc.Client.analyzerstatus();
            tc.assertEqual(st.status, 'success', ['analyzerstatus failed: ' LiveSandboxTest.describe(st)]);
            tc.AnalyzeMode = isfield(st.data, 'analyze_mode') && isequal(st.data.analyze_mode, true);
            tc.record('analyzerstatus', st);

            q = tc.Client.quotes(symbol="SBIN", exchange="NSE");
            if isstruct(q) && strcmp(q.status, 'success') && isnumeric(q.data.ltp) && q.data.ltp > 0
                tc.Ltp = q.data.ltp;
            end
        end
    end

    methods (Test)
        function analyzerModeIsOn(tc)
            % Asserted first: the order tests below run only in sandbox mode.
            tc.verifyTrue(tc.AnalyzeMode, ...
                'The server is NOT in analyzer mode: every order test is skipped.');
        end

        function accountReads(tc)
            c = tc.Client;
            tc.accept('funds', c.funds());
            ob = tc.accept('orderbook', c.orderbook());
            tc.verifyTrue(isfield(ob, 'data'));
            tc.accept('tradebook', c.tradebook());
            tc.accept('positionbook', c.positionbook());
            tc.accept('holdings', c.holdings());
            tc.accept('openposition', c.openposition(strategy=tc.Strategy, symbol="SBIN", ...
                exchange="NSE", product="CNC"));
            pos = struct('symbol', 'SBIN', 'exchange', 'NSE', 'action', 'BUY', 'product', 'CNC', ...
                'pricetype', 'LIMIT', 'quantity', 1, 'price', 500);
            tc.accept('margin', c.margin(positions=pos), true);
        end

        function marketDataReads(tc)
            c = tc.Client;
            q = tc.accept('quotes', c.quotes(symbol="SBIN", exchange="NSE"), true);
            if isfield(q, 'data')
                tc.verifyTrue(all(isfield(q.data, {'ltp', 'open', 'high', 'low', 'volume'})));
            end
            syms = {struct('symbol', 'SBIN', 'exchange', 'NSE'), struct('symbol', 'INFY', 'exchange', 'NSE')};
            mq = tc.accept('multiquotes', c.multiquotes(symbols=syms), true);
            if isfield(mq, 'results')
                tc.verifyNumElements(mq.results, 2);
            end
            tc.accept('depth', c.depth(symbol="SBIN", exchange="NSE"), true);
            s = tc.accept('symbol', c.symbol(symbol="SBIN", exchange="NSE"));
            tc.verifyEqual(s.data.symbol, 'SBIN');
            tc.accept('search', c.search(query="SBIN", exchange="NSE"));
            iv = tc.accept('intervals', c.intervals());
            tc.verifyTrue(isfield(iv.data, 'minutes'));
            tc.accept('interval', c.interval());
            tc.accept('holidays', c.holidays(2026));
            tc.accept('timings', c.timings(char(datetime('today', 'Format', 'yyyy-MM-dd'))), true);
        end

        function historyTimetables(tc)
            c = tc.Client;
            d2 = datetime('today');
            d1 = d2 - days(10);
            fmt = @(d) char(d, 'yyyy-MM-dd');
            tt = c.history(symbol="SBIN", exchange="NSE", interval="5m", start_date=fmt(d1), end_date=fmt(d2));
            tc.record('history 5m', tt);
            if istimetable(tt)
                times = tt.Properties.RowTimes;
                tc.verifyTrue(ismember(times.TimeZone, {'Asia/Kolkata', 'Asia/Calcutta'}));
                tc.verifyTrue(issorted(times) && numel(unique(times)) == numel(times));
                tc.verifyTrue(all(ismember({'open', 'high', 'low', 'close', 'volume'}, tt.Properties.VariableNames)));
                tc.verifyEqual(hour(times(1)) * 60 + minute(times(1)) >= 9 * 60 + 15, true);
            else
                tc.verifyTrue(tc.closedMarket(tt), ['history 5m: ' LiveSandboxTest.describe(tt)]);
            end
            tt = c.history(symbol="SBIN", exchange="NSE", interval="D", start_date=fmt(d2 - days(40)), end_date=fmt(d2));
            tc.record('history D', tt);
            if istimetable(tt)
                times = tt.Properties.RowTimes;
                tc.verifyEqual(times.TimeZone, '');   % zone-less, like the Python SDK
                tc.verifyTrue(issorted(times));
            else
                tc.verifyTrue(tc.closedMarket(tt), ['history D: ' LiveSandboxTest.describe(tt)]);
            end
        end

        function instrumentsTable(tc)
            T = tc.Client.instruments(exchange="NSE_INDEX");
            tc.record('instruments NSE_INDEX', T);
            tc.assertClass(T, 'table', LiveSandboxTest.describe(T));
            tc.verifyGreaterThan(height(T), 0);
            tc.verifyTrue(all(ismember({'symbol', 'exchange', 'token'}, T.Properties.VariableNames)));
            tc.verifyTrue(all(T.exchange == "NSE_INDEX"));
        end

        function optionsLookups(tc)
            c = tc.Client;
            e = tc.accept('expiry', c.expiry(symbol="NIFTY", exchange="NFO", instrumenttype="options"));
            tc.assertNotEmpty(e.data);
            expiries = cellstr(e.data);
            exp = upper(strrep(expiries{1}, '-', ''));    % 19-OCT-26 -> 19OCT26
            % Prefer the second expiry when the first one is today or tomorrow.
            if numel(expiries) > 1
                exp = upper(strrep(expiries{2}, '-', ''));
            end
            tc.accept('syntheticfuture', c.syntheticfuture(underlying="NIFTY", exchange="NSE_INDEX", ...
                expiry_date=exp), true);
            os = tc.accept('optionsymbol', c.optionsymbol(underlying="NIFTY", exchange="NSE_INDEX", ...
                expiry_date=exp, offset="OTM2", option_type="CE"), true);
            if ~isfield(os, 'symbol')
                return
            end
            tc.verifyTrue(startsWith(os.symbol, ['NIFTY' exp]));
            g = tc.accept('optiongreeks', c.optiongreeks(symbol=os.symbol, exchange="NFO"), true);
            if isfield(g, 'greeks')
                tc.verifyTrue(all(isfield(g.greeks, {'delta', 'gamma', 'theta', 'vega', 'rho'})));
            end
            ch = tc.accept('optionchain', c.optionchain(underlying="NIFTY", exchange="NSE_INDEX", ...
                expiry_date=exp, strike_count=2), true);
            if isfield(ch, 'chain')
                tc.verifyNumElements(ch.chain, 5);
            end
            m = tc.accept('multioptiongreeks', c.multioptiongreeks( ...
                symbols={struct('symbol', os.symbol, 'exchange', 'NFO')}, interest_rate=0), true);
            if isfield(m, 'summary')
                tc.verifyEqual(m.summary.total, 1);
            end
        end

        function additionsReadOnly(tc)
            c = tc.Client;
            p = tc.accept('ping', c.ping());
            tc.verifyEqual(p.data.message, 'pong');
            if tc.AnalyzeMode
                tc.accept('pnlsymbols', c.pnlsymbols());
            end
            d2 = datetime('today');
            fmt = @(d) char(d, 'yyyy-MM-dd');
            t = tc.accept('ticker json', c.ticker(symbol="SBIN", exchange="NSE", interval="D", ...
                start_date=fmt(d2 - days(15)), end_date=fmt(d2)), true);
            if isfield(t, 'data')
                tc.verifyTrue(all(isfield(t.data, {'timestamp', 'open', 'close'})));
            end
            txt = c.ticker(symbol="SBIN", exchange="NSE", interval="D", start_date=fmt(d2 - days(15)), ...
                end_date=fmt(d2), format="txt");
            tc.record('ticker txt', txt);
            if ischar(txt)
                lines = splitlines(strtrim(txt));
                tc.verifyTrue(startsWith(lines{1}, 'NSE:SBIN,'), lines{1});
            else
                tc.verifyTrue(tc.closedMarket(txt), LiveSandboxTest.describe(txt));
            end
            tc.accept('chart', c.chart());
            cfg = tc.accept('telegramconfig', c.telegramconfig());
            tc.verifyTrue(isfield(cfg.data, 'rate_limit_per_minute'));
            u = tc.accept('telegramusers', c.telegramusers());
            tc.verifyTrue(isfield(u, 'count'));
            tc.accept('telegramstats', c.telegramstats(7));
            tc.accept('telegrampreferences', c.telegrampreferences(1));
        end

        function strategyModuleReads(tc)
            c = tc.Client;
            l = tc.accept('strategylist', c.strategylist());
            tc.verifyTrue(isfield(l, 'data'));
            % An id that does not exist answers 404 with a JSON body that is
            % passed through with code (the read-only paths of this module).
            r = c.strategystatus(strategy_id=987654321);
            tc.record('strategystatus (unknown id)', r);
            tc.verifyEqual(r.status, 'error');
            tc.verifyEqual(r.code, 404);
            r = c.strategyruns(strategy_id=987654321);
            tc.record('strategyruns (unknown id)', r);
            tc.verifyEqual(r.code, 404);
            r = c.strategyorders(strategy_id=987654321);
            tc.record('strategyorders (unknown id)', r);
            tc.verifyEqual(r.code, 404);
            r = c.strategyevents(strategy_id=987654321);
            tc.record('strategyevents (unknown id)', r);
            tc.verifyEqual(r.code, 404);
        end

        function orderLifecycle(tc)
            tc.assumeTrue(tc.AnalyzeMode, 'Not in analyzer mode: order tests skipped.');
            c = tc.Client;
            price = tc.farPrice();
            r = tc.accept('placeorder', c.placeorder(strategy=tc.Strategy, symbol="SBIN", action="BUY", ...
                exchange="NSE", price_type="LIMIT", product="CNC", quantity=1, price=price));
            tc.assertTrue(isfield(r, 'orderid'));
            oid = r.orderid;
            tc.verifyEqual(r.mode, 'analyze');
            s = tc.accept('orderstatus', c.orderstatus(order_id=oid, strategy=tc.Strategy));
            tc.verifyEqual(s.data.order_status, 'open');
            tc.verifyEqual(s.data.price, price);
            tc.accept('modifyorder', c.modifyorder(order_id=oid, strategy=tc.Strategy, symbol="SBIN", ...
                action="BUY", exchange="NSE", price_type="LIMIT", product="CNC", quantity=1, price=price + 1));
            s = c.orderstatus(order_id=oid, strategy=tc.Strategy);
            tc.verifyEqual(s.data.price, price + 1);
            tc.accept('cancelorder', c.cancelorder(order_id=oid, strategy=tc.Strategy));
            s = c.orderstatus(order_id=oid, strategy=tc.Strategy);
            tc.verifyEqual(s.data.order_status, 'cancelled');
        end

        function smartBasketSplitAndCancelAll(tc)
            tc.assumeTrue(tc.AnalyzeMode, 'Not in analyzer mode: order tests skipped.');
            c = tc.Client;
            price = tc.farPrice();
            sm = tc.accept('placesmartorder', c.placesmartorder(strategy=tc.Strategy, symbol="SBIN", ...
                action="BUY", exchange="NSE", price_type="LIMIT", product="CNC", quantity=1, ...
                position_size=1, price=price));
            orders = struct('symbol', {'SBIN', 'SBIN'}, 'exchange', 'NSE', 'action', 'BUY', ...
                'quantity', 1, 'pricetype', 'LIMIT', 'product', 'CNC', 'price', {price, price - 1});
            b = tc.accept('basketorder', c.basketorder(strategy=tc.Strategy, orders=orders));
            tc.verifyNumElements(b.results, 2);
            sp = tc.accept('splitorder', c.splitorder(strategy=tc.Strategy, symbol="SBIN", ...
                exchange="NSE", action="BUY", quantity=2, splitsize=1, price_type="LIMIT", ...
                product="CNC", price=price));
            tc.verifyEqual(sp.total_quantity, 2);
            tc.verifyNumElements(sp.results, 2);
            ca = tc.accept('cancelallorder', c.cancelallorder(strategy=tc.Strategy));
            ids = [{b.results.orderid}, {sp.results.orderid}];
            if isfield(sm, 'orderid')
                st = c.orderstatus(order_id=sm.orderid, strategy=tc.Strategy);
                if isfield(st, 'data') && strcmp(st.data.order_status, 'open')
                    ids{end + 1} = sm.orderid;
                end
            end
            tc.verifyTrue(all(ismember(ids, cellstr(ca.canceled_orders))), ...
                'cancelallorder did not cancel every order placed by this test');
            tc.accept('closeposition', c.closeposition(strategy=tc.Strategy));
        end

        function gttLifecycle(tc)
            tc.assumeTrue(tc.AnalyzeMode, 'Not in analyzer mode: order tests skipped.');
            c = tc.Client;
            price = tc.farPrice();
            r = tc.accept('placegttorder', c.placegttorder(strategy=tc.Strategy, symbol="SBIN", ...
                exchange="NSE", action="BUY", quantity=1, price=price, triggerprice_sl=price + 1));
            tc.assertTrue(isfield(r, 'trigger_id'));
            tid = r.trigger_id;
            tc.verifyTrue(startsWith(tid, 'GTT-'));
            tc.accept('modifygttorder', c.modifygttorder(trigger_id=tid, strategy=tc.Strategy, ...
                symbol="SBIN", exchange="NSE", action="BUY", quantity=1, price=price - 1, ...
                triggerprice_sl=price));
            book = tc.accept('gttorderbook', c.gttorderbook());
            entry = LiveSandboxTest.findTrigger(book, tid);
            tc.assertNotEmpty(entry, 'The new trigger is not in gttorderbook');
            tc.verifyEqual(entry.status, 'active');
            tc.verifyEqual(entry.trigger_prices, price);
            tc.accept('cancelgttorder', c.cancelgttorder(trigger_id=tid, strategy=tc.Strategy));
            book = tc.accept('gttorderbook status=all', c.gttorderbook(status="all"));
            entry = LiveSandboxTest.findTrigger(book, tid);
            tc.assertNotEmpty(entry);
            tc.verifyEqual(entry.status, 'cancelled');
        end

        function websocketFeed(tc)
            c = tc.Client;
            tc.addTeardown(@() c.disconnect());
            ok = c.connect();
            tc.record('ws connect', struct('status', tf(ok)));
            tc.assertTrue(ok, ['WebSocket connect failed (' c.ws_url ')']);
            tc.verifyTrue(c.connected && c.authenticated);
            ins = {struct('exchange', 'NSE', 'symbol', 'SBIN')};
            tc.verifyTrue(c.subscribe_ltp(ins));
            c.wait(4);
            r = c.get_ltp();
            tc.verifyTrue(isstruct(r) && isfield(r, 'ltp'));
            if isfield(r.ltp, 'NSE') && isfield(r.ltp.NSE, 'SBIN')
                tc.verifyTrue(all(isfield(r.ltp.NSE.SBIN, {'timestamp', 'ltp'})));
                tc.record('ws get_ltp', struct('status', 'success', 'message', sprintf('ltp %g', r.ltp.NSE.SBIN.ltp)));
            else
                % No tick arrives while the market is closed.
                tc.verifyEqual(r.ltp, struct());
                tc.record('ws get_ltp', struct('status', 'tolerated', 'message', 'no tick received (market closed)'));
            end
            p = c.ws_ping();
            tc.record('ws ws_ping', p);
            tc.verifyEqual(p.type, 'pong');
            tc.verifyGreaterThan(p.latency_ms, 0);
            b = c.get_broker_info();
            tc.record('ws get_broker_info', b);
            tc.verifyEqual(b.type, 'broker_info');
            tc.verifyTrue(c.unsubscribe_all());
            tc.verifyEqual(c.get_ltp(), struct('ltp', struct()));
            c.disconnect();
            tc.verifyFalse(c.connected);
            tc.record('ws disconnect', struct('status', tf(~c.connected)));
        end
    end

    methods
        function r = accept(tc, name, r, closedOk)
            %ACCEPT Record a result and require success (or, when CLOSEDOK,
            %   an error that is clearly caused by the closed market).
            if nargin < 4
                closedOk = false;
            end
            tc.record(name, r);
            if isstruct(r) && isfield(r, 'status') && strcmp(r.status, 'success')
                return
            end
            if closedOk && tc.closedMarket(r)
                return
            end
            tc.verifyFail(sprintf('%s failed: %s', name, LiveSandboxTest.describe(r)));
        end

        function tf = closedMarket(tc, r)
            tf = isstruct(r) && isfield(r, 'message') && ischar(r.message) && ...
                ~isempty(regexpi(r.message, tc.ClosedMarket, 'once'));
        end

        function record(tc, name, r)
            if isstruct(r) && isfield(r, 'status')
                if strcmp(r.status, 'error')
                    outcome = 'error';
                    if tc.closedMarket(r)
                        outcome = 'tolerated (market closed)';
                    end
                else
                    outcome = char(string(r.status));
                end
            elseif istimetable(r) || istable(r)
                outcome = sprintf('success (%s, %d rows)', class(r), height(r));
            elseif ischar(r)
                outcome = sprintf('success (text, %d lines)', numel(splitlines(strtrim(r))));
            else
                outcome = class(r);
            end
            tc.Outcomes(name) = {outcome, LiveSandboxTest.describe(r)};
        end

        function price = farPrice(tc)
            tc.assumeFalse(isnan(tc.Ltp), 'No SBIN quote available to price the far LIMIT orders.');
            price = round(tc.Ltp * 0.6);   % whole rupees: on the 0.05 tick grid
        end
    end

    methods (Static)
        function text = describe(r)
            if isstruct(r) && isfield(r, 'message')
                m = r.message;
                if ~ischar(m)
                    m = jsonencode(m);
                end
                text = sprintf('%s: %s', string(LiveSandboxTest.field(r, 'error_type', r.status)), m);
            elseif isstruct(r) && isfield(r, 'status')
                text = char(string(r.status));
            elseif istable(r) || istimetable(r)
                text = sprintf('%d rows', height(r));
            elseif ischar(r)
                text = sprintf('%d characters', numel(r));
            else
                text = class(r);
            end
            text = char(text);
            if numel(text) > 160
                text = [text(1:157) '...'];
            end
        end

        function v = field(s, name, default)
            if isfield(s, name)
                v = s.(name);
            else
                v = default;
            end
        end

        function entry = findTrigger(book, tid)
            entry = [];
            if ~isfield(book, 'data') || isempty(book.data)
                return
            end
            data = book.data;
            if isstruct(data)
                data = num2cell(data);
            end
            for i = 1:numel(data)
                if strcmp(data{i}.trigger_id, tid)
                    entry = data{i};
                    return
                end
            end
        end

        function printOutcomes(outcomes)
            names = outcomes.keys();
            fprintf('\nLive outcome per call (%d calls):\n', numel(names));
            for i = 1:numel(names)
                v = outcomes(names{i});
                fprintf('  %-30s %-28s %s\n', names{i}, v{1}, v{2});
            end
            fprintf('\n');
        end
    end
end

function s = tf(x)
if x
    s = 'success';
else
    s = 'error';
end
end
