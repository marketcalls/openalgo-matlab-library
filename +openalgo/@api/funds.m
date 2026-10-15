function result = funds(obj, varargin)
%FUNDS Get funds and margin details of the connected trading account.
%   RESULT = CLIENT.FUNDS()
%
%   Parameters:
%     Any name=value pair is sent as an extra field, as is.
%
%   Payload: apikey, then the extra fields.
%
%   Returns a struct with status and data (availablecash, collateral,
%   m2mrealized, m2munrealized, utiliseddebits).
%
%   Example:
%     f = client.funds();
%     cash = f.data.availablecash;
%
%   See also openalgo.api/margin, openalgo.api/holdings.

[~, kw] = openalgo.internal.parseArgs('funds', varargin, {}, {}, 0, true);

payload = struct();
payload.apikey = obj.api_key;
payload = openalgo.internal.addKwargs(payload, kw, false);

result = obj.makeRequest('funds', payload);
end
