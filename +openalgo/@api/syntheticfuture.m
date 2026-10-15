function result = syntheticfuture(obj, varargin)
%SYNTHETICFUTURE Calculate the synthetic futures price using ATM call and put options.
%   RESULT = CLIENT.SYNTHETICFUTURE(underlying=U, exchange=X, expiry_date=D)
%
%   A synthetic future replicates the payoff of a futures contract by
%   combining options at the same strike price. The server finds the ATM
%   strike and calculates:
%
%     Synthetic Future Price = Strike Price + Call Premium - Put Premium
%
%   Parameters:
%     underlying  - Underlying symbol (e.g. NIFTY, BANKNIFTY, RELIANCE).
%                   Required.
%     exchange    - Exchange code. Required. NSE_INDEX (NIFTY, BANKNIFTY,
%                   FINNIFTY, MIDCPNIFTY), BSE_INDEX (SENSEX, BANKEX,
%                   SENSEX50), NSE or BSE (equity stocks).
%     expiry_date - Expiry date in DDMMMYY format (e.g. 28NOV25). Required.
%     Other name=value pairs are sent as extra fields, as is.
%
%   Payload: apikey, underlying, exchange, expiry_date, then the extra
%   fields.
%
%   Returns a struct with status, underlying, underlying_ltp, expiry,
%   atm_strike and synthetic_future_price.
%
%   Notes:
%   - This API only calculates and returns data; it places no trades.
%   - Index exchanges (NSE_INDEX, BSE_INDEX) are mapped to the options
%     exchanges (NFO, BFO) automatically.
%
%   Example:
%     r = client.syntheticfuture(underlying="NIFTY", exchange="NSE_INDEX", ...
%         expiry_date="28NOV25");
%     if strcmp(r.status, "success")
%         basis = r.synthetic_future_price - r.underlying_ltp;
%     end
%
%   See also openalgo.api/optionchain, openalgo.api/expiry.

[a, kw] = openalgo.internal.parseArgs('syntheticfuture', varargin, ...
    {'underlying', []; 'exchange', []; 'expiry_date', []}, ...
    {'underlying', 'exchange', 'expiry_date'}, 0, true);

payload = struct();
payload.apikey = obj.api_key;
payload.underlying = a.underlying;
payload.exchange = a.exchange;
payload.expiry_date = a.expiry_date;
payload = openalgo.internal.addKwargs(payload, kw, false);

result = obj.makeRequest('syntheticfuture', payload);
end
