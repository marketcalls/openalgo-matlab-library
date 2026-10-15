function result = placesmartorder(obj, varargin)
%PLACESMARTORDER Place a smart order that considers the current position size.
%   RESULT = CLIENT.PLACESMARTORDER(Name=Value)
%
%   Parameters:
%     strategy      - The trading strategy name. Default "Python".
%     symbol        - Trading symbol. Required.
%     action        - "BUY" or "SELL". Required.
%     exchange      - Exchange code. Required.
%     price_type    - Type of price. Default "MARKET".
%     product       - Product type. Default "MIS".
%     quantity      - Quantity to trade. Default 1.
%     position_size - Required position size. Required.
%     Other name=value pairs are sent as extra fields, as text, for example
%     price, trigger_price, disclosed_quantity, target, stoploss and
%     trailing_sl.
%
%   Payload: apikey, strategy, symbol, action, exchange, pricetype,
%   product, quantity and position_size (both as text), then the extra
%   fields as text.
%
%   Returns the JSON response as a struct.
%
%   Example:
%     resp = client.placesmartorder(strategy="Python", symbol="TATAMOTORS", ...
%         action="SELL", exchange="NSE", price_type="MARKET", product="MIS", ...
%         quantity=1, position_size=5);
%
%   See also openalgo.api/placeorder.

[a, kw] = openalgo.internal.parseArgs('placesmartorder', varargin, ...
    {'strategy', 'Python'; 'symbol', []; 'action', []; 'exchange', []; ...
     'price_type', 'MARKET'; 'product', 'MIS'; 'quantity', 1; 'position_size', []}, ...
    {'symbol', 'action', 'exchange', 'position_size'}, 0, true);

payload = struct();
payload.apikey = obj.api_key;
payload.strategy = a.strategy;
payload.symbol = a.symbol;
payload.action = a.action;
payload.exchange = a.exchange;
payload.pricetype = a.price_type;
payload.product = a.product;
payload.quantity = openalgo.internal.pyStr(a.quantity);
payload.position_size = openalgo.internal.pyStr(a.position_size);
payload = openalgo.internal.addKwargs(payload, kw, true);

result = obj.makeRequest('placesmartorder', payload);
end
