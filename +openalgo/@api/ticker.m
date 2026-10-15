function result = ticker(obj, varargin)
%TICKER Get historical candles from the ticker-compatible endpoint.
%   RESULT = CLIENT.TICKER(symbol=S, exchange=X, interval="D", start_date=D1, end_date=D2, format="json")
%
%   Addition: not present in the Python SDK. It covers the documented
%   GET /api/v1/ticker/<EXCHANGE>:<SYMBOL> endpoint.
%
%   The request is a GET to ticker/<EXCHANGE>:<SYMBOL> with the query
%   parameters apikey, interval, from, to and format. The EXCHANGE:SYMBOL
%   path segment is percent-encoded by matlab.net.URI where needed; the
%   colon and characters such as & are legal in a path segment and go out
%   as is (the server decodes both forms the same way). The endpoint always
%   reads the broker API; use history with source="db" for data from the
%   OpenAlgo historical database. The server limits the date range by
%   interval (10 years for D, W and M, 30 days otherwise) and moves the
%   start date forward when it is too early.
%
%   Parameters:
%     symbol     - Trading symbol. Required.
%     exchange   - Exchange code. Required.
%     interval   - Interval, e.g. "1m", "5m", "15m", "30m", "1h", "D".
%                  Default "D".
%     start_date - Start date, 'YYYY-MM-DD'. Required. Sent as from.
%     end_date   - End date, 'YYYY-MM-DD'. Required. Sent as to.
%     format     - "json" (default) or "txt".
%     Other name=value pairs (for example adjusted or sort) are sent as
%     extra query parameters.
%
%   Returns:
%     format "json": the decoded JSON as a struct, with status and data
%       (one entry per candle with timestamp in epoch seconds, open,
%       high, low, close and volume), or an error struct as for every
%       other method.
%     format "txt": the response body as a character vector of
%       comma-separated rows (Ticker,Date,Open,High,Low,Close,Volume; the
%       intraday rows also carry the time after the date). A non-200
%       answer gives an http_error struct 'HTTP <code>: <body>' with code.
%
%   Examples:
%     r = client.ticker(symbol="RELIANCE", exchange="NSE", interval="D", ...
%         start_date="2026-07-01", end_date="2026-07-10");
%     txt = client.ticker(symbol="RELIANCE", exchange="NSE", interval="5m", ...
%         start_date="2026-07-01", end_date="2026-07-02", format="txt");
%
%   See also openalgo.api/history.

[a, kw] = openalgo.internal.parseArgs('ticker', varargin, ...
    {'symbol', []; 'exchange', []; 'interval', 'D'; 'start_date', []; ...
     'end_date', []; 'format', 'json'}, ...
    {'symbol', 'exchange', 'start_date', 'end_date'}, 0, true);

segment = [openalgo.internal.pyStr(a.exchange) ':' openalgo.internal.pyStr(a.symbol)];

params = struct();
params.apikey = obj.api_key;
params.interval = a.interval;
params.from = a.start_date;
params.to = a.end_date;
params.format = a.format;
params = openalgo.internal.addKwargs(params, kw, false);

[code, text, err] = obj.getRequestRaw('ticker', params, segment);
if ~isempty(err)
    result = err;
    return
end

isText = (ischar(a.format) || (isstring(a.format) && isscalar(a.format))) && ...
    strcmpi(char(a.format), 'txt');
if isText
    if code ~= 200
        result = openalgo.internal.errorResult(sprintf('HTTP %d: %s', code, text), ...
            'http_error', 'code', code);
    else
        result = text;
    end
    return
end
result = openalgo.internal.handleResponse(code, text);
end
