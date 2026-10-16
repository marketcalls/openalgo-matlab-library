function result = cancelallorder(obj, varargin)
%CANCELALLORDER Cancel all orders for a given strategy.
%   RESULT = CLIENT.CANCELALLORDER(strategy="MATLAB")
%
%   Parameters:
%     strategy - The trading strategy name. Default "MATLAB".
%     Other name=value pairs are sent as extra fields, as text.
%
%   Payload: apikey, strategy, then the extra fields.
%
%   Returns the JSON response as a struct.
%
%   Example:
%     resp = client.cancelallorder(strategy="Test Strategy");
%
%   See also openalgo.api/cancelorder, openalgo.api/closeposition.

[a, kw] = openalgo.internal.parseArgs('cancelallorder', varargin, ...
    {'strategy', 'MATLAB'}, {}, 0, true);

payload = struct();
payload.apikey = obj.api_key;
payload.strategy = a.strategy;
payload = openalgo.internal.addKwargs(payload, kw, true);

result = obj.makeRequest('cancelallorder', payload);
end
