function result = optionsymbol(obj, varargin)
%OPTIONSYMBOL Return option symbol details from underlying and offset.
%   RESULT = CLIENT.OPTIONSYMBOL(Name=Value)
%
%   Gets the exact option symbol, lot size and tick size without placing
%   an order. Useful to verify that a symbol exists before ordering, to
%   get the lot size for quantity calculations, to build option strategies
%   and to get the current ATM strike.
%
%   Parameters:
%     strategy    - Deprecated, will be removed in future versions.
%                   Strategy name. Default [] (not sent). Sent with a
%                   warning (openalgo:deprecated) when given.
%     underlying  - Underlying symbol (e.g. NIFTY, BANKNIFTY,
%                   NIFTY28OCT25FUT). Required.
%     exchange    - Exchange code (NSE_INDEX, NSE, NFO, BSE_INDEX, BSE,
%                   BFO). Required.
%     strike_int  - Deprecated, will be removed in future versions. Strike
%                   interval. Sent as text when given, with a warning.
%     offset      - Strike offset (ATM, ITM1 to ITM50, OTM1 to OTM50).
%                   Required.
%     option_type - "CE" for call or "PE" for put. Required.
%     expiry_date - Expiry date in DDMMMYY format (e.g. 28OCT25). Optional
%                   when the underlying includes the expiry.
%     Other name=value pairs are sent as extra fields, as text.
%
%   Payload: apikey, underlying, exchange, offset, option_type, strategy
%   (when given), strike_int (as text, when given), expiry_date (when
%   given), then the extra fields.
%
%   Returns a struct with status, symbol (the resolved option symbol),
%   exchange, lotsize, tick_size and underlying_ltp.
%
%   Examples:
%     s = client.optionsymbol(underlying="NIFTY", exchange="NSE_INDEX", ...
%         expiry_date="28OCT25", offset="ATM", option_type="CE");
%     fprintf("Symbol: %s, lot size: %d\n", s.symbol, s.lotsize);
%
%     % Using a future as the underlying
%     s = client.optionsymbol(underlying="NIFTY28OCT25FUT", exchange="NFO", ...
%         offset="ITM2", option_type="CE");
%
%   See also openalgo.api/optionsorder, openalgo.api/optionchain.

[a, kw] = openalgo.internal.parseArgs('optionsymbol', varargin, ...
    {'strategy', []; 'underlying', []; 'exchange', []; 'strike_int', []; ...
     'offset', []; 'option_type', []; 'expiry_date', []}, ...
    {'underlying', 'exchange', 'offset', 'option_type'}, 0, true);

if ~openalgo.internal.isNone(a.strategy)
    warning('openalgo:deprecated', ...
        'The ''strategy'' parameter is deprecated and will be removed in future versions.');
end
if ~openalgo.internal.isNone(a.strike_int)
    warning('openalgo:deprecated', ...
        'The ''strike_int'' parameter is deprecated and will be removed in future versions.');
end

payload = struct();
payload.apikey = obj.api_key;
payload.underlying = a.underlying;
payload.exchange = a.exchange;
payload.offset = a.offset;
payload.option_type = a.option_type;
if ~openalgo.internal.isNone(a.strategy)
    payload.strategy = a.strategy;
end
if ~openalgo.internal.isNone(a.strike_int)
    payload.strike_int = openalgo.internal.pyStr(a.strike_int);
end
if ~openalgo.internal.isNone(a.expiry_date)
    payload.expiry_date = a.expiry_date;
end
payload = openalgo.internal.addKwargs(payload, kw, true);

result = obj.makeRequest('optionsymbol', payload);
end
