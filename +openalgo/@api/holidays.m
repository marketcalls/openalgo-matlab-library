function result = holidays(obj, varargin)
%HOLIDAYS Get market holidays for a specific year.
%   RESULT = CLIENT.HOLIDAYS() returns the holidays of the current year.
%   RESULT = CLIENT.HOLIDAYS(YEAR) or CLIENT.HOLIDAYS(year=YEAR)
%
%   Parameters:
%     year - Year for the holiday data (2020 to 2050). Optional; the
%            server uses the current year when it is not given. Sent as
%            is. Positional or name=value. No other arguments are
%            accepted.
%
%   Payload: apikey, year (when given). The request goes to the
%   market/holidays endpoint.
%
%   Returns a struct with status, year, timezone ("Asia/Kolkata") and
%   data, one entry per holiday with date, description, holiday_type,
%   closed_exchanges and open_exchanges (exchange, start_time, end_time in
%   epoch milliseconds).
%
%   Example:
%     h = client.holidays(2025);
%
%   See also openalgo.api/timings.

a = openalgo.internal.parseArgs('holidays', varargin, {'year', []}, {}, 1, false);

payload = struct();
payload.apikey = obj.api_key;
if ~openalgo.internal.isNone(a.year)
    payload.year = a.year;
end

result = obj.makeRequest('market/holidays', payload);
end
