classdef api < openalgo.BaseAPI & openalgo.FeedAPI
%API OpenAlgo API client.
%   CLIENT = openalgo.api(api_key="your_api_key", host="http://127.0.0.1:5000")
%   creates the OpenAlgo client: one object carrying every REST method
%   (orders, GTT orders, market data, account, options, strategy module,
%   notifications and market calendar utilities) and the WebSocket market
%   data feed. It mirrors openalgo.api in the Python SDK, with the same
%   method names, parameter names, defaults and request payloads.
%
%   Constructor arguments (positional in this order, or name=value):
%     api_key        - User's API key. Required.
%     host           - Base URL for the API endpoints.
%                      Default "http://127.0.0.1:5000".
%     version        - API version. Default "v1".
%     timeout        - Request timeout in seconds. Default 120.
%     ws_port        - WebSocket server port. Default 8765.
%     ws_url         - Custom WebSocket URL. Overrides host and ws_port.
%                      Default []: derived from host, as
%                      ws://<host name>:<ws_port> for an http:// host and
%                      wss://<host, with any port>/ws for an https:// host
%                      (server deployments serve the feed behind the web
%                      server).
%     verbose        - Feed logging level. false or 0: silent (errors
%                      only); true or 1: connection, authentication and
%                      subscription status; 2: full debug including every
%                      market data update. Default false.
%     auto_reconnect - If true (default), the feed reconnects,
%                      re-authenticates and replays every active
%                      subscription after a drop, with exponential backoff.
%
%   CALLING CONVENTION
%   Methods take name=value arguments with the exact, case-sensitive
%   parameter names of the Python SDK:
%
%     resp = client.placeorder(strategy="Python", symbol="SBIN", ...
%         action="BUY", exchange="NSE", price_type="MARKET", ...
%         product="MIS", quantity=1);
%
%   - Parameters that are keyword-only in Python are name=value only. A
%     required one that is missing raises openalgo:missingArgument.
%   - Parameters that are positional in Python also accept a leading
%     positional value: client.analyzertoggle(true), client.holidays(2025),
%     client.timings("2025-01-15"), client.whatsapp("Build deployed").
%   - [] stands for Python None. An optional parameter left at [] is not
%     sent, exactly as the Python SDK skips None.
%   - Extra name=value pairs on methods that take **kwargs in Python are
%     added to the request payload (as text where the Python SDK applies
%     str(), as is otherwise; [] values are skipped). Methods without
%     **kwargs reject them with openalgo:unexpectedArgument.
%   - Lists (orders, symbols, legs, positions, phone numbers) are cell
%     arrays or struct arrays and are always sent as JSON arrays, even with
%     one element. Dicts are scalar structs.
%
%   RETURN VALUES
%   Every REST method returns the decoded JSON response as a struct (from
%   jsondecode) and never raises for server or network problems: a failure
%   is a struct with status 'error', message and error_type
%   (http_error, json_error, api_error, timeout_error, connection_error,
%   unknown_error, validation_error, no_data or processing_error), plus
%   code and raw_response where the Python SDK includes them.
%   history returns a timetable and instruments a table on success.
%
%   ORDER METHODS
%     placeorder        - Place an order.
%     placesmartorder   - Place an order that considers the position size.
%     basketorder       - Place several orders at once.
%     splitorder        - Split a large order into smaller ones.
%     orderstatus       - Status of one order.
%     openposition      - Open position for a symbol.
%     modifyorder       - Modify an open order.
%     cancelorder       - Cancel an order.
%     closeposition     - Close every open position of a strategy.
%     cancelallorder    - Cancel every order of a strategy.
%
%   GTT ORDER METHODS
%     placegttorder     - Place a Good Till Triggered order.
%     modifygttorder    - Modify an active GTT trigger.
%     cancelgttorder    - Cancel an active GTT trigger.
%     gttorderbook      - List GTT triggers.
%
%   MARKET DATA METHODS
%     quotes            - Real-time quote for a symbol.
%     multiquotes       - Quotes for several symbols.
%     depth             - Market depth for a symbol.
%     symbol            - Symbol details.
%     search            - Search symbols.
%     history           - Historical candles (timetable).
%     intervals         - Supported history intervals.
%     interval          - Legacy alias of intervals.
%     expiry            - Expiry dates of a symbol.
%     instruments       - Instrument master (table).
%     syntheticfuture   - Synthetic future price from ATM options.
%
%   ACCOUNT METHODS
%     funds             - Funds and margin details.
%     orderbook         - Order book with statistics.
%     tradebook         - Trade book.
%     positionbook      - Position book.
%     holdings          - Holdings with statistics.
%     analyzerstatus    - Analyzer (sandbox) mode status.
%     analyzertoggle    - Switch analyzer mode on or off.
%     margin            - Margin required for a basket of positions.
%
%   OPTIONS METHODS
%     optiongreeks      - Option Greeks and implied volatility.
%     optionsorder      - Place an option order by offset.
%     optionsymbol      - Resolve an option symbol by offset.
%     optionsmultiorder - Place a multi-leg option order.
%     optionchain       - Option chain with quotes.
%
%   STRATEGY MODULE METHODS
%     strategylist      - Strategies owned by the API key.
%     strategystatus    - One strategy with legs and current run.
%     strategystart     - Start a run of a batch strategy.
%     strategystop      - Stop the current run.
%     strategycloseall  - Close every leg, recording an operator intent.
%     strategycloseleg  - Exit one leg of the current run.
%     strategyruns      - Every run of a strategy.
%     strategyorders    - Every order of a strategy.
%     strategyevents    - Risk-event audit trail.
%
%   NOTIFICATION AND UTILITY METHODS
%     telegram          - Send a Telegram alert.
%     whatsapp          - Send a WhatsApp message.
%     holidays          - Market holidays of a year.
%     timings           - Market timings of a date.
%     close             - Release the HTTP resources.
%
%   ADDITIONS (not present in the Python SDK)
%   These cover the remaining documented OpenAlgo REST endpoints. They
%   follow the same calling convention; POST methods share the response
%   handling of the order methods and GET methods that of instruments.
%     ping                      - Authenticated connectivity check.
%     pnlsymbols                - Sandbox P&L by symbol.
%     multioptiongreeks         - Greeks for 1 to 50 options at once.
%     ticker                    - Ticker-compatible history (JSON or text).
%     chart                     - Read the stored chart preferences.
%     updatechart               - Update the stored chart preferences.
%     telegramconfig            - Read the Telegram bot configuration.
%     updatetelegramconfig      - Update the Telegram bot configuration.
%     telegramstart             - Start the Telegram bot.
%     telegramstop              - Stop the Telegram bot.
%     telegramusers             - List the linked Telegram users.
%     telegrambroadcast         - Broadcast to the linked Telegram users.
%     telegramstats             - Telegram command statistics.
%     telegrampreferences       - Read a Telegram user's preferences.
%     updatetelegrampreferences - Update a Telegram user's preferences.
%
%   The WebSocket feed methods (connect, disconnect, subscribe_ltp,
%   subscribe_quote, subscribe_depth, subscribe_orders, get_ltp,
%   get_quotes, get_depth, get_orders and the matching unsubscribe
%   methods) come from openalgo.FeedAPI.
%
%   Example:
%     client = openalgo.api(api_key="your_api_key", host="http://127.0.0.1:5000");
%     f = client.funds();
%     q = client.quotes(symbol="SBIN", exchange="NSE");
%     df = client.history(symbol="SBIN", exchange="NSE", interval="5m", ...
%         start_date="2025-01-01", end_date="2025-01-10");
%
%   Help for one method: help openalgo.api/placeorder
%
%   See also openalgo.BaseAPI, openalgo.FeedAPI, openalgo.Strategy.

    methods
        function obj = api(varargin)
            %API Create an OpenAlgo API client.
            %   CLIENT = openalgo.api(api_key, host="http://127.0.0.1:5000",
            %   version="v1", timeout=120, ws_port=8765, ws_url=[],
            %   verbose=false, auto_reconnect=true)
            a = openalgo.internal.parseArgs('api', varargin, ...
                {'api_key', []; 'host', 'http://127.0.0.1:5000'; 'version', 'v1'; ...
                 'timeout', 120.0; 'ws_port', 8765; 'ws_url', []; 'verbose', false; ...
                 'auto_reconnect', true}, ...
                {'api_key'}, 8, false);
            obj@openalgo.BaseAPI(a.api_key, a.host, a.version, a.timeout);
            obj.initFeed(a.host, a.ws_port, a.ws_url, a.verbose, a.auto_reconnect);
        end

        function disp(obj)
            %DISP Display the client without revealing the API key.
            %   The key is a credential, so it is never printed; read
            %   CLIENT.api_key explicitly if you need it.
            if ~isscalar(obj)
                fprintf('  %s array of openalgo.api\n', mat2str(size(obj)));
                return
            end
            if isequal(obj.authenticated, true)
                feed = 'connected';
            else
                feed = 'not connected';
            end
            fprintf('  openalgo.api client\n');
            fprintf('    base_url: %s\n', char(string(obj.base_url)));
            fprintf('    ws_url:   %s\n', char(string(obj.ws_url)));
            fprintf('    feed:     %s\n', feed);
        end
    end
end
