function result = expiry(obj, varargin)
%EXPIRY Get expiry dates for a symbol.
%   RESULT = CLIENT.EXPIRY(symbol=SYMBOL, exchange=EXCHANGE, instrumenttype=TYPE)
%
%   Parameters:
%     symbol         - Trading symbol. Required.
%     exchange       - Exchange code. Required.
%     instrumenttype - Instrument type ("futures" or "options"). Required.
%     Other name=value pairs are sent as extra fields, as is.
%
%   Payload: apikey, symbol, exchange, instrumenttype, then the extra
%   fields.
%
%   Returns a struct with status and data, the expiry dates.
%
%   Example:
%     e = client.expiry(symbol="NIFTY", exchange="NFO", instrumenttype="options");
%
%   See also openalgo.api/optionchain, openalgo.api/syntheticfuture.

[a, kw] = openalgo.internal.parseArgs('expiry', varargin, ...
    {'symbol', []; 'exchange', []; 'instrumenttype', []}, ...
    {'symbol', 'exchange', 'instrumenttype'}, 0, true);

payload = struct();
payload.apikey = obj.api_key;
payload.symbol = a.symbol;
payload.exchange = a.exchange;
payload.instrumenttype = a.instrumenttype;
payload = openalgo.internal.addKwargs(payload, kw, false);

result = obj.makeRequest('expiry', payload);
end
