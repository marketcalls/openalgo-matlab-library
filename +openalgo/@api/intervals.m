function result = intervals(obj, varargin)
%INTERVALS Get supported time intervals for historical data from the API.
%   RESULT = CLIENT.INTERVALS()
%
%   Parameters:
%     Any name=value pair is sent as an extra field, as is.
%
%   Payload: apikey, then the extra fields.
%
%   Returns a struct with status and data, the supported intervals grouped
%   by type (seconds, minutes, hours, days, weeks, months).
%
%   Example:
%     iv = client.intervals();
%     iv.data.minutes
%
%   See also openalgo.api/history, openalgo.api/interval.

[~, kw] = openalgo.internal.parseArgs('intervals', varargin, {}, {}, 0, true);

payload = struct();
payload.apikey = obj.api_key;
payload = openalgo.internal.addKwargs(payload, kw, false);

result = obj.makeRequest('intervals', payload);
end
