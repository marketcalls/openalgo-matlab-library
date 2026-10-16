classdef Strategy < handle
%STRATEGY Send signals to an OpenAlgo strategy through its public webhook.
%   S = openalgo.Strategy(host_url, webhook_id) or
%   S = openalgo.Strategy(host_url, webhook_token="oaws_...", timeout=30)
%   creates a webhook sender.
%
%   It posts to the public webhook at /strategy/webhook/<token>, the
%   surface external alert senders reach. It is not under /api/v1 and takes
%   no API key: the token in the URL is the whole of the credential, so
%   treat it the way you would treat a password.
%
%   The token is shown exactly once, in the browser, when the strategy is
%   created or when the token is rotated. No endpoint returns it (only its
%   SHA-256 digest is stored), so if it is lost, rotate it on the strategy
%   page and copy the new one.
%
%   Two vocabularies, and each strategy kind refuses the other's:
%     batch:  start (which requires mode) and stop. A multi-leg spread
%             entered and exited as a unit.
%     signal: long_entry, long_exit, short_entry and short_exit. One alert
%             moves one leg. There is no start and no mode: the first
%             signal after the platform session boundary opens the run,
%             and the mode comes from the strategy's own live opt-in.
%
%   Constructor arguments:
%     host_url      - OpenAlgo server URL, e.g. "http://127.0.0.1:5000".
%                     Positional or name=value.
%     webhook_id    - The strategy's webhook token, the "oaws_..." value
%                     shown once in the browser. Named webhook_id for
%                     backwards compatibility. Positional or name=value.
%     webhook_token - The same value under its accurate name (name=value
%                     only). Wins over webhook_id when both are given.
%     timeout       - Request timeout in seconds (name=value only).
%                     Default 30.
%
%   Raises openalgo:valueError when no token is given under either name.
%
%   Strategy properties:
%     timeout     - Request timeout in seconds.
%     webhook_url - The webhook URL. It embeds the token, so it is a
%                   credential in its own right: do not log it.
%
%   Strategy methods:
%     send          - Post a raw payload to the webhook.
%     start         - Start a batch strategy (mode "live" or "sandbox").
%     stop          - Stop a batch strategy.
%     signal        - Send a signal-strategy action for one leg.
%     long_entry    - Open or reverse into a long on one leg.
%     long_exit     - Close a long on one leg.
%     short_entry   - Open or reverse into a short on one leg.
%     short_exit    - Close a short on one leg.
%     strategyorder - Removed; raises openalgo:notImplemented.
%     close         - Release the HTTP resources.
%
%   Displaying the object never shows the token.
%
%   Example:
%     s = openalgo.Strategy("http://127.0.0.1:5000", webhook_token="oaws_your_token");
%     r = s.start("sandbox");
%     r = s.long_entry(leg_id=1);
%     r = s.stop();
%
%   See also openalgo.api.

    properties
        %TIMEOUT Request timeout in seconds.
        timeout
    end

    properties (Dependent, SetAccess = private)
        %WEBHOOK_URL Webhook URL, which embeds the token (a credential).
        webhook_url
    end

    properties (Access = private, Hidden)
        HostUrl
        WebhookId
        IsClosed = false
    end

    methods
        function obj = Strategy(varargin)
            %STRATEGY Initialize the webhook sender.
            a = openalgo.internal.parseArgs('Strategy', varargin, ...
                {'host_url', []; 'webhook_id', []; 'webhook_token', []; 'timeout', 30.0}, ...
                {'host_url'}, 2, false);
            if ~openalgo.internal.isNone(a.webhook_token)
                token = a.webhook_token;
            else
                token = a.webhook_id;
            end
            if ~openalgo.internal.truthy(token)
                error('openalgo:valueError', ['A webhook token is required. Pass ' ...
                    'webhook_token=''oaws_...'' - the value shown once in the browser ' ...
                    'when the strategy was created or its token rotated.']);
            end
            obj.HostUrl = regexprep(char(a.host_url), '/+$', '');
            obj.WebhookId = token;
            obj.timeout = a.timeout;
        end

        function url = get.webhook_url(obj)
            url = [obj.HostUrl '/strategy/webhook/' openalgo.internal.pyStr(obj.WebhookId)];
        end

        function close(obj)
            %CLOSE Release the HTTP resources used by the sender.
            %   S.CLOSE() marks the sender as closed. After it, send raises
            %   openalgo:clientClosed.
            obj.IsClosed = true;
        end

        function disp(obj)
            %DISP Display the sender without revealing the token.
            if ~isscalar(obj)
                fprintf('  %s array of openalgo.Strategy\n', mat2str(size(obj)));
                return
            end
            fprintf('  Strategy(host_url=''%s'', webhook_token=<redacted>)\n', obj.HostUrl);
        end

        function result = send(obj, varargin)
            %SEND Post a raw payload to the webhook and return the parsed response.
            %   RESULT = S.SEND(PAYLOAD) posts the struct PAYLOAD as JSON.
            %
            %   Every documented outcome is returned rather than raised,
            %   including the rejections, because the result label is the
            %   contract: a 409 rejected_cooling_off and a 200
            %   rejected_dedupe both need reading. Only a transport failure
            %   or a non-JSON answer produces a locally built error struct
            %   (timeout_error, connection_error, http_error or json_error).
            %   Other failures raise an error.
            %
            %   Returns the server's response with code attached when the
            %   HTTP status was not 200. It carries status, result, message
            %   and, where applicable, strategy_id, run_id, stop_pending and
            %   exits.
            a = openalgo.internal.parseArgs('send', varargin, {'payload', []}, {'payload'}, 1, false);
            body = openalgo.internal.toJson(a.payload);
            if obj.IsClosed
                error('openalgo:clientClosed', 'Cannot send a request, as the client has been closed.');
            end
            timeoutValue = obj.timeout;
            if ~isnumeric(timeoutValue)
                timeoutValue = [];
            end
            try
                [code, text] = openalgo.internal.httpRequest('POST', obj.webhook_url, body, ...
                    timeoutValue, dictionary("Content-Type", "application/json"), []);
            catch ME
                [result, isTransport] = openalgo.internal.transportError(ME);
                if ~isTransport
                    rethrow(ME);
                end
                return
            end
            result = openalgo.internal.parsePostResponse(code, text, true);
        end

        function result = start(obj, varargin)
            %START Start a batch strategy: enter every leg.
            %   RESULT = S.START(MODE) or S.START(mode=MODE)
            %
            %   MODE is "live" or "sandbox". Required, exact and
            %   case-sensitive on the server. There is no default: the one a
            %   hurried reader would reach for is the one that places real
            %   orders.
            %
            %   Returns a struct with status, result, message, strategy_id
            %   and run_id.
            %
            %   Notes:
            %   - Live is opt-in per strategy. mode="live" on a strategy that
            %     has not enabled live trading answers 403
            %     rejected_live_disabled.
            %   - Two identical starts within 60 seconds are one signal
            %     (rejected_dedupe, reported as a success), because senders
            %     retry deliveries they believe failed.
            %   - A strategy that stopped within the last 30 seconds refuses
            %     a start with 409 rejected_cooling_off, so a misconfigured
            %     pair of alerts cannot oscillate.
            %   - start against a signal strategy is rejected_invalid_action.
            a = openalgo.internal.parseArgs('start', varargin, {'mode', []}, {'mode'}, 1, false);
            payload = struct();
            payload.action = 'start';
            payload.mode = a.mode;
            result = obj.send(payload);
        end

        function result = stop(obj, varargin)
            %STOP Stop a batch strategy: exit every owned position at market.
            %   RESULT = S.STOP()
            %
            %   Returns a struct with status, result, message, strategy_id,
            %   run_id, stop_pending and exits.
            %
            %   Notes:
            %   - "Strategy stop accepted" means the durable request reached
            %     the engine, not that the broker is flat. stop_pending true
            %     keeps the run current, subscribed and managed until exit
            %     fills confirm every owner is flat.
            %   - A stop is never blocked by the cooling-off window, and a
            %     stop against an already-stopped strategy does not arm it.
            openalgo.internal.parseArgs('stop', varargin, {}, {}, 0, false);
            payload = struct();
            payload.action = 'stop';
            result = obj.send(payload);
        end

        function result = signal(obj, varargin)
            %SIGNAL Send a signal-strategy action, naming the leg by id or by symbol.
            %   RESULT = S.SIGNAL(ACTION, leg_id=..., symbol=..., exchange=...)
            %
            %   ACTION    - long_entry, long_exit, short_entry or short_exit.
            %               Positional or name=value.
            %   leg_id    - Which leg the signal targets. Wins over
            %               symbol/exchange when both are given. Optional.
            %   symbol    - Leg symbol, used when leg_id is absent. Optional.
            %   exchange  - Exchange for symbol. Optional.
            %
            %   Returns a struct with status, result, message, strategy_id
            %   and run_id.
            %
            %   Notes:
            %   - A signal that does nothing is a success with a note, not a
            %     failure: "Signal accepted (already_long)". The notes are
            %     already_long, already_short, no_matching_position,
            %     outside_entry_window and outside_trading_window. Reporting
            %     a no-op as a failure invites a retry, and a retry on an
            %     order path is how one alert becomes two positions.
            %   - Being refused is different. A signal blocked by the
            %     strategy's direction, or naming a leg that does not exist,
            %     answers 400 rejected_invalid_action with the engine's own
            %     message.
            %   - An opposite entry squares the existing side first, then
            %     opens.
            %   - Signal actions skip the dedupe and cooling-off windows.
            %   - A signal leg on a derivatives exchange must name an exact
            %     listed contract. A base symbol plus an expiry rank is
            %     refused, not guessed.
            a = openalgo.internal.parseArgs('signal', varargin, ...
                {'action', []; 'leg_id', []; 'symbol', []; 'exchange', []}, {'action'}, 1, false);
            result = obj.sendSignal(a.action, a);
        end

        function result = long_entry(obj, varargin)
            %LONG_ENTRY Open or reverse into a long on one leg.
            %   RESULT = S.LONG_ENTRY(leg_id=..., symbol=..., exchange=...)
            %   See also openalgo.Strategy/signal.
            a = openalgo.internal.parseArgs('long_entry', varargin, ...
                {'leg_id', []; 'symbol', []; 'exchange', []}, {}, 0, false);
            result = obj.sendSignal('long_entry', a);
        end

        function result = long_exit(obj, varargin)
            %LONG_EXIT Close a long on one leg.
            %   RESULT = S.LONG_EXIT(leg_id=..., symbol=..., exchange=...)
            %   See also openalgo.Strategy/signal.
            a = openalgo.internal.parseArgs('long_exit', varargin, ...
                {'leg_id', []; 'symbol', []; 'exchange', []}, {}, 0, false);
            result = obj.sendSignal('long_exit', a);
        end

        function result = short_entry(obj, varargin)
            %SHORT_ENTRY Open or reverse into a short on one leg.
            %   RESULT = S.SHORT_ENTRY(leg_id=..., symbol=..., exchange=...)
            %   See also openalgo.Strategy/signal.
            a = openalgo.internal.parseArgs('short_entry', varargin, ...
                {'leg_id', []; 'symbol', []; 'exchange', []}, {}, 0, false);
            result = obj.sendSignal('short_entry', a);
        end

        function result = short_exit(obj, varargin)
            %SHORT_EXIT Close a short on one leg.
            %   RESULT = S.SHORT_EXIT(leg_id=..., symbol=..., exchange=...)
            %   See also openalgo.Strategy/signal.
            a = openalgo.internal.parseArgs('short_exit', varargin, ...
                {'leg_id', []; 'symbol', []; 'exchange', []}, {}, 0, false);
            result = obj.sendSignal('short_exit', a);
        end

        function result = strategyorder(obj, varargin) %#ok<STOUT,INUSD>
            %STRATEGYORDER Removed. The webhook it posted to no longer exists.
            %   The old surface took symbol, action (BUY/SELL) and
            %   position_size and read the LONG_ONLY / SHORT_ONLY / BOTH mode
            %   from the strategy's own configuration. The strategy module
            %   replaced it with two explicit vocabularies, so there is no
            %   mapping this method could make on its own: BUY is long_entry
            %   on a flat leg and short_exit on a short one, and guessing
            %   which would be guessing at an order.
            %
            %   Use start and stop for a batch strategy, or long_entry,
            %   long_exit, short_entry and short_exit for a signal strategy.
            %
            %   Always raises openalgo:notImplemented.
            error('openalgo:notImplemented', ['Strategy.strategyorder() was removed: the ' ...
                'webhook it posted to no longer exists. Use start(mode)/stop() for a ' ...
                'batch strategy, or long_entry()/long_exit()/short_entry()/short_exit() ' ...
                'for a signal strategy.']);
        end
    end

    methods (Access = private)
        function result = sendSignal(obj, action, a)
            payload = struct();
            payload.action = action;
            if ~openalgo.internal.isNone(a.leg_id)
                payload.leg_id = openalgo.internal.pyInt(a.leg_id);
            end
            if ~openalgo.internal.isNone(a.symbol)
                payload.symbol = a.symbol;
            end
            if ~openalgo.internal.isNone(a.exchange)
                payload.exchange = a.exchange;
            end
            result = obj.send(payload);
        end
    end
end
