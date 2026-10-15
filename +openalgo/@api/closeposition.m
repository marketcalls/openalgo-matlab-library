function result = closeposition(obj, varargin)
%CLOSEPOSITION Close all open positions for a given strategy.
%   RESULT = CLIENT.CLOSEPOSITION(strategy="Python")
%
%   Parameters:
%     strategy - The trading strategy name. Default "Python".
%     Other name=value pairs are sent as extra fields, as text.
%
%   Payload: apikey, strategy, then the extra fields.
%
%   Returns the JSON response as a struct.
%
%   Example:
%     resp = client.closeposition(strategy="Test Strategy");
%
%   See also openalgo.api/cancelallorder, openalgo.api/positionbook.

[a, kw] = openalgo.internal.parseArgs('closeposition', varargin, ...
    {'strategy', 'Python'}, {}, 0, true);

payload = struct();
payload.apikey = obj.api_key;
payload.strategy = a.strategy;
payload = openalgo.internal.addKwargs(payload, kw, true);

result = obj.makeRequest('closeposition', payload);
end
