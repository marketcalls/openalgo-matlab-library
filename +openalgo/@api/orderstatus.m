function result = orderstatus(obj, varargin)
%ORDERSTATUS Get the current status of an order.
%   RESULT = CLIENT.ORDERSTATUS(order_id=ID, strategy="Python")
%
%   Parameters:
%     order_id - The ID of the order to check. Required.
%     strategy - The trading strategy name. Default "Python".
%     Other name=value pairs are sent as extra fields, as text.
%
%   Payload: apikey, strategy, orderid, then the extra fields.
%
%   Returns a struct with status and data (action, exchange, order_status,
%   orderid, price, pricetype, product, quantity, symbol, timestamp,
%   trigger_price).
%
%   Example:
%     resp = client.orderstatus(order_id="24120900146469", strategy="Test Strategy");
%
%   See also openalgo.api/orderbook, openalgo.api/placeorder.

[a, kw] = openalgo.internal.parseArgs('orderstatus', varargin, ...
    {'order_id', []; 'strategy', 'Python'}, {'order_id'}, 0, true);

payload = struct();
payload.apikey = obj.api_key;
payload.strategy = a.strategy;
payload.orderid = a.order_id;
payload = openalgo.internal.addKwargs(payload, kw, true);

result = obj.makeRequest('orderstatus', payload);
end
