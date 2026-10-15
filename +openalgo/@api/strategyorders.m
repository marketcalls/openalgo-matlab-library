function result = strategyorders(obj, varargin)
%STRATEGYORDERS Get every order the engine placed across a strategy's runs.
%   RESULT = CLIENT.STRATEGYORDERS(strategy_id=ID, run_id=RUN)
%
%   Parameters:
%     strategy_id - Strategy id, a positive integer. Required.
%     run_id      - Narrow the result to one run. A run belonging to
%                   another strategy matches nothing rather than leaking
%                   its orders. Optional.
%     Other name=value pairs are passed through unchanged; [] values are
%     not sent.
%
%   Payload: apikey, strategy_id (as an integer), run_id (when given), then the extra fields.
%
%   The strategy module is lifecycle plus reads only: building a strategy
%   stays in the browser wizard at /strategy. A strategy that is not yours
%   answers 404, identical to one that does not exist. Every route is a
%   POST to strategy/<route> with the identifier in the body. A non-200
%   answer with a JSON body (for example a 409 carrying stop_pending and
%   the per-leg outcomes, or a 400 whose message is a struct keyed by
%   field name) is returned as is, with code attached.
%
%   Returns a struct with status "success" and data, one entry per order
%   carrying id, run_id, leg_id, kind, position_ref, broker_order_id,
%   symbol, exchange, action, qty, product, pricetype, price, status,
%   placed_at, filled_at, avg_fill_price, filled_qty and reject_reason.
%
%   Notes:
%   - Rows are oldest first, so an entry always precedes its exit. This is
%     the opposite ordering to strategyruns and strategyevents.
%   - A row is written before the broker answers, so an order can appear
%     with status "pending" and a null broker_order_id.
%   - A positive filled_qty proves exposure in every status, including
%     cancelled and rejected.
%   - There is no limit parameter here. Narrow with run_id instead.
%
%   Example:
%     r = client.strategyorders(strategy_id=12, run_id=40);
%
%   See also openalgo.api/strategyruns.

[a, kw] = openalgo.internal.parseArgs('strategyorders', varargin, ...
    {'strategy_id', []; 'run_id', []}, {'strategy_id'}, 0, true);

payload = struct();
payload.apikey = obj.api_key;
payload.strategy_id = openalgo.internal.pyInt(a.strategy_id);
% Unset optional filters are dropped, not sent as null.
filters = {'run_id', a.run_id};
payload = openalgo.internal.addKwargs(payload, [filters; kw], false);

result = obj.post('strategy/orders', payload);
end
