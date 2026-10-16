function result = multioptiongreeks(obj, varargin)
%MULTIOPTIONGREEKS Calculate option Greeks for up to 50 symbols in one request.
%   RESULT = CLIENT.MULTIOPTIONGREEKS(symbols=SYMBOLS, interest_rate=R, expiry_time=T)
%
%   It covers the documented
%   POST /api/v1/multioptiongreeks endpoint.
%
%   Calculates Black-76 Greeks and implied volatility for 1 to 50 option
%   symbols. The server batches the option quotes, reuses underlying
%   quotes and uses a per-expiry synthetic forward when available, with
%   spot as the fallback.
%
%   Parameters:
%     symbols       - 1 to 50 option requests, a cell array of structs or a
%                     struct array. Required. Always sent as a JSON array.
%                     Each item has symbol and exchange (NFO, BFO, CDS, MCX
%                     or CRYPTO), and optionally underlying_symbol and
%                     underlying_exchange.
%     interest_rate - Common annualized rate, 0 to 100 percent. Optional.
%     expiry_time   - Common expiry time in HH:MM form. Optional.
%     Other name=value pairs are sent as extra fields, as is.
%
%   Optional parameters left at [] are not sent. Payload: apikey,
%   symbols, interest_rate and expiry_time (when given), then the extra
%   fields.
%
%   The symbol count is checked before sending; a bad list is reported as
%   a struct with error_type 'validation_error':
%     'Symbols must be an array'
%     'Symbols array cannot be empty'
%     'Maximum 50 symbols allowed'
%
%   Returns a struct with status, data (one entry per symbol with status,
%   symbol, exchange, implied_volatility and greeks) and summary (total,
%   success, failed). Individual items can fail while the batch succeeds,
%   so inspect every item and the summary.
%
%   Example:
%     syms = {struct("symbol","NIFTY25AUG2625000CE","exchange","NFO"), ...
%             struct("symbol","NIFTY25AUG2625000PE","exchange","NFO")};
%     r = client.multioptiongreeks(symbols=syms, interest_rate=7.0, expiry_time="15:30");
%
%   See also openalgo.api/optiongreeks, openalgo.api/optionchain.

[a, kw] = openalgo.internal.parseArgs('multioptiongreeks', varargin, ...
    {'symbols', []; 'interest_rate', []; 'expiry_time', []}, {'symbols'}, 0, true);

[symbols, isList] = openalgo.internal.toList(a.symbols);
if ~isList || ~(iscell(a.symbols) || isstruct(a.symbols))
    result = openalgo.internal.errorResult('Symbols must be an array', 'validation_error');
    return
end
if isempty(symbols)
    result = openalgo.internal.errorResult('Symbols array cannot be empty', 'validation_error');
    return
end
if numel(symbols) > 50
    result = openalgo.internal.errorResult('Maximum 50 symbols allowed', 'validation_error');
    return
end

payload = struct();
payload.apikey = obj.api_key;
payload.symbols = symbols;
if ~openalgo.internal.isNone(a.interest_rate)
    payload.interest_rate = a.interest_rate;
end
if ~openalgo.internal.isNone(a.expiry_time)
    payload.expiry_time = a.expiry_time;
end
payload = openalgo.internal.addKwargs(payload, kw, false);

result = obj.makeRequest('multioptiongreeks', payload);
end
