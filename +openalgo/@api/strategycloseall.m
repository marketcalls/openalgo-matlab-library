function result = strategycloseall(obj, varargin)
%STRATEGYCLOSEALL Close every leg of the current run, recording an operator's intent.
%   RESULT = CLIENT.STRATEGYCLOSEALL(strategy_id=ID)
%
%   Parameters:
%     strategy_id - Strategy id, a positive integer. Required.
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
%   Same stop mechanics as strategystop, different audit intent: a
%   close_all_manual event is written before the stop persists, which
%   proves an operator asked for a flatten. It is not proof that the
%   broker became flat; run_stopped is that terminal evidence.
%
%   Returns a struct with status "success", run_id, stop_pending and
%   exits, the same shape as strategystop.
%
%   Example:
%     r = client.strategycloseall(strategy_id=12);
%
%   See also openalgo.api/strategystop, openalgo.api/strategycloseleg.

[a, kw] = openalgo.internal.parseArgs('strategycloseall', varargin, ...
    {'strategy_id', []}, {'strategy_id'}, 0, true);

payload = struct();
payload.apikey = obj.api_key;
payload.strategy_id = openalgo.internal.pyInt(a.strategy_id);
payload = openalgo.internal.addKwargs(payload, kw, false);

result = obj.post('strategy/close_all', payload);
end
