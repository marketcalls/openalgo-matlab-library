classdef FeedAPI < handle
    %FEEDAPI WebSocket market data feed for OpenAlgo.
    %   FeedAPI is a mixin that gives openalgo.api its streaming methods.
    %   It connects to the OpenAlgo WebSocket proxy (default
    %   ws://127.0.0.1:8765), authenticates with the API key, and streams
    %   LTP (mode 1), Quote (mode 2) and Depth (mode 3) market data plus
    %   account level order updates.
    %
    %   Methods (same names and parameters as the Python SDK):
    %       connect, disconnect
    %       subscribe_ltp, unsubscribe_ltp
    %       subscribe_quote, unsubscribe_quote
    %       subscribe_depth, unsubscribe_depth
    %       subscribe_orders, unsubscribe_orders
    %       get_ltp, get_quotes, get_depth, get_orders
    %
    %   Additions beyond the Python SDK (server features it lacks):
    %       wait                   process the feed for N seconds
    %       unsubscribe_all        drop every symbol subscription
    %       get_broker_info        broker name and adapter status
    %       get_supported_brokers  brokers the server is configured for
    %       ws_ping                application level ping with latency
    %       subscribe_depth(..., depth) requests 5, 20, 30 or 50 levels
    %       Server error messages and unsubscribe acknowledgements are
    %       logged at verbose level 1.
    %
    %   Processing model:
    %       MATLAB runs your code on a single thread. The feed reads the
    %       socket from a MATLAB timer every 0.05 s, so callbacks run while
    %       MATLAB is idle at the prompt, during pause() and during
    %       client.wait(). pause(10) therefore behaves like time.sleep(10)
    %       in Python. A long running computation without pause() delays
    %       the feed until it finishes. In matlab -batch scripts use
    %       client.wait(seconds) or pause(seconds) to keep receiving data.
    %       Call disconnect() when done: the timers hold a reference to the
    %       client until then.
    %
    %   Secure WebSocket (wss://):
    %       A server hosted OpenAlgo usually serves wss:// only; pass it as
    %       ws_url, for example 'wss://openalgo.example.com/ws'. TLS needs
    %       one of: .NET (Windows, used first), the MATLAB Python interface
    %       with a supported Python (see pyenv), or the JVM. The server
    %       certificate and host name are always verified. For a server
    %       whose certificate comes from a private CA, set
    %       client.tls_ca_file to a PEM file with that CA before connect();
    %       it is trusted in addition to the system trust store.
    %
    %   Instruments:
    %       A cell array of structs or a struct array with fields exchange
    %       and symbol (and optionally exchange_token, used as the symbol
    %       when symbol is empty), for example
    %           {struct('exchange','NSE','symbol','RELIANCE'), ...
    %            struct('exchange','NSE','symbol','INFY')}
    %       or struct('exchange',{'NSE','NSE'},'symbol',{'RELIANCE','INFY'}).
    %
    %   Symbol names in returned structs:
    %       get_ltp, get_quotes and get_depth return nested structs keyed
    %       by exchange and symbol. MATLAB field names must be valid
    %       identifiers, so both names pass through matlab.lang.makeValidName:
    %       'M&M' becomes M_M, 'BAJAJ-AUTO' becomes BAJAJ_AUTO and a name
    %       that starts with a digit gets an x prefix. The raw data is
    %       also available in the ltp_data, quotes_data and depth_data maps
    %       (containers.Map) under the original 'EXCHANGE:SYMBOL' key.
    %
    %   Example:
    %       client = openalgo.api('your_api_key', 'http://127.0.0.1:5000');
    %       client.connect();
    %       ins = {struct('exchange','NSE','symbol','RELIANCE')};
    %       client.subscribe_ltp(ins, @(d) disp(d.data.ltp));
    %       pause(10);
    %       r = client.get_ltp();
    %       client.unsubscribe_ltp(ins);
    %       client.disconnect();
    %
    %   See also openalgo.api.

    properties
        verbose = 0             % logging level: 0 silent, 1 basic, 2 full debug
        ws_port = 8765          % WebSocket server port
        ws_host = ''            % host derived from the REST host (unset when ws_url is given)
        ws_url = ''             % WebSocket URL used by connect
        ws = []                 % current openalgo.internal.WebSocketClient, or []
        connected = false       % true while the socket is open
        authenticated = false   % true after a successful auth reply
        ltp_data                % containers.Map 'EXCHANGE:SYMBOL' -> struct(price, timestamp)
        quotes_data             % containers.Map 'EXCHANGE:SYMBOL' -> quote struct
        depth_data              % containers.Map 'EXCHANGE:SYMBOL' -> struct(ltp, timestamp, depth)
        order_data = {}         % order_update messages, most recent first (max 500)
        ltp_callback = []       % function handle called with each LTP update
        quote_callback = []     % function handle called with each Quote update
        quotes_callback = []    % reserved, kept for parity with the Python SDK
        depth_callback = []     % function handle called with each Depth update
        order_callback = []     % function handle called with each order update
        auto_reconnect = true   % reconnect and replay subscriptions after a drop
    end

    properties (Hidden, SetAccess = protected)
        shutting_down = false       % set by disconnect() to suppress reconnects
        orders_subscribed = false   % replay subscribe_orders after a reconnect
        active_subs = {}            % 1x3 cell (modes 1 to 3) of struct(keys, entries)
        reconnect_active = false    % a reconnect sequence is in progress
        reconnect_attempt = 0       % attempts made in the current sequence
        reconnect_due = Inf         % feed clock time of the next attempt (no timer fallback)
        poll_timer = []             % fixed spacing timer that reads the socket
        reconnect_timer = []        % single shot timer for the next reconnect attempt
        feed_clock = []             % tic reference for the feed clock
        pending_replies = {}        % requests waiting for a reply: struct(id, types, done, reply)
        next_reply_id = 0
    end

    properties (Hidden)
        ping_interval = 20                  % seconds between keepalive pings
        ping_timeout = 10                   % seconds to wait for a pong
        reconnect_backoffs = [1 2 5 10 30 60] % reconnect delays in seconds (last one repeats)
        poll_period = 0.05                  % poll timer period in seconds
        log_sink = []                       % optional function handle that receives each log line instead of stdout
        tls_transport = 'auto'              % wss:// transport: 'auto', 'dotnet', 'python' or 'java'
        tls_verify = true                   % verify server certificates; false only for tests with self-signed certificates
        tls_ca_file = ''                    % PEM file of extra trusted CA certificates (private CA); the host name is still verified
    end

    properties (Constant, Hidden)
        FEED_ORDER_HISTORY = 500
        FEED_MODE_NAMES = {'LTP', 'Quote', 'Depth'}
    end

    methods
        function obj = FeedAPI()
            %FEEDAPI Initialise the feed state with default settings.
            %   Subclasses call initFeed(host, ws_port, ws_url, verbose,
            %   auto_reconnect) to apply their own settings.
            obj.initFeed();
        end

        function ok = connect(obj)
            %CONNECT Connect to the WebSocket server and authenticate.
            %   ok = client.connect() opens the WebSocket at client.ws_url,
            %   sends the API key and waits up to 5 seconds for the
            %   authentication reply.
            %
            %   Outputs:
            %       ok  true if the connection and authentication succeed,
            %           false otherwise.
            %
            %   Example:
            %       if ~client.connect(), error('feed not available'); end
            obj.shutting_down = false;
            ok = obj.doConnect();
        end

        function disconnect(obj)
            %DISCONNECT Disconnect from the WebSocket server.
            %   client.disconnect() closes the connection, waits up to 2
            %   seconds for the close handshake, stops the feed timers and
            %   suppresses auto-reconnect.
            %
            %   Example:
            %       client.disconnect();
            obj.shutting_down = true;
            obj.reconnect_active = false;
            obj.reconnect_due = Inf;
            obj.killTimer('reconnect_timer');
            ws = obj.ws;
            if ~isempty(ws) && isvalid(ws)
                try
                    ws.close();
                catch
                end
                started = tic;
                while obj.connected && ~ws.isClosed() && ~ws.PumpBusy && toc(started) < 2
                    obj.feedPump();
                    if obj.connected && ~ws.isClosed()
                        pause(0.02);
                    end
                end
                if ~ws.isClosed()
                    ws.abort();
                end
                if ~ws.CloseHandled
                    ws.CloseHandled = true;
                    obj.onClosed();
                end
                obj.ws = [];
                obj.connected = false;
                obj.authenticated = false;
            end
            obj.killTimer('poll_timer');
        end

        function ok = subscribe_ltp(obj, varargin)
            %SUBSCRIBE_LTP Subscribe to LTP updates for instruments.
            %   ok = client.subscribe_ltp(instruments)
            %   ok = client.subscribe_ltp(instruments, on_data_received)
            %   ok = client.subscribe_ltp(instruments, on_data_received=@cb)
            %
            %   Inputs:
            %       instruments       cell array of structs or struct array
            %                         with fields exchange, symbol and
            %                         optionally exchange_token
            %       on_data_received  optional function handle called with
            %                         struct(type, symbol, exchange, mode,
            %                         data) where data has ltp, timestamp
            %                         and ltt when the server sends it
            %
            %   Outputs:
            %       ok  true if the subscription request was sent
            %
            %   Example:
            %       client.subscribe_ltp({struct('exchange','NSE','symbol','INFY')}, ...
            %           @(d) fprintf('%s %g\n', d.symbol, d.data.ltp));
            opts = openalgo.FeedAPI.feedParseArgs(varargin, {'instruments', 'on_data_received'}, {[], []}, 'subscribe_ltp', 1);
            ok = obj.subscribeMode(1, opts.instruments, opts.on_data_received, 'ltp_callback');
        end

        function ok = unsubscribe_ltp(obj, varargin)
            %UNSUBSCRIBE_LTP Unsubscribe from LTP updates for instruments.
            %   ok = client.unsubscribe_ltp(instruments) sends one bulk
            %   unsubscribe request, forgets the instruments for reconnect
            %   replay and removes their cached LTP data.
            %
            %   Inputs:
            %       instruments  cell array of structs or struct array with
            %                    fields exchange, symbol and optionally
            %                    exchange_token
            %
            %   Outputs:
            %       ok  true if the request was sent, false when not
            %           connected, not authenticated or no valid instrument
            %
            %   Example:
            %       client.unsubscribe_ltp({struct('exchange','NSE','symbol','INFY')});
            opts = openalgo.FeedAPI.feedParseArgs(varargin, {'instruments'}, {[]}, 'unsubscribe_ltp', 1);
            ok = obj.unsubscribeMode(1, opts.instruments);
        end

        function ok = subscribe_quote(obj, varargin)
            %SUBSCRIBE_QUOTE Subscribe to Quote updates for instruments.
            %   ok = client.subscribe_quote(instruments)
            %   ok = client.subscribe_quote(instruments, on_data_received)
            %
            %   Inputs:
            %       instruments       cell array of structs or struct array
            %                         with fields exchange, symbol and
            %                         optionally exchange_token
            %       on_data_received  optional function handle called with
            %                         struct(type, symbol, exchange, mode,
            %                         data) where data holds open, high,
            %                         low, close, ltp, volume,
            %                         last_trade_quantity, avg_trade_price,
            %                         change, change_percent and timestamp
            %
            %   Outputs:
            %       ok  true if the subscription request was sent
            %
            %   Example:
            %       client.subscribe_quote({struct('exchange','NSE','symbol','TCS')});
            opts = openalgo.FeedAPI.feedParseArgs(varargin, {'instruments', 'on_data_received'}, {[], []}, 'subscribe_quote', 1);
            ok = obj.subscribeMode(2, opts.instruments, opts.on_data_received, 'quote_callback');
        end

        function ok = unsubscribe_quote(obj, varargin)
            %UNSUBSCRIBE_QUOTE Unsubscribe from Quote updates for instruments.
            %   ok = client.unsubscribe_quote(instruments) sends one bulk
            %   unsubscribe request, forgets the instruments for reconnect
            %   replay and removes their cached quote data.
            %
            %   Inputs:
            %       instruments  cell array of structs or struct array
            %
            %   Outputs:
            %       ok  true if the request was sent
            %
            %   Example:
            %       client.unsubscribe_quote({struct('exchange','NSE','symbol','TCS')});
            opts = openalgo.FeedAPI.feedParseArgs(varargin, {'instruments'}, {[]}, 'unsubscribe_quote', 1);
            ok = obj.unsubscribeMode(2, opts.instruments);
        end

        function ok = subscribe_depth(obj, varargin)
            %SUBSCRIBE_DEPTH Subscribe to Market Depth updates for instruments.
            %   ok = client.subscribe_depth(instruments)
            %   ok = client.subscribe_depth(instruments, on_data_received)
            %   ok = client.subscribe_depth(instruments, on_data_received, depth)
            %   ok = client.subscribe_depth(instruments, depth=20)
            %
            %   Inputs:
            %       instruments       cell array of structs or struct array
            %                         with fields exchange, symbol and
            %                         optionally exchange_token
            %       on_data_received  optional function handle called with
            %                         struct(type, symbol, exchange, mode,
            %                         data) where data holds ltp, timestamp
            %                         and depth; depth.buy and depth.sell
            %                         are cell arrays of level structs
            %                         (price, quantity, orders) as sent by
            %                         the server
            %       depth             optional number of book levels to
            %                         request (default 5). 20, 30 or 50
            %                         levels depend on the broker; a broker
            %                         that refuses the level reports it in
            %                         the subscribe acknowledgement, which
            %                         is logged.
            %
            %   Outputs:
            %       ok  true if the subscription request was sent
            %
            %   Example:
            %       client.subscribe_depth({struct('exchange','NSE','symbol','SBIN')});
            %       client.subscribe_depth({struct('exchange','NSE','symbol','SBIN')}, depth=20);
            opts = openalgo.FeedAPI.feedParseArgs(varargin, {'instruments', 'on_data_received', 'depth'}, {[], [], 5}, 'subscribe_depth', 1);
            depth = opts.depth;
            if isempty(depth)
                depth = 5;
            end
            if ~(isnumeric(depth) && isscalar(depth) && depth >= 1 && depth == fix(depth))
                error('openalgo:FeedAPI:badArgument', 'subscribe_depth() depth must be a positive whole number');
            end
            ok = obj.subscribeMode(3, opts.instruments, opts.on_data_received, 'depth_callback', double(depth));
        end

        function ok = unsubscribe_depth(obj, varargin)
            %UNSUBSCRIBE_DEPTH Unsubscribe from Market Depth updates for instruments.
            %   ok = client.unsubscribe_depth(instruments) sends one bulk
            %   unsubscribe request, forgets the instruments for reconnect
            %   replay and removes their cached depth data.
            %
            %   Inputs:
            %       instruments  cell array of structs or struct array
            %
            %   Outputs:
            %       ok  true if the request was sent
            %
            %   Example:
            %       client.unsubscribe_depth({struct('exchange','NSE','symbol','SBIN')});
            opts = openalgo.FeedAPI.feedParseArgs(varargin, {'instruments'}, {[]}, 'unsubscribe_depth', 1);
            ok = obj.unsubscribeMode(3, opts.instruments);
        end

        function ok = subscribe_orders(obj, varargin)
            %SUBSCRIBE_ORDERS Subscribe to real-time order updates for the account.
            %   ok = client.subscribe_orders()
            %   ok = client.subscribe_orders(on_order_update)
            %
            %   Order updates report asynchronous status changes after an
            %   order is placed: fills, partial fills, rejections and
            %   cancellations. No symbols are involved.
            %
            %   Inputs:
            %       on_order_update  optional function handle called with
            %                        each order_update message as a struct
            %                        (type, orderid, symbol, exchange,
            %                        action, quantity, pricetype, product,
            %                        order_status, filled_quantity,
            %                        pending_quantity, average_price,
            %                        rejection_reason, broker)
            %
            %   Outputs:
            %       ok  true if the subscription request was sent
            %
            %   Example:
            %       client.subscribe_orders(@(o) disp(o.order_status));
            opts = openalgo.FeedAPI.feedParseArgs(varargin, {'on_order_update'}, {[]}, 'subscribe_orders', 0);
            ok = false;
            if ~obj.connected
                obj.logMsg(1, 'ERROR', 'Not connected to WebSocket server');
                return
            end
            if ~obj.authenticated
                obj.logMsg(1, 'ERROR', 'Not authenticated with WebSocket server');
                return
            end
            if openalgo.FeedAPI.isTruthy(opts.on_order_update)
                obj.order_callback = opts.on_order_update;
            end
            obj.logMsg(1, 'SUB', 'Subscribing to order updates...');
            try
                obj.ws.send(jsonencode(struct('action', 'subscribe_orders')));
                obj.orders_subscribed = true;
                ok = true;
            catch err
                obj.logMsg(1, 'ERROR', ['Error sending order subscription: ' err.message]);
            end
        end

        function ok = unsubscribe_orders(obj)
            %UNSUBSCRIBE_ORDERS Unsubscribe from real-time order updates.
            %   ok = client.unsubscribe_orders()
            %
            %   Outputs:
            %       ok  true if the unsubscription request was sent
            %
            %   Example:
            %       client.unsubscribe_orders();
            ok = false;
            if ~obj.connected || ~obj.authenticated
                return
            end
            obj.logMsg(1, 'UNSUB', 'Unsubscribing from order updates');
            obj.orders_subscribed = false;
            try
                obj.ws.send(jsonencode(struct('action', 'unsubscribe_orders')));
                ok = true;
            catch err
                obj.logMsg(1, 'ERROR', ['Error sending order unsubscription: ' err.message]);
            end
        end

        function result = get_orders(obj)
            %GET_ORDERS Order updates received so far, most recent first.
            %   result = client.get_orders()
            %
            %   Outputs:
            %       result  struct with field orders: a cell array of
            %               order_update message structs, most recent
            %               first, at most 500 entries
            %
            %   Example:
            %       r = client.get_orders();
            %       if ~isempty(r.orders), disp(r.orders{1}.order_status); end
            result = struct('orders', {obj.order_data});
        end

        function result = get_ltp(obj, varargin)
            %GET_LTP Latest LTP data in nested format.
            %   result = client.get_ltp()
            %   result = client.get_ltp(exchange)
            %   result = client.get_ltp(exchange, symbol)
            %   result = client.get_ltp(exchange='NSE', symbol='INFY')
            %
            %   Inputs:
            %       exchange  optional exchange filter
            %       symbol    optional symbol filter
            %
            %   Outputs:
            %       result  struct with field ltp; result.ltp.EXCHANGE.SYMBOL
            %               is struct(timestamp, ltp). Exchange and symbol
            %               field names pass through matlab.lang.makeValidName
            %               (for example 'M&M' becomes M_M). With no data
            %               result is struct('ltp', struct()).
            %
            %   Example:
            %       r = client.get_ltp('NSE', 'INFY');
            %       price = r.ltp.NSE.INFY.ltp;
            opts = openalgo.FeedAPI.feedParseArgs(varargin, {'exchange', 'symbol'}, {[], []}, 'get_ltp', 0);
            out = struct();
            mapKeys = obj.ltp_data.keys();
            for i = 1:numel(mapKeys)
                [ex, sym, ok] = openalgo.FeedAPI.feedSplitKey(mapKeys{i}, opts.exchange, opts.symbol);
                if ~ok
                    continue
                end
                data = obj.ltp_data(mapKeys{i});
                entry = struct();
                entry.timestamp = data.timestamp;
                entry.ltp = data.price;
                out.(matlab.lang.makeValidName(ex)).(matlab.lang.makeValidName(sym)) = entry;
            end
            result = struct('ltp', out);
        end

        function result = get_quotes(obj, varargin)
            %GET_QUOTES Latest Quote data in nested format.
            %   result = client.get_quotes()
            %   result = client.get_quotes(exchange)
            %   result = client.get_quotes(exchange, symbol)
            %
            %   Inputs:
            %       exchange  optional exchange filter
            %       symbol    optional symbol filter
            %
            %   Outputs:
            %       result  struct with field quote;
            %               result.quote.EXCHANGE.SYMBOL has fields
            %               timestamp, open, high, low, close, ltp, volume,
            %               last_trade_quantity, avg_trade_price, change and
            %               change_percent. Field names pass through
            %               matlab.lang.makeValidName. With no data result is
            %               struct('quote', struct()).
            %
            %   Example:
            %       r = client.get_quotes('NSE', 'TCS');
            %       q = r.quote.NSE.TCS;
            opts = openalgo.FeedAPI.feedParseArgs(varargin, {'exchange', 'symbol'}, {[], []}, 'get_quotes', 0);
            out = struct();
            mapKeys = obj.quotes_data.keys();
            for i = 1:numel(mapKeys)
                [ex, sym, ok] = openalgo.FeedAPI.feedSplitKey(mapKeys{i}, opts.exchange, opts.symbol);
                if ~ok
                    continue
                end
                data = obj.quotes_data(mapKeys{i});
                entry = struct();
                entry.timestamp = data.timestamp;
                entry.open = data.open;
                entry.high = data.high;
                entry.low = data.low;
                entry.close = data.close;
                entry.ltp = data.ltp;
                entry.volume = openalgo.FeedAPI.getf(data, 'volume', 0);
                entry.last_trade_quantity = openalgo.FeedAPI.getf(data, 'last_trade_quantity', 0);
                entry.avg_trade_price = openalgo.FeedAPI.getf(data, 'avg_trade_price', 0);
                entry.change = openalgo.FeedAPI.getf(data, 'change', 0);
                entry.change_percent = openalgo.FeedAPI.getf(data, 'change_percent', 0);
                out.(matlab.lang.makeValidName(ex)).(matlab.lang.makeValidName(sym)) = entry;
            end
            result = struct('quote', out);
        end

        function result = get_depth(obj, varargin)
            %GET_DEPTH Latest Market Depth data in nested format.
            %   result = client.get_depth()
            %   result = client.get_depth(exchange)
            %   result = client.get_depth(exchange, symbol)
            %
            %   Inputs:
            %       exchange  optional exchange filter
            %       symbol    optional symbol filter
            %
            %   Outputs:
            %       result  struct with field depth;
            %               result.depth.EXCHANGE.SYMBOL has fields
            %               timestamp, ltp, buyBook and sellBook. Each book
            %               is a 1xN struct array (N at least 5) with fields
            %               price, qty and orders (doubles). Missing levels
            %               are padded with zeros and missing or empty values
            %               read as 0. buyBook(1) is the best bid. Field
            %               names pass through matlab.lang.makeValidName.
            %
            %   Example:
            %       r = client.get_depth('NSE', 'SBIN');
            %       bestBid = r.depth.NSE.SBIN.buyBook(1).price;
            opts = openalgo.FeedAPI.feedParseArgs(varargin, {'exchange', 'symbol'}, {[], []}, 'get_depth', 0);
            out = struct();
            mapKeys = obj.depth_data.keys();
            for i = 1:numel(mapKeys)
                [ex, sym, ok] = openalgo.FeedAPI.feedSplitKey(mapKeys{i}, opts.exchange, opts.symbol);
                if ~ok
                    continue
                end
                data = obj.depth_data(mapKeys{i});
                entry = struct();
                entry.timestamp = openalgo.FeedAPI.getf(data, 'timestamp', openalgo.FeedAPI.nowMs());
                entry.ltp = openalgo.FeedAPI.getf(data, 'ltp', 0);
                depth = openalgo.FeedAPI.getf(data, 'depth', struct());
                entry.buyBook = openalgo.FeedAPI.feedBook(openalgo.FeedAPI.getf(depth, 'buy', {}));
                entry.sellBook = openalgo.FeedAPI.feedBook(openalgo.FeedAPI.getf(depth, 'sell', {}));
                out.(matlab.lang.makeValidName(ex)).(matlab.lang.makeValidName(sym)) = entry;
            end
            result = struct('depth', out);
        end

        function ok = unsubscribe_all(obj)
            %UNSUBSCRIBE_ALL Unsubscribe from every symbol in every mode.
            %   ok = client.unsubscribe_all() sends {"action":"unsubscribe_all"},
            %   forgets all LTP, Quote and Depth subscriptions so a reconnect
            %   does not replay them, and clears the cached ltp, quote and
            %   depth data. The order update subscription is not changed.
            %   Addition beyond the Python SDK.
            %
            %   Outputs:
            %       ok  true if the request was sent, false when not
            %           connected or not authenticated
            %
            %   Example:
            %       client.unsubscribe_all();
            ok = false;
            if ~obj.connected || ~obj.authenticated
                return
            end
            obj.logMsg(1, 'UNSUB', 'Unsubscribing from all symbols');
            empty = struct('keys', {{}}, 'entries', {{}}, 'depths', zeros(1, 0));
            obj.active_subs = {empty, empty, empty};
            stores = {obj.ltp_data, obj.quotes_data, obj.depth_data};
            for i = 1:numel(stores)
                if stores{i}.Count > 0
                    stores{i}.remove(stores{i}.keys());
                end
            end
            try
                obj.ws.send(jsonencode(struct('action', 'unsubscribe_all')));
                ok = true;
            catch err
                obj.logMsg(1, 'ERROR', ['Error sending unsubscribe_all: ' err.message]);
            end
        end

        function reply = get_broker_info(obj, varargin)
            %GET_BROKER_INFO Ask the server which broker serves this session.
            %   reply = client.get_broker_info()
            %   reply = client.get_broker_info(timeout)
            %   reply = client.get_broker_info(timeout=2)
            %
            %   Sends {"action":"get_broker_info"} and keeps processing the
            %   feed (market data and callbacks continue) until the reply
            %   arrives. Addition beyond the Python SDK.
            %
            %   Inputs:
            %       timeout  seconds to wait (default 5)
            %
            %   Outputs:
            %       reply  the server reply struct (type 'broker_info',
            %              status, broker, adapter_status, user_id), the
            %              server error struct (status 'error', code,
            %              message), or struct(status='error', message=...)
            %              when not connected, not authenticated or timed out
            %
            %   Example:
            %       info = client.get_broker_info();
            %       disp(info.broker);
            opts = openalgo.FeedAPI.feedParseArgs(varargin, {'timeout'}, {5}, 'get_broker_info', 0);
            reply = obj.request(jsonencode(struct('action', 'get_broker_info')), {'broker_info'}, opts.timeout);
        end

        function reply = get_supported_brokers(obj, varargin)
            %GET_SUPPORTED_BROKERS Ask the server for its configured brokers.
            %   reply = client.get_supported_brokers()
            %   reply = client.get_supported_brokers(timeout)
            %
            %   Sends {"action":"get_supported_brokers"} and keeps processing
            %   the feed until the reply arrives. Addition beyond the Python
            %   SDK.
            %
            %   Inputs:
            %       timeout  seconds to wait (default 5)
            %
            %   Outputs:
            %       reply  the server reply struct (type 'supported_brokers',
            %              status, brokers, count), the server error struct,
            %              or struct(status='error', message=...) when not
            %              connected, not authenticated or timed out
            %
            %   Example:
            %       r = client.get_supported_brokers();
            %       disp(r.brokers);
            opts = openalgo.FeedAPI.feedParseArgs(varargin, {'timeout'}, {5}, 'get_supported_brokers', 0);
            reply = obj.request(jsonencode(struct('action', 'get_supported_brokers')), {'supported_brokers'}, opts.timeout);
        end

        function reply = ws_ping(obj, varargin)
            %WS_PING Application level ping that measures the round trip.
            %   reply = client.ws_ping()
            %   reply = client.ws_ping(timeout)
            %
            %   Sends {"action":"ping","timestamp":<epoch ms>} and waits for
            %   the server's pong while processing the feed. This is separate
            %   from the WebSocket control pings, which the client answers on
            %   its own. Addition beyond the Python SDK.
            %
            %   Inputs:
            %       timeout  seconds to wait (default 5)
            %
            %   Outputs:
            %       reply  the pong struct (type 'pong', status,
            %              server_timestamp, client_timestamp) plus
            %              latency_ms, the measured round trip in
            %              milliseconds; or struct(status='error',
            %              message=...) when not connected, not
            %              authenticated or timed out
            %
            %   Example:
            %       p = client.ws_ping();
            %       fprintf('round trip %.1f ms\n', p.latency_ms);
            opts = openalgo.FeedAPI.feedParseArgs(varargin, {'timeout'}, {5}, 'ws_ping', 0);
            started = tic;
            text = sprintf('{"action":"ping","timestamp":%d}', openalgo.FeedAPI.nowMs());
            reply = obj.request(text, {'pong'}, opts.timeout);
            if openalgo.FeedAPI.isText(openalgo.FeedAPI.getf(reply, 'type', []), 'pong')
                reply.latency_ms = toc(started) * 1000;
            end
        end

        function wait(obj, seconds)
            %WAIT Keep processing the feed for a number of seconds.
            %   client.wait(seconds) reads the socket, runs callbacks and
            %   lets reconnect attempts run until the time has passed. Use
            %   it in matlab -batch scripts where nothing else keeps MATLAB
            %   idle. pause(seconds) has the same effect while the feed
            %   timers are running.
            %
            %   Inputs:
            %       seconds  time to wait (default 1)
            %
            %   Example:
            %       client.subscribe_ltp(ins);
            %       client.wait(30);
            %       disp(client.get_ltp());
            if nargin < 2 || isempty(seconds)
                seconds = 1;
            end
            started = tic;
            while true
                obj.feedPump();
                obj.feedServiceReconnect();
                left = seconds - toc(started);
                if left <= 0
                    break
                end
                pause(min(0.02, left));
            end
        end

        function delete(obj)
            %DELETE Stop the feed timers and close the socket.
            obj.shutting_down = true;
            obj.killTimer('reconnect_timer');
            obj.killTimer('poll_timer');
            ws = obj.ws;
            if ~isempty(ws) && isvalid(ws)
                ws.CloseHandled = true;
                try
                    ws.close();
                catch
                end
                try
                    ws.abort();
                catch
                end
            end
        end
    end

    methods (Hidden)
        function feedProcessMessage(obj, messageStr)
            %FEEDPROCESSMESSAGE Handle one incoming text message (Python _process_message).
            messageStr = char(messageStr);
            try
                message = jsondecode(messageStr);
            catch
                obj.logMsg(1, 'ERROR', ['Invalid JSON message: ' messageStr(1:min(100, end)) '...']);
                return
            end
            try
                obj.handleMessage(message);
            catch err
                obj.logMsg(1, 'ERROR', ['Error handling message: ' err.message]);
            end
        end

        function feedPump(obj)
            %FEEDPUMP Read the socket once and process the complete messages.
            ws = obj.ws;
            if isempty(ws) || ~isvalid(ws) || ws.PumpBusy
                return
            end
            ws.PumpBusy = true;
            guard = onCleanup(@() openalgo.FeedAPI.releasePump(ws));
            msgs = ws.poll();
            for i = 1:numel(msgs)
                obj.feedProcessMessage(msgs{i});
                if ~obj.isCurrentWs(ws)
                    break
                end
            end
            if ws.isClosed() && ~ws.CloseHandled && obj.isCurrentWs(ws)
                ws.CloseHandled = true;
                if ~isempty(ws.LastError)
                    obj.logMsg(1, 'ERROR', ['WebSocket error: ' ws.LastError]);
                end
                obj.onClosed();
            end
            clear guard
        end

        function feedOnPollTimer(obj)
            %FEEDONPOLLTIMER Poll timer callback.
            try
                obj.feedPump();
            catch err
                obj.logMsg(1, 'ERROR', ['Feed poll error: ' err.message]);
            end
        end

        function feedOnReconnectTimer(obj)
            %FEEDONRECONNECTTIMER Reconnect timer callback.
            % The firing timer deletes itself through its StopFcn.
            obj.reconnect_timer = [];
            obj.reconnect_due = -Inf;
            obj.feedServiceReconnect();
        end

        function feedServiceReconnect(obj)
            %FEEDSERVICERECONNECT Run the reconnect attempt when it is due.
            t = obj.reconnect_timer;
            if ~obj.reconnect_active || (~isempty(t) && isvalid(t)) || ...
                    toc(obj.feed_clock) < obj.reconnect_due
                return
            end
            obj.reconnect_due = Inf;
            try
                obj.runReconnectAttempt();
            catch err
                obj.logMsg(1, 'ERROR', ['Reconnect error: ' err.message]);
                obj.reconnect_active = false;
            end
        end
    end

    methods (Access = protected)
        function initFeed(obj, host, ws_port, ws_url, verbose, auto_reconnect)
            %INITFEED Apply feed settings and reset the feed state.
            %   initFeed(obj, host, ws_port, ws_url, verbose, auto_reconnect)
            %   derives ws_url from host when ws_url is empty:
            %     http:// host (or no scheme), as in the Python SDK: the
            %       scheme is removed, the rest is cut at the first '/' and
            %       then at the first ':', giving ws://HOST:WS_PORT.
            %     https:// host (a server hosted OpenAlgo, which serves the
            %       feed behind the web server): wss://HOST[:PORT]/ws, with
            %       the host and port exactly as given and ws_port unused.
            %   A non-empty ws_url is used as given. verbose false gives 0,
            %   otherwise double(verbose).
            if nargin < 2 || isempty(host)
                host = 'http://127.0.0.1:5000';
            end
            if nargin < 3 || isempty(ws_port)
                ws_port = 8765;
            end
            if nargin < 4
                ws_url = [];
            end
            if nargin < 5 || isempty(verbose)
                verbose = false;
            end
            if nargin < 6 || isempty(auto_reconnect)
                auto_reconnect = true;
            end

            % Stop any feed activity of an earlier initialisation.
            obj.killTimer('reconnect_timer');
            obj.killTimer('poll_timer');
            if ~isempty(obj.ws) && isvalid(obj.ws)
                obj.ws.CloseHandled = true;
                try
                    obj.ws.abort();
                catch
                end
            end

            if islogical(verbose) && ~verbose
                obj.verbose = 0;
            else
                obj.verbose = double(verbose);
            end
            obj.ws_port = ws_port;
            if openalgo.FeedAPI.isTruthy(ws_url)
                obj.ws_url = char(ws_url);
            else
                h = char(host);
                secure = startsWith(h, 'https://');
                if startsWith(h, 'http://')
                    h = h(8:end);
                elseif secure
                    h = h(9:end);
                end
                hostPort = char(regexp(h, '^[^/]*', 'match', 'once'));
                obj.ws_host = char(regexp(hostPort, '^[^:]*', 'match', 'once'));
                if secure
                    obj.ws_url = ['wss://' hostPort '/ws'];
                else
                    obj.ws_url = ['ws://' obj.ws_host ':' openalgo.FeedAPI.pyStr(ws_port)];
                end
            end
            obj.ws = [];
            obj.connected = false;
            obj.authenticated = false;

            obj.ltp_data = containers.Map('KeyType', 'char', 'ValueType', 'any');
            obj.quotes_data = containers.Map('KeyType', 'char', 'ValueType', 'any');
            obj.depth_data = containers.Map('KeyType', 'char', 'ValueType', 'any');

            obj.ltp_callback = [];
            obj.quote_callback = [];
            obj.quotes_callback = [];
            obj.depth_callback = [];
            obj.order_callback = [];

            obj.order_data = {};
            obj.orders_subscribed = false;

            obj.auto_reconnect = logical(auto_reconnect);
            obj.shutting_down = false;
            obj.reconnect_active = false;
            obj.reconnect_attempt = 0;
            obj.reconnect_due = Inf;
            obj.feed_clock = tic;
            empty = struct('keys', {{}}, 'entries', {{}}, 'depths', zeros(1, 0));
            obj.active_subs = {empty, empty, empty};
        end
    end

    methods (Access = private)
        function logMsg(obj, level, category, message)
            % Python _log: fixed width category then the message.
            if obj.verbose >= level
                obj.emit(sprintf('%-8s %s', ['[' category ']'], message));
            end
        end

        function emit(obj, line)
            % Print one output line, or hand it to log_sink when set.
            if isempty(obj.log_sink)
                fprintf('%s\n', line);
            else
                try
                    feval(obj.log_sink, line);
                catch
                    fprintf('%s\n', line);
                end
            end
        end

        function reply = request(obj, text, types, timeout)
            % Send one request and process the feed until a reply of one of
            % the given types (or a server error) arrives.
            if isempty(timeout)
                timeout = 5;
            end
            if ~obj.connected
                obj.logMsg(1, 'ERROR', 'Not connected to WebSocket server');
                reply = struct('status', 'error', 'message', 'Not connected to WebSocket server');
                return
            end
            if ~obj.authenticated
                obj.logMsg(1, 'ERROR', 'Not authenticated with WebSocket server');
                reply = struct('status', 'error', 'message', 'Not authenticated with WebSocket server');
                return
            end
            obj.next_reply_id = obj.next_reply_id + 1;
            id = obj.next_reply_id;
            obj.pending_replies{end + 1} = struct('id', id, 'types', {types}, 'done', false, 'reply', []);
            cleanup = onCleanup(@() obj.dropPendingReply(id));
            try
                obj.ws.send(text);
            catch err
                obj.logMsg(1, 'ERROR', ['Error sending request: ' err.message]);
                reply = struct('status', 'error', 'message', err.message);
                return
            end
            started = tic;
            while true
                obj.feedPump();
                waiter = obj.findPendingReply(id);
                if isempty(waiter) || waiter.done || toc(started) >= timeout || ~obj.connected
                    break
                end
                pause(0.01);
            end
            if ~isempty(waiter) && waiter.done
                reply = waiter.reply;
            elseif ~obj.connected
                reply = struct('status', 'error', 'message', 'Connection closed while waiting for the reply');
            else
                reply = struct('status', 'error', 'message', ...
                    sprintf('Timed out waiting for the %s reply', strjoin(types, '/')));
                obj.logMsg(1, 'ERROR', reply.message);
            end
            clear cleanup
        end

        function waiter = findPendingReply(obj, id)
            waiter = [];
            for i = 1:numel(obj.pending_replies)
                if obj.pending_replies{i}.id == id
                    waiter = obj.pending_replies{i};
                    return
                end
            end
        end

        function dropPendingReply(obj, id)
            if ~isvalid(obj)
                return
            end
            keep = true(1, numel(obj.pending_replies));
            for i = 1:numel(obj.pending_replies)
                keep(i) = obj.pending_replies{i}.id ~= id;
            end
            obj.pending_replies = obj.pending_replies(keep);
        end

        function matchPendingReply(obj, msgType, message)
            % Hand a reply to the oldest request waiting for its type.
            for i = 1:numel(obj.pending_replies)
                w = obj.pending_replies{i};
                if ~w.done && (any(strcmp(msgType, w.types)) || strcmp(msgType, 'error'))
                    w.done = true;
                    w.reply = message;
                    obj.pending_replies{i} = w;
                    return
                end
            end
        end

        function ok = doConnect(obj)
            % Open one connection and wait for authentication (Python _do_connect).
            ok = false;
            try
                obj.discardSocket();
                try
                    client = openalgo.internal.WebSocketClient(obj.ws_url, ...
                        'PingInterval', obj.ping_interval, 'PingTimeout', obj.ping_timeout, ...
                        'TlsTransport', obj.tls_transport, 'VerifyCertificate', obj.tls_verify, ...
                        'CaFile', obj.tls_ca_file);
                    client.open(5);
                catch err
                    % Python: on_error, then on_close, then the connect wait gives up.
                    obj.logMsg(1, 'ERROR', ['WebSocket error: ' err.message]);
                    obj.onClosed();
                    obj.logMsg(1, 'ERROR', 'Failed to connect to WebSocket server');
                    return
                end
                obj.ws = client;
                obj.startPollTimer();
                obj.logMsg(1, 'WS', ['Connected to ' obj.ws_url]);
                obj.connected = true;
                obj.authenticate();

                started = tic;
                while ~obj.authenticated && obj.connected && toc(started) < 5
                    obj.feedPump();
                    if ~obj.authenticated && obj.connected
                        pause(0.02);
                    end
                end
                ok = logical(obj.authenticated);
            catch err
                obj.logMsg(1, 'ERROR', ['Error connecting to WebSocket: ' err.message]);
                ok = false;
            end
        end

        function authenticate(obj)
            % Send the API key (Python _authenticate).
            if ~obj.connected
                obj.logMsg(1, 'ERROR', 'Cannot authenticate: not connected');
                return
            end
            key = obj.api_key;
            if isstring(key)
                key = char(key);
            end
            msg = struct();
            msg.action = 'authenticate';
            msg.api_key = key;
            keyText = openalgo.FeedAPI.pyStr(key);
            masked = [keyText(1:min(8, end)) '...' keyText(max(1, end - 7):end)];
            obj.logMsg(1, 'AUTH', ['Authenticating with API key: ' masked]);
            obj.ws.send(jsonencode(msg));
        end

        function onClosed(obj)
            % Python on_close.
            obj.logMsg(1, 'WS', ['Disconnected from ' obj.ws_url]);
            obj.connected = false;
            obj.authenticated = false;
            if obj.auto_reconnect && ~obj.shutting_down
                obj.scheduleReconnect();
            end
        end

        function discardSocket(obj)
            % Close a previous socket quietly before opening a new one.
            ws = obj.ws;
            obj.ws = [];
            if ~isempty(ws) && isvalid(ws)
                ws.CloseHandled = true;
                try
                    ws.close();
                catch
                end
                try
                    ws.abort();
                catch
                end
            end
        end

        function tf = isCurrentWs(obj, ws)
            cur = obj.ws;
            tf = ~isempty(cur) && isvalid(cur) && cur == ws;
        end

        function scheduleReconnect(obj)
            % Start a reconnect sequence unless one is running (Python _schedule_reconnect).
            if obj.shutting_down || ~obj.auto_reconnect
                return
            end
            if obj.reconnect_active
                return
            end
            obj.reconnect_active = true;
            obj.reconnect_attempt = 0;
            obj.scheduleReconnectAttempt();
        end

        function scheduleReconnectAttempt(obj)
            backoffs = obj.reconnect_backoffs;
            delay = backoffs(min(obj.reconnect_attempt + 1, numel(backoffs)));
            obj.logMsg(1, 'WS', sprintf('Reconnect attempt %d in %ss...', ...
                obj.reconnect_attempt + 1, openalgo.FeedAPI.pyStr(delay)));
            obj.killTimer('reconnect_timer');
            obj.reconnect_due = toc(obj.feed_clock) + delay;
            try
                t = timer('Name', 'openalgo-feed-reconnect', ...
                    'ExecutionMode', 'singleShot', ...
                    'StartDelay', round(max(0, delay) * 1000) / 1000, ...
                    'TimerFcn', @(~, ~) obj.feedOnReconnectTimer(), ...
                    'StopFcn', @(src, ~) openalgo.FeedAPI.deleteTimer(src), ...
                    'ErrorFcn', @(~, evt) openalgo.FeedAPI.logTimerError(evt), ...
                    'ObjectVisibility', 'off');
                obj.reconnect_timer = t;
                start(t);
            catch
                % No timer support: wait() runs the attempt when it is due.
                obj.reconnect_timer = [];
            end
        end

        function runReconnectAttempt(obj)
            % One iteration of the Python _reconnect_loop.
            if obj.shutting_down || ~obj.reconnect_active
                obj.reconnect_active = false;
                return
            end
            attempt = obj.reconnect_attempt + 1;
            try
                if obj.doConnect()
                    obj.logMsg(1, 'WS', 'Reconnected and re-authenticated.');
                    obj.reconnect_active = false;
                    obj.reconnect_attempt = 0;
                    obj.replaySubscriptions();
                    return
                end
            catch err
                obj.logMsg(1, 'ERROR', sprintf('Reconnect attempt %d failed: %s', attempt, err.message));
            end
            obj.reconnect_attempt = attempt;
            if obj.shutting_down || obj.authenticated
                obj.reconnect_active = false;
                return
            end
            obj.scheduleReconnectAttempt();
        end

        function replaySubscriptions(obj)
            % Re-send every active subscription, one bulk message per mode.
            for mode = 1:3
                store = obj.active_subs{mode};
                if isempty(store.entries)
                    continue
                end
                modeNames = openalgo.FeedAPI.FEED_MODE_NAMES;
                obj.logMsg(1, 'SUB', sprintf('Replaying %d %s subscription(s) after reconnect', ...
                    numel(store.entries), modeNames{mode}));
                % One bulk message per mode, or per depth level for Depth.
                levels = unique(store.depths, 'stable');
                for k = 1:numel(levels)
                    obj.sendSubscribeMsg(mode, store.entries(store.depths == levels(k)), levels(k));
                end
            end
            if obj.orders_subscribed && ~isempty(obj.ws)
                obj.logMsg(1, 'SUB', 'Replaying order-update subscription after reconnect');
                try
                    obj.ws.send(jsonencode(struct('action', 'subscribe_orders')));
                catch err
                    obj.logMsg(1, 'ERROR', ['Error replaying order subscription: ' err.message]);
                end
            end
        end

        function ok = sendSubscribeMsg(obj, mode, entries, depth)
            % {"action":"subscribe","symbols":[...],"mode":m,"depth":d}
            if nargin < 4
                depth = 5;
            end
            ok = false;
            if isempty(obj.ws)
                return
            end
            msg = struct();
            msg.action = 'subscribe';
            msg.symbols = reshape(entries, 1, []);
            msg.mode = mode;
            msg.depth = depth;
            try
                obj.ws.send(jsonencode(msg));
                ok = true;
            catch err
                obj.logMsg(1, 'ERROR', ['Error sending bulk subscribe: ' err.message]);
            end
        end

        function ok = sendUnsubscribeMsg(obj, mode, entries)
            % {"action":"unsubscribe","symbols":[{"symbol","exchange","mode"}...]}
            ok = false;
            if isempty(obj.ws)
                return
            end
            symbols = cell(1, numel(entries));
            for i = 1:numel(entries)
                s = struct();
                s.symbol = entries{i}.symbol;
                s.exchange = entries{i}.exchange;
                s.mode = mode;
                symbols{i} = s;
            end
            msg = struct();
            msg.action = 'unsubscribe';
            msg.symbols = symbols;
            try
                obj.ws.send(jsonencode(msg));
                ok = true;
            catch err
                obj.logMsg(1, 'ERROR', ['Error sending bulk unsubscribe: ' err.message]);
            end
        end

        function ok = subscribeMode(obj, mode, instruments, callback, callbackProp, depth)
            if nargin < 6
                depth = 5;
            end
            ok = false;
            if ~obj.connected
                obj.logMsg(1, 'ERROR', 'Not connected to WebSocket server');
                return
            end
            if ~obj.authenticated
                obj.logMsg(1, 'ERROR', 'Not authenticated with WebSocket server');
                return
            end
            if openalgo.FeedAPI.isTruthy(callback)
                obj.(callbackProp) = callback;
            end
            modeNames = openalgo.FeedAPI.FEED_MODE_NAMES;
            label = modeNames{mode};
            items = openalgo.FeedAPI.feedInstrumentList(instruments);
            valid = {};
            for i = 1:numel(items)
                [exchange, symbol, good] = openalgo.FeedAPI.feedInstrument(items{i});
                if ~good
                    obj.logMsg(1, 'ERROR', ['Invalid instrument: ' openalgo.FeedAPI.pyRepr(items{i})]);
                    continue
                end
                entry = struct();
                entry.symbol = symbol;
                entry.exchange = exchange;
                valid{end + 1} = entry; %#ok<AGROW>
                obj.addActiveSub(mode, exchange, symbol, entry, depth);
                obj.logMsg(1, 'SUB', sprintf('Subscribing %s:%s %s...', ...
                    openalgo.FeedAPI.pyStr(exchange), openalgo.FeedAPI.pyStr(symbol), label));
            end
            if isempty(valid)
                return
            end
            ok = obj.sendSubscribeMsg(mode, valid, depth);
        end

        function ok = unsubscribeMode(obj, mode, instruments)
            ok = false;
            if ~obj.connected || ~obj.authenticated
                return
            end
            modeNames = openalgo.FeedAPI.FEED_MODE_NAMES;
            label = modeNames{mode};
            switch mode
                case 1
                    store = obj.ltp_data;
                case 2
                    store = obj.quotes_data;
                otherwise
                    store = obj.depth_data;
            end
            items = openalgo.FeedAPI.feedInstrumentList(instruments);
            valid = {};
            for i = 1:numel(items)
                [exchange, symbol, good] = openalgo.FeedAPI.feedInstrument(items{i});
                if ~good
                    obj.logMsg(1, 'ERROR', ['Invalid instrument: ' openalgo.FeedAPI.pyRepr(items{i})]);
                    continue
                end
                obj.logMsg(1, 'UNSUB', sprintf('Unsubscribing %s:%s %s', ...
                    openalgo.FeedAPI.pyStr(exchange), openalgo.FeedAPI.pyStr(symbol), label));
                entry = struct();
                entry.symbol = symbol;
                entry.exchange = exchange;
                valid{end + 1} = entry; %#ok<AGROW>
                obj.removeActiveSub(mode, exchange, symbol);
                key = [openalgo.FeedAPI.pyStr(exchange) ':' openalgo.FeedAPI.pyStr(symbol)];
                if store.isKey(key)
                    store.remove(key);
                end
            end
            if isempty(valid)
                return
            end
            ok = obj.sendUnsubscribeMsg(mode, valid);
        end

        function addActiveSub(obj, mode, exchange, symbol, entry, depth)
            key = openalgo.FeedAPI.subKey(exchange, symbol);
            store = obj.active_subs{mode};
            idx = find(strcmp(store.keys, key), 1);
            if isempty(idx)
                store.keys{end + 1} = key;
                store.entries{end + 1} = entry;
                store.depths(end + 1) = depth;
            else
                store.entries{idx} = entry;
                store.depths(idx) = depth;
            end
            obj.active_subs{mode} = store;
        end

        function removeActiveSub(obj, mode, exchange, symbol)
            key = openalgo.FeedAPI.subKey(exchange, symbol);
            store = obj.active_subs{mode};
            idx = strcmp(store.keys, key);
            store.keys(idx) = [];
            store.entries(idx) = [];
            store.depths(idx) = [];
            obj.active_subs{mode} = store;
        end

        function handleMessage(obj, message)
            % Body of the Python _process_message after json.loads.
            if ~isstruct(message) || ~isscalar(message)
                error('''%s'' object has no attribute ''get''', openalgo.FeedAPI.pyTypeName(message));
            end
            getf = @openalgo.FeedAPI.getf;
            pyStr = @openalgo.FeedAPI.pyStr;
            isText = @openalgo.FeedAPI.isText;
            msgType = getf(message, 'type', []);

            % Server errors: {"status":"error","code","message"} (no type) or
            % {"type":"error",...}. Logged; also the answer to a waiting request.
            isServerError = isText(msgType, 'error') || ...
                (isempty(msgType) && isText(getf(message, 'status', []), 'error'));
            if ~isempty(obj.pending_replies)
                if isServerError
                    obj.matchPendingReply('error', message);
                elseif ischar(msgType)
                    obj.matchPendingReply(msgType, message);
                end
            end
            if isServerError
                code = getf(message, 'code', []);
                text = pyStr(getf(message, 'message', 'Unknown error'));
                if openalgo.FeedAPI.isTruthy(code)
                    obj.logMsg(1, 'ERROR', sprintf('Server error %s: %s', pyStr(code), text));
                else
                    obj.logMsg(1, 'ERROR', ['Server error: ' text]);
                end
                return
            end

            % Authentication response
            if isText(msgType, 'auth')
                if isText(getf(message, 'status', []), 'success')
                    obj.authenticated = true;
                    broker = getf(message, 'broker', 'unknown');
                    userId = getf(message, 'user_id', 'unknown');
                    obj.logMsg(1, 'AUTH', sprintf('Success | Broker: %s | User: %s', pyStr(broker), pyStr(userId)));
                    obj.logMsg(2, 'AUTH', ['Full response: ' openalgo.FeedAPI.pyRepr(message)]);
                else
                    obj.logMsg(1, 'ERROR', ['Authentication failed: ' pyStr(getf(message, 'message', 'Unknown error'))]);
                end
                return
            end

            % Order-update subscription responses
            if isText(msgType, 'subscribe_orders') || isText(msgType, 'unsubscribe_orders')
                obj.logMsg(1, 'SUB', sprintf('Order updates | %s | Status: %s', ...
                    pyStr(msgType), pyStr(getf(message, 'status', '?'))));
                obj.logMsg(2, 'SUB', ['Full response: ' openalgo.FeedAPI.pyRepr(message)]);
                return
            end

            % Real-time order updates
            if isText(msgType, 'order_update')
                orders = [{message}, obj.order_data];
                if numel(orders) > openalgo.FeedAPI.FEED_ORDER_HISTORY
                    orders = orders(1:openalgo.FeedAPI.FEED_ORDER_HISTORY);
                end
                obj.order_data = orders;
                obj.logMsg(2, 'ORDER', sprintf('%-20s | %-10s | Qty: %s/%s | Avg: %s | ID: %s', ...
                    pyStr(getf(message, 'symbol', '?')), pyStr(getf(message, 'order_status', '?')), ...
                    pyStr(getf(message, 'filled_quantity', 0)), pyStr(getf(message, 'quantity', 0)), ...
                    pyStr(getf(message, 'average_price', 0)), pyStr(getf(message, 'orderid', '?'))));
                cb = obj.order_callback;
                if openalgo.FeedAPI.isTruthy(cb)
                    try
                        feval(cb, message);
                    catch err
                        obj.logMsg(1, 'ERROR', ['Order callback error: ' err.message]);
                    end
                end
                return
            end

            % Subscription response
            if isText(msgType, 'subscribe')
                subs = openalgo.FeedAPI.toCellRow(getf(message, 'subscriptions', {}));
                for i = 1:numel(subs)
                    sub = subs{i};
                    obj.logMsg(1, 'SUB', sprintf('%s:%s | Mode: %s | Status: %s', ...
                        pyStr(getf(sub, 'exchange', '?')), pyStr(getf(sub, 'symbol', '?')), ...
                        openalgo.FeedAPI.modeName(getf(sub, 'mode', 0)), pyStr(getf(sub, 'status', '?'))));
                    if isText(getf(sub, 'status', []), 'error')
                        obj.logMsg(1, 'ERROR', sprintf('Subscription failed for %s:%s: %s', ...
                            pyStr(getf(sub, 'exchange', '?')), pyStr(getf(sub, 'symbol', '?')), ...
                            pyStr(getf(sub, 'message', 'Unknown error'))));
                    end
                end
                obj.logMsg(2, 'SUB', ['Full response: ' openalgo.FeedAPI.pyRepr(message)]);
                return
            end

            % Unsubscription response
            if isText(msgType, 'unsubscribe')
                done = openalgo.FeedAPI.toCellRow(getf(message, 'successful', {}));
                for i = 1:numel(done)
                    item = done{i};
                    obj.logMsg(1, 'UNSUB', sprintf('%s:%s | Mode: %s | Status: %s', ...
                        pyStr(getf(item, 'exchange', '?')), pyStr(getf(item, 'symbol', '?')), ...
                        openalgo.FeedAPI.modeName(getf(item, 'mode', 0)), pyStr(getf(item, 'status', 'success'))));
                end
                failed = openalgo.FeedAPI.toCellRow(getf(message, 'failed', {}));
                for i = 1:numel(failed)
                    item = failed{i};
                    obj.logMsg(1, 'ERROR', sprintf('Unsubscribe failed for %s:%s | Mode: %s: %s', ...
                        pyStr(getf(item, 'exchange', '?')), pyStr(getf(item, 'symbol', '?')), ...
                        openalgo.FeedAPI.modeName(getf(item, 'mode', 0)), ...
                        pyStr(getf(item, 'message', 'Unknown error'))));
                end
                obj.logMsg(2, 'UNSUB', ['Full response: ' openalgo.FeedAPI.pyRepr(message)]);
                return
            end

            % Market data
            if ~isText(msgType, 'market_data')
                return
            end
            exchange = getf(message, 'exchange', []);
            symbol = getf(message, 'symbol', []);
            if ~(openalgo.FeedAPI.isTruthy(exchange) && openalgo.FeedAPI.isTruthy(symbol))
                return
            end
            mode = getf(message, 'mode', []);
            marketData = getf(message, 'data', struct());
            isMode = @(m) (isnumeric(mode) || islogical(mode)) && isscalar(mode) && mode == m;
            if ~(isMode(1) || isMode(2) || isMode(3))
                return
            end
            if ~isstruct(marketData) || ~isscalar(marketData)
                error('''%s'' object has no attribute ''get''', openalgo.FeedAPI.pyTypeName(marketData));
            end
            symbolKey = [pyStr(exchange) ':' pyStr(symbol)];

            if isMode(1) && isfield(marketData, 'ltp')
                % LTP data (mode 1)
                ltp = marketData.ltp;
                timestamp = getf(marketData, 'timestamp', openalgo.FeedAPI.nowMs());
                rec = struct();
                rec.price = ltp;
                rec.timestamp = timestamp;
                store = obj.ltp_data;
                store(symbolKey) = rec; %#ok<NASGU>
                obj.logMsg(2, 'LTP', sprintf('%-20s | LTP: %s', symbolKey, pyStr(ltp)));
                cb = obj.ltp_callback;
                if openalgo.FeedAPI.isTruthy(cb)
                    try
                        data = struct();
                        data.ltp = ltp;
                        data.timestamp = timestamp;
                        if isfield(marketData, 'ltt')
                            data.ltt = marketData.ltt;
                        elseif isfield(marketData, 'data') && isstruct(marketData.data) && ...
                                isscalar(marketData.data) && isfield(marketData.data, 'ltt')
                            data.ltt = marketData.data.ltt;
                        end
                        feval(cb, openalgo.FeedAPI.cleanData(symbol, exchange, mode, data));
                    catch err
                        obj.logMsg(1, 'ERROR', ['LTP callback error: ' err.message]);
                    end
                end
            elseif isMode(2)
                % Quote data (mode 2)
                quote = struct();
                quote.open = getf(marketData, 'open', 0);
                quote.high = getf(marketData, 'high', 0);
                quote.low = getf(marketData, 'low', 0);
                quote.close = getf(marketData, 'close', 0);
                quote.ltp = getf(marketData, 'ltp', 0);
                quote.volume = getf(marketData, 'volume', 0);
                quote.last_trade_quantity = getf(marketData, 'last_trade_quantity', 0);
                quote.avg_trade_price = getf(marketData, 'avg_trade_price', 0);
                quote.change = getf(marketData, 'change', 0);
                quote.change_percent = getf(marketData, 'change_percent', 0);
                quote.timestamp = getf(marketData, 'timestamp', openalgo.FeedAPI.nowMs());
                store = obj.quotes_data;
                store(symbolKey) = quote; %#ok<NASGU>
                obj.logMsg(2, 'QUOTE', sprintf('%-20s | O: %-10s H: %-10s L: %-10s C: %-10s LTP: %s', ...
                    symbolKey, pyStr(quote.open), pyStr(quote.high), pyStr(quote.low), ...
                    pyStr(quote.close), pyStr(quote.ltp)));
                cb = obj.quote_callback;
                if openalgo.FeedAPI.isTruthy(cb)
                    try
                        feval(cb, openalgo.FeedAPI.cleanData(symbol, exchange, mode, quote));
                    catch err
                        obj.logMsg(1, 'ERROR', ['Quote callback error: ' err.message]);
                    end
                end
            elseif isMode(3) && isfield(marketData, 'depth')
                % Market depth data (mode 3)
                depthData = struct();
                depthData.ltp = getf(marketData, 'ltp', 0);
                depthData.timestamp = getf(marketData, 'timestamp', openalgo.FeedAPI.nowMs());
                depthData.depth = openalgo.FeedAPI.normalizeDepth(marketData.depth);
                store = obj.depth_data;
                store(symbolKey) = depthData; %#ok<NASGU>
                obj.logMsg(2, 'DEPTH', sprintf('%-20s | LTP: %s', symbolKey, pyStr(depthData.ltp)));
                if obj.verbose >= 2
                    obj.printDepth(depthData.depth.buy, depthData.depth.sell);
                end
                cb = obj.depth_callback;
                if openalgo.FeedAPI.isTruthy(cb)
                    try
                        feval(cb, openalgo.FeedAPI.cleanData(symbol, exchange, mode, depthData));
                    catch err
                        obj.logMsg(1, 'ERROR', ['Depth callback error: ' err.message]);
                    end
                end
            end
        end

        function printDepth(obj, buy, sell)
            pad = blanks(9);
            obj.emit(sprintf('%s%-30s | %-30s', pad, 'BUY', 'SELL'));
            obj.emit(sprintf('%s%-10s %-10s %-8s | %-10s %-10s %-8s', pad, 'Price', 'Qty', 'Orders', 'Price', 'Qty', 'Orders'));
            obj.emit([pad repmat('-', 1, 62)]);
            maxLevels = max([numel(buy), numel(sell), 1]);
            for i = 1:maxLevels
                b = struct();
                s = struct();
                if i <= numel(buy)
                    b = buy{i};
                end
                if i <= numel(sell)
                    s = sell{i};
                end
                f = @(lvl, name) openalgo.FeedAPI.pyStr(openalgo.FeedAPI.getf(lvl, name, '-'));
                obj.emit(sprintf('%s%-10s %-10s %-8s | %-10s %-10s %-8s', pad, ...
                    f(b, 'price'), f(b, 'quantity'), f(b, 'orders'), ...
                    f(s, 'price'), f(s, 'quantity'), f(s, 'orders')));
            end
        end

        function startPollTimer(obj)
            t = obj.poll_timer;
            if ~isempty(t) && isvalid(t)
                if strcmp(t.Running, 'off')
                    start(t);
                end
                return
            end
            obj.poll_timer = [];
            try
                t = timer('Name', 'openalgo-feed-poll', ...
                    'ExecutionMode', 'fixedSpacing', ...
                    'Period', obj.poll_period, ...
                    'BusyMode', 'drop', ...
                    'TimerFcn', @(~, ~) obj.feedOnPollTimer(), ...
                    'StopFcn', @(src, ~) openalgo.FeedAPI.deleteTimer(src), ...
                    'ErrorFcn', @(~, evt) openalgo.FeedAPI.logTimerError(evt), ...
                    'ObjectVisibility', 'off');
                obj.poll_timer = t;
                start(t);
            catch err
                obj.logMsg(1, 'ERROR', ['Feed timer unavailable, use wait() to process data: ' err.message]);
            end
        end

        function killTimer(obj, prop)
            t = obj.(prop);
            obj.(prop) = [];
            if isempty(t)
                return
            end
            try
                if isvalid(t)
                    if strcmp(t.Running, 'on')
                        stop(t);        % StopFcn deletes it
                    else
                        delete(t);
                    end
                end
            catch
            end
        end
    end

    methods (Static, Hidden)
        function deleteTimer(t)
            %DELETETIMER StopFcn of the feed timers.
            try
                if isvalid(t)
                    delete(t);
                end
            catch
            end
        end

        function logTimerError(evt)
            %LOGTIMERERROR ErrorFcn of the feed timers.
            msg = 'unknown error';
            try
                msg = evt.Data.message;
            catch
            end
            fprintf('%-8s %s\n', '[ERROR]', ['Feed timer error: ' msg]);
        end

        function releasePump(ws)
            if isvalid(ws)
                ws.PumpBusy = false;
            end
        end
    end

    methods (Static, Access = private)
        function opts = feedParseArgs(args, names, defaults, fname, nRequired)
            % Optional arguments given positionally or as name=value pairs.
            opts = cell2struct(defaults(:), names(:), 1);
            given = false(1, numel(names));
            n = numel(args);
            i = 1;
            pos = 1;
            while i <= n
                a = args{i};
                isName = (ischar(a) && (isrow(a) || isempty(a))) || (isstring(a) && isscalar(a));
                if isName && any(strcmpi(char(a), names)) && mod(n - i + 1, 2) == 0
                    while i <= n
                        nm = args{i};
                        if ~((ischar(nm) && isrow(nm)) || (isstring(nm) && isscalar(nm))) || ~any(strcmpi(char(nm), names))
                            error('openalgo:FeedAPI:badArgument', '%s() got an unexpected argument: %s', ...
                                fname, openalgo.FeedAPI.pyRepr(nm));
                        end
                        idx = find(strcmpi(char(nm), names), 1);
                        opts.(names{idx}) = args{i + 1};
                        given(idx) = true;
                        i = i + 2;
                    end
                    break
                end
                if pos > numel(names)
                    error('openalgo:FeedAPI:badArgument', '%s() takes at most %d arguments (%d given)', ...
                        fname, numel(names), n);
                end
                opts.(names{pos}) = a;
                given(pos) = true;
                pos = pos + 1;
                i = i + 1;
            end
            for k = 1:nRequired
                if ~given(k)
                    error('openalgo:FeedAPI:missingArgument', '%s() missing required argument: ''%s''', ...
                        fname, names{k});
                end
            end
        end

        function items = feedInstrumentList(instruments)
            if isempty(instruments)
                items = {};
            elseif iscell(instruments)
                items = reshape(instruments, 1, []);
            elseif isstruct(instruments)
                items = num2cell(reshape(instruments, 1, []));
            else
                items = {instruments};
            end
        end

        function [exchange, symbol, good] = feedInstrument(instrument)
            exchange = [];
            symbol = [];
            good = false;
            if ~isstruct(instrument) || ~isscalar(instrument)
                return
            end
            exchange = openalgo.FeedAPI.textValue(openalgo.FeedAPI.getf(instrument, 'exchange', []));
            symbol = openalgo.FeedAPI.textValue(openalgo.FeedAPI.getf(instrument, 'symbol', []));
            token = openalgo.FeedAPI.textValue(openalgo.FeedAPI.getf(instrument, 'exchange_token', []));
            if ~openalgo.FeedAPI.isTruthy(symbol) && openalgo.FeedAPI.isTruthy(token)
                symbol = token;
            end
            good = openalgo.FeedAPI.isTruthy(exchange) && openalgo.FeedAPI.isTruthy(symbol);
        end

        function [ex, sym, ok] = feedSplitKey(key, exchange, symbol)
            % Python: parts = key.split(":"); filters on parts[0] and parts[1].
            ex = '';
            sym = '';
            ok = false;
            if ~contains(key, ':')
                return
            end
            parts = strsplit(key, ':', 'CollapseDelimiters', false);
            ex = parts{1};
            sym = parts{2};
            if openalgo.FeedAPI.isTruthy(exchange) && ~strcmp(ex, openalgo.FeedAPI.pyStr(exchange))
                return
            end
            if openalgo.FeedAPI.isTruthy(symbol) && ~strcmp(sym, openalgo.FeedAPI.pyStr(symbol))
                return
            end
            ok = true;
        end

        function book = feedBook(levels)
            levels = openalgo.FeedAPI.toCellRow(levels);
            n = numel(levels);
            book = repmat(struct('price', 0, 'qty', 0, 'orders', 0), 1, max(n, 5));
            for i = 1:n
                lvl = levels{i};
                book(i).price = openalgo.FeedAPI.toNumber(openalgo.FeedAPI.getf(lvl, 'price', 0));
                book(i).qty = fix(openalgo.FeedAPI.toNumber(openalgo.FeedAPI.getf(lvl, 'quantity', 0)));
                book(i).orders = fix(openalgo.FeedAPI.toNumber(openalgo.FeedAPI.getf(lvl, 'orders', 0)));
            end
        end

        function depth = normalizeDepth(depth)
            % depth.buy and depth.sell as row cell arrays of level structs.
            if ~isstruct(depth) || ~isscalar(depth)
                depth = struct();
            end
            depth.buy = openalgo.FeedAPI.toCellRow(openalgo.FeedAPI.getf(depth, 'buy', {}));
            depth.sell = openalgo.FeedAPI.toCellRow(openalgo.FeedAPI.getf(depth, 'sell', {}));
        end

        function c = toCellRow(x)
            if isempty(x)
                c = cell(1, 0);
            elseif iscell(x)
                c = reshape(x, 1, []);
            elseif isstruct(x)
                c = num2cell(reshape(x, 1, []));
            else
                c = cell(1, 0);
            end
        end

        function s = cleanData(symbol, exchange, mode, data)
            s = struct();
            s.type = 'market_data';
            s.symbol = symbol;
            s.exchange = exchange;
            s.mode = mode;
            s.data = data;
        end

        function v = getf(s, name, default)
            % Python dict.get for a scalar struct.
            if isstruct(s) && isscalar(s) && isfield(s, name)
                v = s.(name);
            else
                v = default;
            end
        end

        function tf = isText(v, text)
            tf = (ischar(v) || (isstring(v) && isscalar(v))) && strcmp(v, text);
        end

        function v = textValue(v)
            if isstring(v) && isscalar(v)
                v = char(v);
            end
        end

        function tf = isTruthy(v)
            % Python truthiness for the values the feed handles.
            if isa(v, 'function_handle')
                tf = true;
            elseif isempty(v)
                tf = false;
            elseif ischar(v)
                tf = true;
            elseif isstring(v)
                tf = strlength(v(1)) > 0;
            elseif (isnumeric(v) || islogical(v)) && isscalar(v)
                tf = v ~= 0;
            else
                tf = true;
            end
        end

        function v = toNumber(x)
            if isempty(x)
                v = 0;
            elseif ischar(x) || isstring(x)
                v = str2double(x);
            elseif isnumeric(x) || islogical(x)
                v = double(x(1));
            else
                v = 0;
            end
        end

        function key = subKey(exchange, symbol)
            key = [openalgo.FeedAPI.pyStr(exchange) char(31) openalgo.FeedAPI.pyStr(symbol)];
        end

        function name = modeName(mode)
            % Mode 1/2/3 or the case-insensitive label LTP/Quote/Depth.
            names = {'LTP', 'Quote', 'Depth'};
            name = 'Unknown';
            if (isnumeric(mode) || islogical(mode)) && isscalar(mode) && any(mode == [1 2 3])
                name = names{double(mode)};
            elseif (ischar(mode) && isrow(mode)) || (isstring(mode) && isscalar(mode))
                idx = find(strcmpi(char(mode), names), 1);
                if ~isempty(idx)
                    name = names{idx};
                end
            end
        end

        function t = nowMs()
            t = floor(posixtime(datetime('now', 'TimeZone', 'UTC')) * 1000);
        end

        function s = pyStr(v)
            % Python str() of a decoded JSON value.
            if ischar(v)
                s = reshape(v, 1, []);
            elseif isstring(v) && isscalar(v)
                s = char(v);
            elseif isnumeric(v) && isempty(v)
                s = 'None';
            elseif (isnumeric(v) || islogical(v)) && isscalar(v)
                s = openalgo.FeedAPI.pyRepr(v);
            else
                s = openalgo.FeedAPI.pyRepr(v);
            end
        end

        function s = pyRepr(v)
            % Python repr() of a decoded JSON value.
            if ischar(v)
                s = openalgo.FeedAPI.pyQuote(reshape(v, 1, []));
            elseif isstring(v)
                if isscalar(v)
                    s = openalgo.FeedAPI.pyQuote(char(v));
                else
                    s = openalgo.FeedAPI.pyList(num2cell(v));
                end
            elseif isstruct(v)
                if isscalar(v)
                    f = fieldnames(v);
                    parts = cell(1, numel(f));
                    for i = 1:numel(f)
                        parts{i} = [openalgo.FeedAPI.pyQuote(f{i}) ': ' openalgo.FeedAPI.pyRepr(v.(f{i}))];
                    end
                    s = ['{' strjoin(parts, ', ') '}'];
                else
                    s = openalgo.FeedAPI.pyList(num2cell(v));
                end
            elseif iscell(v)
                s = openalgo.FeedAPI.pyList(v);
            elseif islogical(v)
                if isscalar(v)
                    if v
                        s = 'True';
                    else
                        s = 'False';
                    end
                else
                    s = openalgo.FeedAPI.pyList(num2cell(v));
                end
            elseif isnumeric(v)
                if isempty(v)
                    s = 'None';
                elseif isscalar(v)
                    s = openalgo.FeedAPI.pyNum(v);
                else
                    s = openalgo.FeedAPI.pyList(num2cell(v));
                end
            elseif isa(v, 'function_handle')
                s = ['<function ' func2str(v) '>'];
            else
                s = ['<' class(v) '>'];
            end
        end

        function s = pyList(c)
            parts = cellfun(@openalgo.FeedAPI.pyRepr, reshape(c, 1, []), 'UniformOutput', false);
            s = ['[' strjoin(parts, ', ') ']'];
        end

        function s = pyQuote(text)
            text = strrep(text, '\', '\\');
            text = strrep(text, char(10), '\n');
            text = strrep(text, char(13), '\r');
            text = strrep(text, char(9), '\t');
            if any(text == '''') && ~any(text == '"')
                s = ['"' text '"'];
            else
                s = ['''' strrep(text, '''', '\''') ''''];
            end
        end

        function s = pyNum(x)
            if isinteger(x)
                s = sprintf('%d', x);
                return
            end
            x = double(x);
            if isnan(x)
                s = 'nan';
            elseif isinf(x)
                if x > 0
                    s = 'inf';
                else
                    s = '-inf';
                end
            elseif x == fix(x) && abs(x) < 1e16
                s = sprintf('%d', x);
            else
                for p = 1:17
                    s = sprintf(sprintf('%%.%dg', p), x);
                    if str2double(s) == x
                        break
                    end
                end
            end
        end

        function name = pyTypeName(v)
            if isstruct(v) && ~isscalar(v) || iscell(v)
                name = 'list';
            elseif ischar(v) || isstring(v)
                name = 'str';
            elseif islogical(v)
                name = 'bool';
            elseif isnumeric(v) && isempty(v)
                name = 'NoneType';
            elseif isnumeric(v) && isscalar(v) && v == fix(v)
                name = 'int';
            elseif isnumeric(v)
                name = 'float';
            else
                name = class(v);
            end
        end
    end
end
