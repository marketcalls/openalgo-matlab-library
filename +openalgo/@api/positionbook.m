function result = positionbook(obj, varargin)
%POSITIONBOOK Get positionbook details from the broker.
%   RESULT = CLIENT.POSITIONBOOK()
%
%   Parameters:
%     Any name=value pair is sent as an extra field, as is.
%
%   Payload: apikey, then the extra fields.
%
%   Returns a struct with status and data, one entry per position with
%   average_price, exchange, product, quantity and symbol.
%
%   Example:
%     pb = client.positionbook();
%
%   See also openalgo.api/openposition, openalgo.api/closeposition.

[~, kw] = openalgo.internal.parseArgs('positionbook', varargin, {}, {}, 0, true);

payload = struct();
payload.apikey = obj.api_key;
payload = openalgo.internal.addKwargs(payload, kw, false);

result = obj.makeRequest('positionbook', payload);
end
