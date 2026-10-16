function result = placegttorder(obj, varargin)
%PLACEGTTORDER Place a GTT (Good Till Triggered) order.
%   RESULT = CLIENT.PLACEGTTORDER(Name=Value)
%
%   A GTT is a price trigger that sits with the broker until LTP crosses
%   the level, at which point the underlying order is placed
%   automatically. Two trigger types, and picking the wrong one is the
%   usual mistake:
%
%   - SINGLE: one trigger, one order. Exactly one of triggerprice_sl and
%     triggerprice_tg carries the level and the other stays 0. The suffix
%     is only a directional hint (_sl for a level below LTP, _tg for one
%     above), because a SINGLE GTT has no stoploss leg to name.
%   - OCO: two triggers, one of which fires and cancels the other. Here
%     the suffix is a real role: triggerprice_sl is the stoploss leg's
%     trigger with stoploss as its limit, triggerprice_tg is the target
%     leg's trigger with target as its limit, and all four are required.
%
%   Parameters:
%     strategy        - Strategy identifier, used as the broker correlation
%                       id where supported. Default "MATLAB".
%     symbol          - Trading symbol in OpenAlgo format. Required.
%     action          - "BUY" or "SELL". For OCO it applies to both legs.
%                       Required.
%     exchange        - Exchange code. Required.
%     trigger_type    - "SINGLE" or "OCO". Default "SINGLE".
%     product         - "CNC" or "NRML". MIS is refused. Default "CNC".
%     quantity        - Order quantity. Integer for equity and F&O; a
%                       fractional value is only accepted on crypto
%                       exchanges. Default 1.
%     price_type      - "LIMIT" or "MARKET". Default "LIMIT".
%     price           - SINGLE only: the child order's limit price. Send 0
%                       with price_type="MARKET". Ignored for OCO.
%                       Default 0.
%     triggerprice_sl - Trigger below LTP. For SINGLE use this or
%                       triggerprice_tg; for OCO it is the stoploss leg's
%                       trigger. Default 0.
%     triggerprice_tg - Trigger above LTP. For SINGLE use this or
%                       triggerprice_sl; for OCO it is the target leg's
%                       trigger. Default 0.
%     stoploss        - OCO only: the stoploss leg's limit price.
%                       Default [] (sent as null).
%     target          - OCO only: the target leg's limit price.
%                       Default [] (sent as null).
%     Other name=value pairs are passed through unchanged.
%
%   GTT numeric fields go out as JSON numbers rather than the strings the
%   rest of the order surface sends, because the server validates them as
%   floats. For SINGLE, stoploss and target are sent as JSON null.
%   Payload: apikey, strategy, trigger_type, exchange, symbol, action,
%   product, quantity, pricetype, price, triggerprice_sl, triggerprice_tg,
%   stoploss, target, then the extra fields.
%
%   Validation mirrors the server's own rules, so a bad SINGLE/OCO
%   combination is reported before an order leaves the machine, as a
%   struct with error_type 'validation_error' (not raised):
%     "trigger_type must be 'SINGLE' or 'OCO'."
%     "Required for OCO: <names>."
%     "Stoploss trigger must be less than target trigger (triggerprice_sl < triggerprice_tg)."
%     "SINGLE GTT requires a positive triggerprice_sl or triggerprice_tg."
%     "SINGLE GTT takes exactly one of triggerprice_sl or triggerprice_tg; set the other to 0."
%
%   Returns a struct with status "success" and trigger_id on success. Save
%   the trigger_id: modify and cancel both need it.
%
%   Notes:
%   - last_price is fetched server-side; do not send it.
%   - In analyzer (sandbox) mode the trigger is placed in the sandbox: the
%     response carries mode "analyze" and a GTT-... trigger_id, and it
%     fires against live LTP exactly as it would at the broker.
%
%   Examples:
%     % SINGLE: buy when price falls to 700
%     r = client.placegttorder(symbol="SBIN", exchange="NSE", action="BUY", ...
%         quantity=1, price=700, triggerprice_sl=701);
%
%     % OCO: protect a holding with a stoploss and a target
%     r = client.placegttorder(symbol="SBIN", exchange="NSE", action="SELL", ...
%         trigger_type="OCO", quantity=1, triggerprice_sl=700, stoploss=699, ...
%         triggerprice_tg=850, target=849);
%
%   See also openalgo.api/modifygttorder, openalgo.api/cancelgttorder,
%   openalgo.api/gttorderbook.

[a, kw] = openalgo.internal.parseArgs('placegttorder', varargin, ...
    {'strategy', 'MATLAB'; 'symbol', []; 'action', []; 'exchange', []; ...
     'trigger_type', 'SINGLE'; 'product', 'CNC'; 'quantity', 1; ...
     'price_type', 'LIMIT'; 'price', 0; 'triggerprice_sl', 0; 'triggerprice_tg', 0; ...
     'stoploss', []; 'target', []}, ...
    {'symbol', 'action', 'exchange'}, 0, true);

[payload, err] = gttPayload(obj.api_key, a, kw);
if ~isempty(err)
    result = err;
    return
end
result = obj.post('placegttorder', payload);
end
