function result = symbol(obj, varargin)
%SYMBOL Get symbol details from the API.
%   RESULT = CLIENT.SYMBOL(symbol=SYMBOL, exchange=EXCHANGE)
%
%   Parameters:
%     symbol   - Trading symbol. Required.
%     exchange - Exchange code. Required.
%     Other name=value pairs are sent as extra fields, as is.
%
%   Payload: apikey, symbol, exchange, then the extra fields.
%
%   Returns a struct with status and data (token, lot size, tick size and
%   other symbol details).
%
%   Example:
%     s = client.symbol(symbol="NIFTY30DEC25FUT", exchange="NFO");
%
%   See also openalgo.api/search, openalgo.api/instruments.

[a, kw] = openalgo.internal.parseArgs('symbol', varargin, ...
    {'symbol', []; 'exchange', []}, {'symbol', 'exchange'}, 0, true);

payload = struct();
payload.apikey = obj.api_key;
payload.symbol = a.symbol;
payload.exchange = a.exchange;
payload = openalgo.internal.addKwargs(payload, kw, false);

result = obj.makeRequest('symbol', payload);
end
