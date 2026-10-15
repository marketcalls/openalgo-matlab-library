function result = basketorder(obj, varargin)
%BASKETORDER Place multiple orders simultaneously.
%   RESULT = CLIENT.BASKETORDER(orders=ORDERS, strategy="Python")
%
%   Parameters:
%     strategy - The trading strategy name. Default "Python".
%     orders   - List of orders, a cell array of structs or a struct
%                array. Required. Each order has:
%                  symbol    - Trading symbol. Required.
%                  exchange  - Exchange code. Required.
%                  action    - "BUY" or "SELL". Required.
%                  quantity  - Quantity to trade. Required.
%                  pricetype - Type of price. Optional ("MARKET").
%                  product   - Product type. Optional ("MIS").
%                  price, trigger_price, disclosed_quantity - Optional.
%                Numeric and logical scalar values inside an order are sent
%                as text (Python str()); everything else as is.
%     Other name=value pairs are sent as extra fields, as text.
%
%   Payload: apikey, strategy, orders (always a JSON array), then the
%   extra fields.
%
%   Returns a struct with status and results, one entry (orderid, status,
%   symbol) per order.
%
%   Example:
%     orders = {struct("symbol","BHEL","exchange","NSE","action","BUY", ...
%                      "quantity",1,"pricetype","MARKET","product","MIS"), ...
%               struct("symbol","ZOMATO","exchange","NSE","action","SELL", ...
%                      "quantity",1,"pricetype","MARKET","product","MIS")};
%     resp = client.basketorder(orders=orders);
%
%   See also openalgo.api/placeorder, openalgo.api/splitorder.

[a, kw] = openalgo.internal.parseArgs('basketorder', varargin, ...
    {'strategy', 'Python'; 'orders', []}, {'orders'}, 0, true);

[orders, isList] = openalgo.internal.toList(a.orders);
if ~isList
    error('openalgo:typeError', 'orders must be a list (cell array or struct array), got %s', class(a.orders));
end
processed = cell(1, numel(orders));
for i = 1:numel(orders)
    order = orders{i};
    if ~isstruct(order)
        error('openalgo:typeError', 'Each order must be a struct (dict), got %s', class(order));
    end
    p = struct();
    f = fieldnames(order);
    for j = 1:numel(f)
        value = order.(f{j});
        if (isnumeric(value) || islogical(value)) && isscalar(value)
            value = openalgo.internal.pyStr(value);
        end
        p.(f{j}) = value;
    end
    processed{i} = p;
end

payload = struct();
payload.apikey = obj.api_key;
payload.strategy = a.strategy;
payload.orders = processed;
payload = openalgo.internal.addKwargs(payload, kw, true);

result = obj.makeRequest('basketorder', payload);
end
