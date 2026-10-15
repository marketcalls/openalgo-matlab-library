function result = strategylist(obj, varargin)
%STRATEGYLIST List the strategies this API key owns, newest first.
%   RESULT = CLIENT.STRATEGYLIST(status=STATUS, q=QUERY)
%
%   Parameters:
%     status - Filter by strategy status: "stopped", "running", "paused"
%              or "errored". An out-of-vocabulary value is a 400, not an
%              empty list. Optional.
%     q      - Case-insensitive substring match on the strategy name,
%              100 characters at most. Optional.
%     Other name=value pairs are passed through unchanged; [] values are
%     not sent.
%
%   Payload: apikey, status and q (when given), then the extra fields.
%
%   The strategy module is lifecycle plus reads only: building a strategy
%   stays in the browser wizard at /strategy. A strategy that is not yours
%   answers 404, identical to one that does not exist. Every route is a
%   POST to strategy/<route> with the identifier in the body. A non-200
%   answer with a JSON body (for example a 409 carrying stop_pending and
%   the per-leg outcomes, or a 400 whose message is a struct keyed by
%   field name) is returned as is, with code attached.
%
%   Returns a struct with status "success" and data, one entry per
%   strategy carrying id, name, strategy_kind, direction, product, the
%   risk settings, live_enabled, status, current_run_id and
%   last_finalized_run.
%
%   Notes:
%   - The list form omits legs. Call strategystatus for one strategy's
%     legs.
%   - For a stopped strategy, last_finalized_run.pnl_realized is the
%     durable final P&L; do not infer it from an earlier checkpoint.
%
%   Example:
%     r = client.strategylist(status="running");
%
%   See also openalgo.api/strategystatus.

[a, kw] = openalgo.internal.parseArgs('strategylist', varargin, ...
    {'status', []; 'q', []}, {}, 0, true);

payload = struct();
payload.apikey = obj.api_key;
% Unset optional filters are dropped, not sent as null.
filters = {'status', a.status; 'q', a.q};
payload = openalgo.internal.addKwargs(payload, [filters; kw], false);

result = obj.post('strategy/list', payload);
end
