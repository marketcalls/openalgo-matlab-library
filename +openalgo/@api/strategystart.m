function result = strategystart(obj, varargin)
%STRATEGYSTART Start a run of a batch strategy. Every leg's entry order is placed.
%   RESULT = CLIENT.STRATEGYSTART(strategy_id=ID, mode=MODE)
%
%   Parameters:
%     strategy_id - Strategy id, a positive integer. Required.
%     mode        - "live" or "sandbox". Required, exact and
%                   case-sensitive, and passed through exactly as given.
%                   There is no default anywhere in the chain: the default
%                   a hurried reader would reach for is the one that
%                   places real orders.
%     Other name=value pairs are passed through unchanged; [] values are
%     not sent.
%
%   Payload: apikey, strategy_id (as an integer), mode, then the extra fields.
%
%   The strategy module is lifecycle plus reads only: building a strategy
%   stays in the browser wizard at /strategy. A strategy that is not yours
%   answers 404, identical to one that does not exist. Every route is a
%   POST to strategy/<route> with the identifier in the body. A non-200
%   answer with a JSON body (for example a 409 carrying stop_pending and
%   the per-leg outcomes, or a 400 whose message is a struct keyed by
%   field name) is returned as is, with code attached.
%
%   Returns a struct with status "success", run_id, mode and legs, one
%   entry per leg carrying leg_id, ok, acknowledged, symbol,
%   broker_order_id and error.
%
%   Notes:
%   - Live is opt-in per strategy: a strategy is created sandbox-only and
%     mode="live" is refused with a 409 until live trading is enabled on
%     the strategy page.
%   - Partial success is a 200. Check legs(i).ok rather than assuming
%     every leg reached the market.
%   - ok true with acknowledged false is a real broker order whose id
%     could not be written back, not a rejection. It reconciles itself.
%   - A run whose entries were all rejected is closed immediately and the
%     call answers 400.
%   - A second start against a running strategy answers 409, so two
%     triggers firing at once cannot both place a full set of entries.
%   - This is for batch strategies. A signal strategy has no start: its
%     first inbound signal after the platform session boundary opens the
%     run.
%
%   Example:
%     r = client.strategystart(strategy_id=12, mode="sandbox");
%
%   See also openalgo.api/strategystop, openalgo.api/strategystatus.

[a, kw] = openalgo.internal.parseArgs('strategystart', varargin, ...
    {'strategy_id', []; 'mode', []}, {'strategy_id', 'mode'}, 0, true);

payload = struct();
payload.apikey = obj.api_key;
payload.strategy_id = openalgo.internal.pyInt(a.strategy_id);
payload.mode = a.mode;
payload = openalgo.internal.addKwargs(payload, kw, false);

result = obj.post('strategy/start', payload);
end
