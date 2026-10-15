function result = depth(obj, varargin)
%DEPTH Get market depth (order book) for a symbol.
%   RESULT = CLIENT.DEPTH(symbol=SYMBOL, exchange=EXCHANGE)
%
%   Parameters:
%     symbol   - Trading symbol. Required.
%     exchange - Exchange code. Required.
%     Other name=value pairs are sent as extra fields, as is.
%
%   Payload: apikey, symbol, exchange, then the extra fields.
%
%   Returns a struct with status and data, including the top 5 bids and
%   asks.
%
%   Example:
%     d = client.depth(symbol="SBIN", exchange="NSE");
%
%   See also openalgo.api/quotes.

[a, kw] = openalgo.internal.parseArgs('depth', varargin, ...
    {'symbol', []; 'exchange', []}, {'symbol', 'exchange'}, 0, true);

payload = struct();
payload.apikey = obj.api_key;
payload.symbol = a.symbol;
payload.exchange = a.exchange;
payload = openalgo.internal.addKwargs(payload, kw, false);

result = obj.makeRequest('depth', payload);
end
