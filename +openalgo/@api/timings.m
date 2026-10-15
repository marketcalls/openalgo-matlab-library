function result = timings(obj, varargin)
%TIMINGS Get market timings for a specific date.
%   RESULT = CLIENT.TIMINGS() returns the timings of today.
%   RESULT = CLIENT.TIMINGS(DATE) or CLIENT.TIMINGS(date=DATE)
%
%   Parameters:
%     date - Date in YYYY-MM-DD format. Optional; defaults to the current
%            local date. Positional or name=value. No other arguments are
%            accepted.
%
%   Payload: apikey, date. The request goes to the market/timings
%   endpoint.
%
%   Returns a struct with status and data, one entry per open exchange
%   with exchange, start_time and end_time (epoch milliseconds). An empty
%   data list means the market is closed (holiday).
%
%   Example:
%     t = client.timings("2025-01-15");
%
%   See also openalgo.api/holidays.

a = openalgo.internal.parseArgs('timings', varargin, {'date', []}, {}, 1, false);

date = a.date;
if openalgo.internal.isNone(date)
    date = char(datetime('now', 'Format', 'yyyy-MM-dd'));
end

payload = struct();
payload.apikey = obj.api_key;
payload.date = date;

result = obj.makeRequest('market/timings', payload);
end
