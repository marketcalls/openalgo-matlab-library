function result = optionsorder(obj, varargin)
%OPTIONSORDER Place an option order, resolving the symbol from underlying and offset.
%   RESULT = CLIENT.OPTIONSORDER(Name=Value)
%
%   Parameters:
%     strategy    - Strategy name. Default "Python".
%     underlying  - Underlying symbol (e.g. NIFTY, BANKNIFTY,
%                   NIFTY28OCT25FUT). Required.
%     exchange    - Exchange code (NSE_INDEX, NSE, NFO, BSE_INDEX, BSE,
%                   BFO). Required.
%     strike_int  - Deprecated, will be removed in future versions. Strike
%                   interval. Sent as text when given, with a warning
%                   (openalgo:deprecated).
%     offset      - Strike offset (ATM, ITM1 to ITM50, OTM1 to OTM50).
%                   Required.
%     option_type - "CE" for call or "PE" for put. Required.
%     action      - "BUY" or "SELL". Required.
%     quantity    - Quantity (a multiple of the lot size). Required.
%     expiry_date - Expiry date in DDMMMYY format (e.g. 28OCT25). Optional
%                   when the underlying includes the expiry.
%     price_type  - MARKET, LIMIT, SL or SL-M. Default "MARKET".
%     product     - MIS or NRML (options do not support CNC).
%                   Default "MIS".
%     Other name=value pairs are sent as extra fields, as text, for example
%     price (LIMIT orders), trigger_price (SL and SL-M orders) and
%     disclosed_quantity.
%
%   Payload: apikey, strategy, underlying, exchange, offset, option_type,
%   action, quantity (as text), pricetype, product, strike_int (as text,
%   when given), expiry_date (when given), then the extra fields.
%
%   Returns a struct with status, orderid, symbol (the resolved option
%   symbol), exchange, underlying, underlying_ltp, offset, option_type and,
%   in analyze mode, mode.
%
%   Examples:
%     r = client.optionsorder(strategy="test_strategy", underlying="NIFTY", ...
%         exchange="NSE_INDEX", expiry_date="28NOV24", offset="ATM", ...
%         option_type="CE", action="BUY", quantity=75);
%
%     % LIMIT order
%     r = client.optionsorder(strategy="nifty_scalping", underlying="NIFTY", ...
%         exchange="NSE_INDEX", expiry_date="28NOV24", offset="OTM1", ...
%         option_type="CE", action="BUY", quantity=75, price_type="LIMIT", ...
%         price="50.0");
%
%   See also openalgo.api/optionsmultiorder, openalgo.api/optionsymbol.

[a, kw] = openalgo.internal.parseArgs('optionsorder', varargin, ...
    {'strategy', 'Python'; 'underlying', []; 'exchange', []; 'strike_int', []; ...
     'offset', []; 'option_type', []; 'action', []; 'quantity', []; ...
     'expiry_date', []; 'price_type', 'MARKET'; 'product', 'MIS'}, ...
    {'underlying', 'exchange', 'offset', 'option_type', 'action', 'quantity'}, 0, true);

if ~openalgo.internal.isNone(a.strike_int)
    warning('openalgo:deprecated', ...
        'The ''strike_int'' parameter is deprecated and will be removed in future versions.');
end

payload = struct();
payload.apikey = obj.api_key;
payload.strategy = a.strategy;
payload.underlying = a.underlying;
payload.exchange = a.exchange;
payload.offset = a.offset;
payload.option_type = a.option_type;
payload.action = a.action;
payload.quantity = openalgo.internal.pyStr(a.quantity);
payload.pricetype = a.price_type;
payload.product = a.product;
if ~openalgo.internal.isNone(a.strike_int)
    payload.strike_int = openalgo.internal.pyStr(a.strike_int);
end
if ~openalgo.internal.isNone(a.expiry_date)
    payload.expiry_date = a.expiry_date;
end
payload = openalgo.internal.addKwargs(payload, kw, true);

result = obj.makeRequest('optionsorder', payload);
end
