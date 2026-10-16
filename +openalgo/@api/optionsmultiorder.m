function result = optionsmultiorder(obj, varargin)
%OPTIONSMULTIORDER Place several option legs on one underlying, resolving symbols by offset.
%   RESULT = CLIENT.OPTIONSMULTIORDER(strategy=S, underlying=U, exchange=X, legs=LEGS)
%
%   BUY legs are executed first for margin efficiency, then SELL legs.
%
%   Parameters:
%     strategy    - Strategy name. Required.
%     underlying  - Underlying symbol (e.g. NIFTY, BANKNIFTY,
%                   NIFTY28OCT25FUT). Required.
%     exchange    - Exchange code (NSE_INDEX, NSE, NFO, BSE_INDEX, BSE,
%                   BFO). Required.
%     legs        - 1 to 20 legs, a cell array of structs or a struct
%                   array. Required. Each leg has:
%                     offset             - ATM, ITM1 to ITM50, OTM1 to OTM50.
%                                          Required.
%                     option_type        - "CE" or "PE". Required.
%                     action             - "BUY" or "SELL". Required.
%                     quantity           - Multiple of the lot size.
%                                          Required. Sent as an integer.
%                     expiry_date        - Per-leg expiry (DDMMMYY) for
%                                          calendar and diagonal spreads.
%                                          Overrides the request expiry.
%                     pricetype          - MARKET, LIMIT, SL or SL-M.
%                     product            - MIS or NRML.
%                     price              - Limit price (sent as a number).
%                     trigger_price      - Trigger price (sent as a number).
%                     disclosed_quantity - Sent as an integer.
%                   Only these fields are sent, in this order.
%     expiry_date - Expiry date in DDMMMYY format (e.g. 25NOV25). Optional
%                   when the underlying includes the expiry.
%     strike_int  - Deprecated. Strike interval, auto-detected by the
%                   server. Sent as an integer with a warning
%                   (openalgo:deprecated) when given.
%     Other name=value pairs are sent as extra fields, as is.
%
%   Payload: apikey, strategy, underlying, exchange, legs (always a JSON
%   array), strike_int (when given), expiry_date (when given), then the
%   extra fields.
%
%   Returns a struct with status, underlying, underlying_ltp, mode (in
%   analyze mode) and results, one entry per leg with leg, symbol, offset,
%   option_type, action, status, orderid and, on error, message.
%
%   Examples:
%     % Iron condor
%     legs = {struct("offset","OTM10","option_type","CE","action","BUY","quantity",75), ...
%             struct("offset","OTM10","option_type","PE","action","BUY","quantity",75), ...
%             struct("offset","OTM5","option_type","CE","action","SELL","quantity",75), ...
%             struct("offset","OTM5","option_type","PE","action","SELL","quantity",75)};
%     r = client.optionsmultiorder(strategy="Iron Condor", underlying="NIFTY", ...
%         exchange="NSE_INDEX", expiry_date="25NOV25", legs=legs);
%
%     % Calendar spread (different expiries, same strike)
%     legs = {struct("offset","ATM","option_type","CE","action","BUY","quantity",75, ...
%                    "expiry_date","30DEC25"), ...
%             struct("offset","ATM","option_type","CE","action","SELL","quantity",75, ...
%                    "expiry_date","25NOV25")};
%     r = client.optionsmultiorder(strategy="Calendar Spread", underlying="NIFTY", ...
%         exchange="NSE_INDEX", legs=legs);
%
%   See also openalgo.api/optionsorder.

[a, kw] = openalgo.internal.parseArgs('optionsmultiorder', varargin, ...
    {'strategy', []; 'underlying', []; 'exchange', []; 'legs', []; ...
     'expiry_date', []; 'strike_int', []}, ...
    {'strategy', 'underlying', 'exchange', 'legs'}, 0, true);

if ~openalgo.internal.isNone(a.strike_int)
    warning('openalgo:deprecated', ...
        'The ''strike_int'' parameter is deprecated and will be removed in future versions.');
end

[legs, isList] = openalgo.internal.toList(a.legs);
if ~isList
    error('openalgo:typeError', 'legs must be a list (cell array or struct array), got %s', class(a.legs));
end
processed = cell(1, numel(legs));
for i = 1:numel(legs)
    leg = legs{i};
    if ~isstruct(leg)
        error('openalgo:typeError', 'Each leg must be a struct (dict), got %s', class(leg));
    end
    p = struct();
    p.offset = field(leg, 'offset');
    p.option_type = field(leg, 'option_type');
    p.action = field(leg, 'action');
    p.quantity = openalgo.internal.pyInt(field(leg, 'quantity'));
    if isfield(leg, 'expiry_date')
        p.expiry_date = leg.expiry_date;
    end
    if isfield(leg, 'pricetype')
        p.pricetype = leg.pricetype;
    end
    if isfield(leg, 'product')
        p.product = leg.product;
    end
    if isfield(leg, 'price')
        p.price = openalgo.internal.JsonFloat(openalgo.internal.pyFloat(leg.price));
    end
    if isfield(leg, 'trigger_price')
        p.trigger_price = openalgo.internal.JsonFloat(openalgo.internal.pyFloat(leg.trigger_price));
    end
    if isfield(leg, 'disclosed_quantity')
        p.disclosed_quantity = openalgo.internal.pyInt(leg.disclosed_quantity);
    end
    processed{i} = p;
end

payload = struct();
payload.apikey = obj.api_key;
payload.strategy = a.strategy;
payload.underlying = a.underlying;
payload.exchange = a.exchange;
payload.legs = processed;
if ~openalgo.internal.isNone(a.strike_int)
    payload.strike_int = openalgo.internal.pyInt(a.strike_int);
end
if ~openalgo.internal.isNone(a.expiry_date)
    payload.expiry_date = a.expiry_date;
end
payload = openalgo.internal.addKwargs(payload, kw, false);

result = obj.makeRequest('optionsmultiorder', payload);
end

function v = field(leg, name)
% leg.(name): raises openalgo:keyError when the key is missing.
if ~isfield(leg, name)
    error('openalgo:keyError', '''%s''', name);
end
v = leg.(name);
end
