function result = multiquotes(obj, varargin)
%MULTIQUOTES Get real-time quotes for multiple symbols in a single request.
%   RESULT = CLIENT.MULTIQUOTES(symbols=SYMBOLS)
%
%   Parameters:
%     symbols - List of symbol-exchange pairs, a cell array of structs or
%               a struct array, each with fields symbol and exchange.
%               Required. Always sent as a JSON array.
%     Other name=value pairs are sent as extra fields, as is.
%
%   Payload: apikey, symbols, then the extra fields.
%
%   Returns a struct with status "success" and the quote data for each
%   symbol, or a struct with status "error" and a message.
%
%   Examples:
%     % Quotes for several NSE stocks
%     r = client.multiquotes(symbols={ ...
%         struct("symbol","RELIANCE","exchange","NSE"), ...
%         struct("symbol","TCS","exchange","NSE"), ...
%         struct("symbol","INFY","exchange","NSE")});
%
%     % Across exchanges, as a struct array
%     syms = struct("symbol", {"RELIANCE","NIFTY","GOLD"}, ...
%                   "exchange", {"NSE","NSE_INDEX","MCX"});
%     r = client.multiquotes(symbols=syms);
%
%   See also openalgo.api/quotes.

[a, kw] = openalgo.internal.parseArgs('multiquotes', varargin, ...
    {'symbols', []}, {'symbols'}, 0, true);

symbols = a.symbols;
[list, isList] = openalgo.internal.toList(symbols);
if isList
    symbols = list;
end

payload = struct();
payload.apikey = obj.api_key;
payload.symbols = symbols;
payload = openalgo.internal.addKwargs(payload, kw, false);

result = obj.makeRequest('multiquotes', payload);
end
