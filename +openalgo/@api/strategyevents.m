function result = strategyevents(obj, varargin)
%STRATEGYEVENTS Get the risk-event audit trail for a strategy, newest first.
%   RESULT = CLIENT.STRATEGYEVENTS(strategy_id=ID, Name=Value)
%
%   Parameters:
%     strategy_id - Strategy id, a positive integer. Required.
%     run_id      - Narrow the result to one run. Configuration events
%                   carry run_id null, so this filter excludes them.
%                   Optional.
%     kind        - Filter by event kind. Must be a member of the
%                   event-kind vocabulary; anything else is a 400.
%                   Optional.
%     severity    - "info", "warn" or "critical". Optional.
%     limit       - How many events to return, 1 to 1000. Server default
%                   500. A value outside the range is a 400, not a clamp.
%                   Optional.
%     Other name=value pairs are passed through unchanged; [] values are
%     not sent.
%
%   Payload: apikey, strategy_id (as an integer), run_id, kind, severity and limit (when given), then the extra fields.
%
%   The strategy module is lifecycle plus reads only: building a strategy
%   stays in the browser wizard at /strategy. A strategy that is not yours
%   answers 404, identical to one that does not exist. Every route is a
%   POST to strategy/<route> with the identifier in the body. A non-200
%   answer with a JSON body (for example a 409 carrying stop_pending and
%   the per-leg outcomes, or a 400 whose message is a struct keyed by
%   field name) is returned as is, with code attached.
%
%   Returns a struct with status "success" and data, one entry per event
%   carrying id, run_id, strategy_id, ts, kind, severity, leg_id, message
%   and payload.
%
%   Event kinds an operator should not ignore:
%   - run_stop_requested (info): the stop is durable and new signal
%     entries are gated. It is not proof the broker is flat.
%   - run_stop_failed (critical): the broker refused a stop's exits and
%     the run is still holding those positions.
%   - order_ack_unrecorded (critical): the broker accepted an order but
%     its acknowledgement could not be written; it reconciles itself.
%   - leg_expiry_fallback (warn): the chain did not list the expiry rank
%     the leg asked for, so a nearer one was used.
%   - flip_outgoing_exit_rejected (critical): the outgoing side of a
%     signal flip is still held.
%
%   Notes:
%   - The trail is append-only; nothing updates or deletes a row.
%   - payload is free-form JSON and null on most events. Do not assume
%     one shape across kinds.
%
%   Example:
%     r = client.strategyevents(strategy_id=12, severity="critical", limit=50);
%
%   See also openalgo.api/strategyruns, openalgo.api/strategyorders.

[a, kw] = openalgo.internal.parseArgs('strategyevents', varargin, ...
    {'strategy_id', []; 'run_id', []; 'kind', []; 'severity', []; 'limit', []}, {'strategy_id'}, 0, true);

payload = struct();
payload.apikey = obj.api_key;
payload.strategy_id = openalgo.internal.pyInt(a.strategy_id);
% Unset optional filters are dropped, not sent as null.
filters = {'run_id', a.run_id; 'kind', a.kind; 'severity', a.severity; 'limit', a.limit};
payload = openalgo.internal.addKwargs(payload, [filters; kw], false);

result = obj.post('strategy/events', payload);
end
