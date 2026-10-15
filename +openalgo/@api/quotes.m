function result = quotes(obj, varargin)
%QUOTES Get real-time quotes for a symbol.
%   RESULT = CLIENT.QUOTES(symbol=SYMBOL, exchange=EXCHANGE)
%
%   Parameters:
%     symbol   - Trading symbol. Required.
%     exchange - Exchange code. Required.
%     Other name=value pairs are sent as extra fields, as is.
%
%   Payload: apikey, symbol, exchange, then the extra fields.
%
%   Returns a struct with status and data (bid, ask, open, high, low, ltp,
%   prev_close, volume, oi and so on).
%
%   Example:
%     q = client.quotes(symbol="SBIN", exchange="NSE");
%     ltp = q.data.ltp;
%
%   See also openalgo.api/multiquotes, openalgo.api/depth.

[a, kw] = openalgo.internal.parseArgs('quotes', varargin, ...
    {'symbol', []; 'exchange', []}, {'symbol', 'exchange'}, 0, true);

payload = struct();
payload.apikey = obj.api_key;
payload.symbol = a.symbol;
payload.exchange = a.exchange;
payload = openalgo.internal.addKwargs(payload, kw, false);

result = obj.makeRequest('quotes', payload);
end
