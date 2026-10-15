function result = modifyorder(obj, varargin)
%MODIFYORDER Modify an existing order.
%   RESULT = CLIENT.MODIFYORDER(Name=Value)
%
%   Parameters:
%     order_id           - The ID of the order to modify. Required.
%     strategy           - The trading strategy name. Default "Python".
%     symbol             - Trading symbol. Required.
%     action             - "BUY" or "SELL". Required.
%     exchange           - Exchange code. Required.
%     price_type         - Type of price. Default "LIMIT".
%     product            - Product type. Required.
%     quantity           - Quantity to trade. Required.
%     price              - New price for the order. Required.
%     disclosed_quantity - Disclosed quantity. Default "0".
%     trigger_price      - Trigger price. Default "0".
%     Other name=value pairs are sent as extra fields, as text.
%
%   Payload: apikey, orderid, strategy, symbol, action, exchange,
%   pricetype, product, quantity, price, disclosed_quantity and
%   trigger_price (the last four as text), then the extra fields.
%
%   Returns the JSON response as a struct.
%
%   Example:
%     resp = client.modifyorder(order_id="24120900146469", strategy="Python", ...
%         symbol="YESBANK", action="BUY", exchange="NSE", price_type="LIMIT", ...
%         product="CNC", quantity=1, price=16.5);
%
%   See also openalgo.api/placeorder, openalgo.api/cancelorder.

[a, kw] = openalgo.internal.parseArgs('modifyorder', varargin, ...
    {'order_id', []; 'strategy', 'Python'; 'symbol', []; 'action', []; ...
     'exchange', []; 'price_type', 'LIMIT'; 'product', []; 'quantity', []; ...
     'price', []; 'disclosed_quantity', '0'; 'trigger_price', '0'}, ...
    {'order_id', 'symbol', 'action', 'exchange', 'product', 'quantity', 'price'}, 0, true);

payload = struct();
payload.apikey = obj.api_key;
payload.orderid = a.order_id;
payload.strategy = a.strategy;
payload.symbol = a.symbol;
payload.action = a.action;
payload.exchange = a.exchange;
payload.pricetype = a.price_type;
payload.product = a.product;
payload.quantity = openalgo.internal.pyStr(a.quantity);
payload.price = openalgo.internal.pyStr(a.price);
payload.disclosed_quantity = openalgo.internal.pyStr(a.disclosed_quantity);
payload.trigger_price = openalgo.internal.pyStr(a.trigger_price);
payload = openalgo.internal.addKwargs(payload, kw, true);

result = obj.makeRequest('modifyorder', payload);
end
