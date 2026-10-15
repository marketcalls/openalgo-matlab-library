function result = strategystop(obj, varargin)
%STRATEGYSTOP Stop the strategy's current run: exit every owned position at market.
%   RESULT = CLIENT.STRATEGYSTOP(strategy_id=ID)
%
%   Parameters:
%     strategy_id - Strategy id, a positive integer. Required. The run is
%                   resolved from the strategy; a caller never supplies a
%                   run id.
%     Other name=value pairs are passed through unchanged; [] values are
%     not sent.
%
%   Payload: apikey, strategy_id (as an integer), then the extra fields.
%
%   The strategy module is lifecycle plus reads only: building a strategy
%   stays in the browser wizard at /strategy. A strategy that is not yours
%   answers 404, identical to one that does not exist. Every route is a
%   POST to strategy/<route> with the identifier in the body. A non-200
%   answer with a JSON body (for example a 409 carrying stop_pending and
%   the per-leg outcomes, or a 400 whose message is a struct keyed by
%   field name) is returned as is, with code attached.
%
%   Returns a struct with status "success", run_id, stop_pending and
%   exits, one entry per leg carrying leg_id, ok, position_ref, exit_owner
%   and error.
%
%   Notes:
%   - An accepted stop is not necessarily flat. stop_pending true means
%     the request is durable and its exits were accepted, but the run
%     stays open, subscribed and managed until fills prove every position
%     is flat. Never infer flatness from the HTTP status.
%   - 409 when nothing is running, and 409 can also carry stop_pending
%     true when an unfilled entry or a refused exit still needs
%     management. Retry the stop in that case.
%   - A leg whose entry was accepted but not filled is not exited and the
%     stop is reported as refused: there is no confirmed quantity to
%     close.
%
%   Example:
%     r = client.strategystop(strategy_id=12);
%     if isfield(r, "stop_pending") && r.stop_pending
%         % exits accepted but not yet filled
%     end
%
%   See also openalgo.api/strategycloseall, openalgo.api/strategystart.

[a, kw] = openalgo.internal.parseArgs('strategystop', varargin, ...
    {'strategy_id', []}, {'strategy_id'}, 0, true);

payload = struct();
payload.apikey = obj.api_key;
payload.strategy_id = openalgo.internal.pyInt(a.strategy_id);
payload = openalgo.internal.addKwargs(payload, kw, false);

result = obj.post('strategy/stop', payload);
end
