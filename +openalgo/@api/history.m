function result = history(obj, varargin)
%HISTORY Get historical data for a symbol as a timetable.
%   TT = CLIENT.HISTORY(symbol=S, exchange=X, interval=I, start_date=D1, end_date=D2)
%
%   Parameters:
%     symbol     - Trading symbol. Required.
%     exchange   - Exchange code. Required.
%     interval   - Time interval for the data, e.g. "1m", "5m", "1h", "D".
%                  Required. Use intervals() to get the supported values.
%     start_date - Start date in format 'YYYY-MM-DD'. Required.
%     end_date   - End date in format 'YYYY-MM-DD'. Required.
%     source     - Data source. "api" (default) fetches from the broker
%                  API; "db" fetches from the OpenAlgo historical
%                  database, which stores 1m and D intervals physically
%                  and computes all other intervals on the fly. Custom
%                  intraday intervals (2m, 3m, 4m, 6m, 7m, 2h, 3h, 4h and
%                  so on) and daily-based intervals (W, M, Q, Y and
%                  multiples such as 2W or 3M) are only available with
%                  source="db".
%     Other name=value pairs are sent as extra fields, as is.
%
%   Payload: apikey, symbol, exchange, interval, start_date, end_date,
%   source, then the extra fields.
%
%   Returns a timetable on success (the MATLAB counterpart of the pandas
%   DataFrame of the Python SDK). The row times (named timestamp) come
%   from the epoch seconds in the response: in the Asia/Kolkata time zone
%   for intraday intervals, and without a time zone for "D", "W" and "M"
%   (clock time as returned, like the Python SDK). Rows are
%   sorted by time and duplicate timestamps are removed, keeping the
%   first. The other columns (open, high, low, close, volume, oi, ...)
%   keep their names.
%
%   On failure returns the error struct of the request, or:
%     error_type 'no_data'          'No data available for the specified period'
%     error_type 'processing_error' 'Failed to process historical data: ...'
%                                   (with raw_data holding the data list)
%
%   Example:
%     tt = client.history(symbol="SBIN", exchange="NSE", interval="5m", ...
%         start_date="2025-01-01", end_date="2025-01-10");
%     if istimetable(tt)
%         plot(tt.timestamp, tt.close)
%     end
%
%   See also openalgo.api/intervals, timetable.

[a, kw] = openalgo.internal.parseArgs('history', varargin, ...
    {'symbol', []; 'exchange', []; 'interval', []; 'start_date', []; ...
     'end_date', []; 'source', 'api'}, ...
    {'symbol', 'exchange', 'interval', 'start_date', 'end_date'}, 0, true);

payload = struct();
payload.apikey = obj.api_key;
payload.symbol = a.symbol;
payload.exchange = a.exchange;
payload.interval = a.interval;
payload.start_date = a.start_date;
payload.end_date = a.end_date;
payload.source = a.source;
payload = openalgo.internal.addKwargs(payload, kw, false);

result = obj.makeRequest('history', payload);

if ~(isstruct(result) && isfield(result, 'status') && ...
        openalgo.internal.textEquals(result.status, 'success') && isfield(result, 'data'))
    return
end

data = result.data;
try
    T = openalgo.internal.recordsToTable(data);
    if height(T) == 0
        result = openalgo.internal.errorResult('No data available for the specified period', ...
            'no_data');
        return
    end
    if ~ismember('timestamp', T.Properties.VariableNames)
        error('openalgo:processingError', '''timestamp''');
    end

    ts = T.timestamp;
    if isstring(ts) || iscell(ts)
        ts = str2double(string(ts));
    end
    ts = double(ts(:));
    times = datetime(ts, 'ConvertFrom', 'posixtime', 'TimeZone', 'UTC');

    intervalText = '';
    if ischar(a.interval) || (isstring(a.interval) && isscalar(a.interval))
        intervalText = char(a.interval);
    end
    if ~any(strcmp(intervalText, {'D', 'W', 'M'}))
        times.TimeZone = 'Asia/Kolkata';
        times.Format = 'yyyy-MM-dd HH:mm:ssxxx';
    else
        % Daily, weekly and monthly bars carry no time zone, like the
        % zone-less pandas timestamps of the Python SDK.
        times.TimeZone = '';
        times.Format = 'yyyy-MM-dd HH:mm:ss';
    end

    T.timestamp = [];
    [~, order] = sort(ts);              % stable: equal times keep their order
    T = T(order, :);
    times = times(order);
    sortedTs = ts(order);
    keep = [true; diff(sortedTs) ~= 0];
    keep = keep & ~(isnan(sortedTs) & [false; isnan(sortedTs(1:end-1))]);
    T = T(keep, :);
    times = times(keep);

    result = table2timetable(T, 'RowTimes', times);
    result.Properties.DimensionNames{1} = 'timestamp';
catch ME
    result = openalgo.internal.errorResult( ...
        ['Failed to process historical data: ' ME.message], 'processing_error', ...
        'raw_data', data);
end
end
