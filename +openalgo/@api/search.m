function result = search(obj, varargin)
%SEARCH Search for symbols across exchanges.
%   RESULT = CLIENT.SEARCH(query=QUERY, exchange=EXCHANGE)
%
%   Parameters:
%     query    - Search query for symbol. Required.
%     exchange - Exchange filter. Optional; sent only when non-empty.
%                Supported exchanges: NSE, NFO, BSE, BFO, MCX, CDS, BCD,
%                NCDEX, NSE_INDEX, BSE_INDEX, MCX_INDEX.
%     Other name=value pairs are sent as extra fields, as is.
%
%   Payload: apikey, query, exchange (when given), then the extra fields.
%
%   Returns a struct with status and data, the matching symbols with
%   symbol, name, exchange, token, instrumenttype, lotsize, strike and
%   expiry.
%
%   Example:
%     r = client.search(query="NIFTY 26000 DEC CE", exchange="NFO");
%
%   See also openalgo.api/symbol, openalgo.api/instruments.

[a, kw] = openalgo.internal.parseArgs('search', varargin, ...
    {'query', []; 'exchange', []}, {'query'}, 0, true);

payload = struct();
payload.apikey = obj.api_key;
payload.query = a.query;
if openalgo.internal.truthy(a.exchange)
    payload.exchange = a.exchange;
end
payload = openalgo.internal.addKwargs(payload, kw, false);

result = obj.makeRequest('search', payload);
end
