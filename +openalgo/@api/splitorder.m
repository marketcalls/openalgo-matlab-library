function result = splitorder(obj, varargin)
%SPLITORDER Split a large order into multiple smaller orders.
%   RESULT = CLIENT.SPLITORDER(Name=Value)
%
%   Parameters:
%     strategy   - The trading strategy name. Default "MATLAB".
%     symbol     - Trading symbol. Required.
%     action     - "BUY" or "SELL". Required.
%     exchange   - Exchange code. Required.
%     quantity   - Total quantity to trade. Required.
%     splitsize  - Size of each split order. Required.
%     price_type - Type of price. Default "MARKET".
%     product    - Product type. Default "MIS".
%     Other name=value pairs are sent as extra fields, as text, for example
%     price, trigger_price and disclosed_quantity.
%
%   Payload: apikey, strategy, symbol, action, exchange, quantity and
%   splitsize (both as text), pricetype, product, then the extra fields.
%
%   Returns a struct with status, split_size, total_quantity and results,
%   one entry (order_num, orderid, quantity, status) per split order.
%
%   Example:
%     resp = client.splitorder(symbol="YESBANK", exchange="NSE", action="SELL", ...
%         quantity=105, splitsize=20, price_type="MARKET", product="MIS");
%
%   See also openalgo.api/placeorder, openalgo.api/basketorder.

[a, kw] = openalgo.internal.parseArgs('splitorder', varargin, ...
    {'strategy', 'MATLAB'; 'symbol', []; 'action', []; 'exchange', []; ...
     'quantity', []; 'splitsize', []; 'price_type', 'MARKET'; 'product', 'MIS'}, ...
    {'symbol', 'action', 'exchange', 'quantity', 'splitsize'}, 0, true);

payload = struct();
payload.apikey = obj.api_key;
payload.strategy = a.strategy;
payload.symbol = a.symbol;
payload.action = a.action;
payload.exchange = a.exchange;
payload.quantity = openalgo.internal.pyStr(a.quantity);
payload.splitsize = openalgo.internal.pyStr(a.splitsize);
payload.pricetype = a.price_type;
payload.product = a.product;
payload = openalgo.internal.addKwargs(payload, kw, true);

result = obj.makeRequest('splitorder', payload);
end
