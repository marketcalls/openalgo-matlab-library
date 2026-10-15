function result = modifygttorder(obj, varargin)
%MODIFYGTTORDER Modify an active GTT trigger.
%   RESULT = CLIENT.MODIFYGTTORDER(trigger_id=ID, Name=Value)
%
%   Modify is a full replacement, not a patch: every field on the trigger
%   is replaced by what this call sends, so pass everything you want to
%   keep rather than only the values that changed.
%
%   Parameters:
%     trigger_id - The trigger to modify, as returned by placegttorder.
%                  Required. Sent as text, after every other field.
%     Everything else is identical to placegttorder (strategy, symbol,
%     action, exchange, trigger_type, product, quantity, price_type,
%     price, triggerprice_sl, triggerprice_tg, stoploss, target and extra
%     name=value pairs), with the same validation.
%
%   Returns a struct with status "success" and trigger_id on success.
%
%   What cannot be modified:
%   - trigger_type (SINGLE to OCO or back), symbol, exchange and action
%     are fixed. Cancel and re-place instead.
%   - Only active GTTs are modifiable; triggered, cancelled and expired
%     ones are immutable.
%
%   Example:
%     r = client.modifygttorder(trigger_id="GTT-123", symbol="SBIN", exchange="NSE", ...
%         action="BUY", quantity=2, price=695, triggerprice_sl=696);
%
%   See also openalgo.api/placegttorder, openalgo.api/cancelgttorder.

[a, kw] = openalgo.internal.parseArgs('modifygttorder', varargin, ...
    {'trigger_id', []; 'strategy', 'Python'; 'symbol', []; 'action', []; 'exchange', []; ...
     'trigger_type', 'SINGLE'; 'product', 'CNC'; 'quantity', 1; ...
     'price_type', 'LIMIT'; 'price', 0; 'triggerprice_sl', 0; 'triggerprice_tg', 0; ...
     'stoploss', []; 'target', []}, ...
    {'trigger_id', 'symbol', 'action', 'exchange'}, 0, true);

[payload, err] = gttPayload(obj.api_key, a, kw);
if ~isempty(err)
    result = err;
    return
end
payload.trigger_id = openalgo.internal.pyStr(a.trigger_id);
result = obj.post('modifygttorder', payload);
end
