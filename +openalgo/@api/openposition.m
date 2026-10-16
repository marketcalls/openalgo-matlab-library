function result = openposition(obj, varargin)
%OPENPOSITION Get the current open position for a specific symbol.
%   RESULT = CLIENT.OPENPOSITION(Name=Value)
%
%   Parameters:
%     strategy - The trading strategy name. Default "MATLAB".
%     symbol   - Trading symbol. Required.
%     exchange - Exchange code. Required.
%     product  - Product type. Required.
%     Other name=value pairs are sent as extra fields, as text.
%
%   Payload: apikey, strategy, symbol, exchange, product, then the extra
%   fields.
%
%   Returns a struct with quantity and status.
%
%   Example:
%     resp = client.openposition(strategy="Test Strategy", symbol="YESBANK", ...
%         exchange="NSE", product="CNC");
%
%   See also openalgo.api/positionbook.

[a, kw] = openalgo.internal.parseArgs('openposition', varargin, ...
    {'strategy', 'MATLAB'; 'symbol', []; 'exchange', []; 'product', []}, ...
    {'symbol', 'exchange', 'product'}, 0, true);

payload = struct();
payload.apikey = obj.api_key;
payload.strategy = a.strategy;
payload.symbol = a.symbol;
payload.exchange = a.exchange;
payload.product = a.product;
payload = openalgo.internal.addKwargs(payload, kw, true);

result = obj.makeRequest('openposition', payload);
end
