function result = tradebook(obj, varargin)
%TRADEBOOK Get tradebook details from the broker.
%   RESULT = CLIENT.TRADEBOOK()
%
%   Parameters:
%     Any name=value pair is sent as an extra field, as is.
%
%   Payload: apikey, then the extra fields.
%
%   Returns a struct with status and data, one entry per trade with
%   action, average_price, exchange, orderid, product, quantity, symbol,
%   timestamp and trade_value.
%
%   Example:
%     tb = client.tradebook();
%
%   See also openalgo.api/orderbook, openalgo.api/positionbook.

[~, kw] = openalgo.internal.parseArgs('tradebook', varargin, {}, {}, 0, true);

payload = struct();
payload.apikey = obj.api_key;
payload = openalgo.internal.addKwargs(payload, kw, false);

result = obj.makeRequest('tradebook', payload);
end
