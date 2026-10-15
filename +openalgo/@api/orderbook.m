function result = orderbook(obj, varargin)
%ORDERBOOK Get orderbook details from the broker with basic orderbook statistics.
%   RESULT = CLIENT.ORDERBOOK()
%
%   Parameters:
%     Any name=value pair is sent as an extra field, as is.
%
%   Payload: apikey, then the extra fields.
%
%   Returns a struct with status and data, which holds orders (one entry
%   per order with action, exchange, order_status, orderid, price,
%   pricetype, product, quantity, symbol, timestamp, trigger_price) and
%   statistics (total_buy_orders, total_completed_orders,
%   total_open_orders, total_rejected_orders, total_sell_orders).
%
%   Example:
%     ob = client.orderbook();
%
%   See also openalgo.api/orderstatus, openalgo.api/tradebook.

[~, kw] = openalgo.internal.parseArgs('orderbook', varargin, {}, {}, 0, true);

payload = struct();
payload.apikey = obj.api_key;
payload = openalgo.internal.addKwargs(payload, kw, false);

result = obj.makeRequest('orderbook', payload);
end
