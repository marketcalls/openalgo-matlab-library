function result = strategycloseleg(obj, varargin)
%STRATEGYCLOSELEG Exit one leg of the current run at market. The run continues with the rest.
%   RESULT = CLIENT.STRATEGYCLOSELEG(strategy_id=ID, leg_id=LEG)
%
%   Parameters:
%     strategy_id - Strategy id, a positive integer. Required.
%     leg_id      - The leg's id within the strategy, the same value that
%                   appears in legs(i).id on strategystatus. Not an order
%                   id and not a run id. Required. Sent as an integer.
%     Other name=value pairs are passed through unchanged; [] values are
%     not sent.
%
%   Payload: apikey, strategy_id and leg_id (as integers), then the extra fields.
%
%   The strategy module is lifecycle plus reads only: building a strategy
%   stays in the browser wizard at /strategy. A strategy that is not yours
%   answers 404, identical to one that does not exist. Every route is a
%   POST to strategy/<route> with the identifier in the body. A non-200
%   answer with a JSON body (for example a 409 carrying stop_pending and
%   the per-leg outcomes, or a 400 whose message is a struct keyed by
%   field name) is returned as is, with code attached.
%
%   Returns a struct with status "success", run_id, leg_id, run_stopped
%   and exits.
%
%   Notes:
%   - run_stopped reports only what this call could prove. A live broker
%     normally acknowledges before its fill, so even the last accepted
%     exit returns false and the fill finalises the run later.
%   - A refused exit is a failure, not a close: read the per-leg ok. The
%     leg stays retryable, so its stop, its target and the scheduler's
%     square-off can all still reach it.
%   - A leg_id that names no open leg is a 409, not a 404. The strategy
%     was found; the leg is simply not in a state that can be closed.
%
%   Example:
%     r = client.strategycloseleg(strategy_id=12, leg_id=3);
%
%   See also openalgo.api/strategystatus, openalgo.api/strategycloseall.

[a, kw] = openalgo.internal.parseArgs('strategycloseleg', varargin, ...
    {'strategy_id', []; 'leg_id', []}, {'strategy_id', 'leg_id'}, 0, true);

payload = struct();
payload.apikey = obj.api_key;
payload.strategy_id = openalgo.internal.pyInt(a.strategy_id);
payload.leg_id = openalgo.internal.pyInt(a.leg_id);
payload = openalgo.internal.addKwargs(payload, kw, false);

result = obj.post('strategy/close_leg', payload);
end
