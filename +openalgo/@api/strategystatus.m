function result = strategystatus(obj, varargin)
%STRATEGYSTATUS Get one strategy's full configuration including legs, and its current run.
%   RESULT = CLIENT.STRATEGYSTATUS(strategy_id=ID)
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
%   Returns a struct with status "success", data and run. run is empty
%   (JSON null) whenever the strategy has no current run, which is the
%   normal state of a stopped strategy.
%
%   Notes:
%   - A populated run.stop_requested_reason means a stop is durable but
%     not yet confirmed flat. The run is still current and still managed.
%   - run.resolved_expiries is the snapshot taken at run start, so a
%     positional strategy does not roll to a new contract mid-run.
%   - Prefer run over the strategy's own status when you need to know
%     whether anything is actually open.
%
%   Example:
%     r = client.strategystatus(strategy_id=12);
%
%   See also openalgo.api/strategylist, openalgo.api/strategyruns.

[a, kw] = openalgo.internal.parseArgs('strategystatus', varargin, ...
    {'strategy_id', []}, {'strategy_id'}, 0, true);

payload = struct();
payload.apikey = obj.api_key;
payload.strategy_id = openalgo.internal.pyInt(a.strategy_id);
payload = openalgo.internal.addKwargs(payload, kw, false);

result = obj.post('strategy/status', payload);
end
