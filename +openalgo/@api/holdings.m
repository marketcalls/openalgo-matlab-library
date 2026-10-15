function result = holdings(obj, varargin)
%HOLDINGS Get stock holdings details from the broker.
%   RESULT = CLIENT.HOLDINGS()
%
%   Parameters:
%     Any name=value pair is sent as an extra field, as is.
%
%   Payload: apikey, then the extra fields.
%
%   Returns a struct with status and data, which holds holdings (one
%   entry per holding with exchange, pnl, pnlpercent, product, quantity,
%   symbol) and statistics (totalholdingvalue, totalinvvalue,
%   totalpnlpercentage, totalprofitandloss).
%
%   Example:
%     h = client.holdings();
%
%   See also openalgo.api/positionbook, openalgo.api/funds.

[~, kw] = openalgo.internal.parseArgs('holdings', varargin, {}, {}, 0, true);

payload = struct();
payload.apikey = obj.api_key;
payload = openalgo.internal.addKwargs(payload, kw, false);

result = obj.makeRequest('holdings', payload);
end
