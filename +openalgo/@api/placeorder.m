function result = placeorder(obj, varargin)
%PLACEORDER Place an order.
%   RESULT = CLIENT.PLACEORDER(Name=Value) places an order with the given
%   parameters. All parameters are name=value.
%
%   Parameters:
%     strategy    - The trading strategy name. Default "Python".
%     symbol      - Trading symbol. Required.
%     action      - "BUY" or "SELL". Required.
%     exchange    - Exchange code. Required.
%     price_type  - Type of price. Default "MARKET".
%     product     - Product type. Default "MIS".
%     quantity    - Quantity to trade. Default 1.
%     Other name=value pairs are sent as extra fields, as text (Python
%     str()), for example:
%       price              - Required for LIMIT orders.
%       trigger_price      - Required for SL and SL-M orders.
%       disclosed_quantity - Disclosed quantity.
%       target             - Target price.
%       stoploss           - Stoploss price.
%       trailing_sl        - Trailing stoploss points.
%
%   Payload: apikey, strategy, symbol, action, exchange, pricetype,
%   product, quantity (as text), then the extra fields as text.
%
%   Returns the JSON response as a struct, for example with fields orderid
%   and status.
%
%   Example:
%     resp = client.placeorder(strategy="Python", symbol="SBIN", action="BUY", ...
%         exchange="NSE", price_type="LIMIT", product="MIS", quantity=1, price=750);
%
%   See also openalgo.api/placesmartorder, openalgo.api/modifyorder.

[a, kw] = openalgo.internal.parseArgs('placeorder', varargin, ...
    {'strategy', 'Python'; 'symbol', []; 'action', []; 'exchange', []; ...
     'price_type', 'MARKET'; 'product', 'MIS'; 'quantity', 1}, ...
    {'symbol', 'action', 'exchange'}, 0, true);

payload = struct();
payload.apikey = obj.api_key;
payload.strategy = a.strategy;
payload.symbol = a.symbol;
payload.action = a.action;
payload.exchange = a.exchange;
payload.pricetype = a.price_type;
payload.product = a.product;
payload.quantity = openalgo.internal.pyStr(a.quantity);
payload = openalgo.internal.addKwargs(payload, kw, true);

result = obj.makeRequest('placeorder', payload);
end
