function result = cancelorder(obj, varargin)
%CANCELORDER Cancel an existing order.
%   RESULT = CLIENT.CANCELORDER(order_id=ID, strategy="MATLAB")
%
%   Parameters:
%     order_id - The ID of the order to cancel. Required.
%     strategy - The trading strategy name. Default "MATLAB".
%     Other name=value pairs are sent as extra fields, as text.
%
%   Payload: apikey, orderid, strategy, then the extra fields.
%
%   Returns the JSON response as a struct.
%
%   Example:
%     resp = client.cancelorder(order_id="24120900146469", strategy="Test Strategy");
%
%   See also openalgo.api/cancelallorder, openalgo.api/modifyorder.

[a, kw] = openalgo.internal.parseArgs('cancelorder', varargin, ...
    {'order_id', []; 'strategy', 'MATLAB'}, {'order_id'}, 0, true);

payload = struct();
payload.apikey = obj.api_key;
payload.orderid = a.order_id;
payload.strategy = a.strategy;
payload = openalgo.internal.addKwargs(payload, kw, true);

result = obj.makeRequest('cancelorder', payload);
end
