function result = cancelgttorder(obj, varargin)
%CANCELGTTORDER Cancel an active GTT trigger.
%   RESULT = CLIENT.CANCELGTTORDER(trigger_id=ID, strategy="Python")
%
%   Parameters:
%     trigger_id - The trigger to cancel. Required. Sent as text.
%     strategy   - Strategy identifier, recorded in event logs.
%                  Default "Python".
%     Other name=value pairs are passed through unchanged.
%
%   Payload: apikey, strategy, trigger_id, then the extra fields.
%
%   Returns a struct with status "success" and trigger_id on success.
%
%   Notes:
%   - Cancelling an OCO removes both legs atomically; there is no per-leg
%     cancel.
%   - Only active triggers can be cancelled. Cancelling one that already
%     fired returns whatever the broker says, which may be a success or a
%     "trigger not found" error depending on the broker.
%
%   Example:
%     r = client.cancelgttorder(trigger_id="GTT-123");
%
%   See also openalgo.api/placegttorder, openalgo.api/gttorderbook.

[a, kw] = openalgo.internal.parseArgs('cancelgttorder', varargin, ...
    {'trigger_id', []; 'strategy', 'Python'}, {'trigger_id'}, 0, true);

payload = struct();
payload.apikey = obj.api_key;
payload.strategy = a.strategy;
payload.trigger_id = openalgo.internal.pyStr(a.trigger_id);
payload = openalgo.internal.addKwargs(payload, kw, false);

result = obj.post('cancelgttorder', payload);
end
