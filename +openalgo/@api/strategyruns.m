function result = strategyruns(obj, varargin)
%STRATEGYRUNS Get every activation of a strategy, newest first.
%   RESULT = CLIENT.STRATEGYRUNS(strategy_id=ID, limit=N)
%
%   Parameters:
%     strategy_id - Strategy id, a positive integer. Required.
%     limit       - How many runs to return, 1 to 500. Server default 100.
%                   A value outside the range is a 400, not a clamp.
%                   Optional.
%     Other name=value pairs are passed through unchanged; [] values are
%     not sent.
%
%   Payload: apikey, strategy_id (as an integer), limit (when given), then the extra fields.
%
%   The strategy module is lifecycle plus reads only: building a strategy
%   stays in the browser wizard at /strategy. A strategy that is not yours
%   answers 404, identical to one that does not exist. Every route is a
%   POST to strategy/<route> with the identifier in the body. A non-200
%   answer with a JSON body (for example a 409 carrying stop_pending and
%   the per-leg outcomes, or a 400 whose message is a struct keyed by
%   field name) is returned as is, with code attached.
%
%   Returns a struct with status "success" and data, one entry per run
%   carrying id, mode, broker, started_at, stopped_at, stop_reason,
%   stop_requested_at, stop_requested_reason, pnl_realized, pnl_peak,
%   pnl_trough, trigger_source, webhook_event_id and resolved_expiries.
%
%   Notes:
%   - The row at the top is the current run only while stopped_at is
%     null.
%   - pnl_peak and pnl_trough are authoritative only once the run has
%     stopped; while it is open the checkpoints are the authority.
%   - An overall threshold triggers an exit, it does not promise the
%     result. Market exits fill at the available bid/ask, so pnl_realized
%     can differ from the threshold that caused the stop.
%
%   Example:
%     r = client.strategyruns(strategy_id=12, limit=10);
%
%   See also openalgo.api/strategyorders, openalgo.api/strategyevents.

[a, kw] = openalgo.internal.parseArgs('strategyruns', varargin, ...
    {'strategy_id', []; 'limit', []}, {'strategy_id'}, 0, true);

payload = struct();
payload.apikey = obj.api_key;
payload.strategy_id = openalgo.internal.pyInt(a.strategy_id);
% Unset optional filters are dropped, not sent as null.
filters = {'limit', a.limit};
payload = openalgo.internal.addKwargs(payload, [filters; kw], false);

result = obj.post('strategy/runs', payload);
end
