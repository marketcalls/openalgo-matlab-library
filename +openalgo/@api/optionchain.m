function result = optionchain(obj, varargin)
%OPTIONCHAIN Fetch option chain data with real-time quotes for all strikes.
%   RESULT = CLIENT.OPTIONCHAIN(underlying=U, exchange=X, expiry_date=D, strike_count=N)
%
%   Returns the option chain with call and put data for each strike,
%   including LTP, bid/ask, OHLC, volume, OI, lot size and moneyness
%   labels.
%
%   Parameters:
%     underlying   - Underlying symbol (e.g. NIFTY, BANKNIFTY, RELIANCE, or
%                    a future like NIFTY30DEC25FUT). Required.
%     exchange     - Exchange code (NSE_INDEX, NSE, NFO, BSE_INDEX, BSE,
%                    BFO). Required.
%     expiry_date  - Expiry date in DDMMMYY format (e.g. 30DEC25). Needed
%                    unless the underlying includes the expiry. Optional.
%     strike_count - Number of strikes above and below ATM (1 to 100).
%                    All strikes are returned when omitted. Sent as an
%                    integer. Optional.
%     Other name=value pairs are sent as extra fields, as is.
%
%   Payload: apikey, underlying, exchange, expiry_date (when given),
%   strike_count (when given), then the extra fields.
%
%   Returns a struct with status, underlying, underlying_ltp, expiry_date,
%   atm_strike and chain, one entry per strike with strike, ce and pe. ce
%   and pe hold symbol, label (ATM, ITM1, OTM1, ...), ltp, bid, ask, open,
%   high, low, prev_close, volume, oi, lotsize and tick_size, or are empty
%   when the side does not exist.
%
%   Label logic: strikes below ATM have ITM calls and OTM puts, strikes
%   above ATM have OTM calls and ITM puts, and the ATM strike labels both
%   sides ATM.
%
%   Examples:
%     chain = client.optionchain(underlying="NIFTY", exchange="NSE_INDEX", ...
%         expiry_date="30DEC25", strike_count=10);
%     chain = client.optionchain(underlying="NIFTY30DEC25FUT", exchange="NFO");
%
%   See also openalgo.api/optiongreeks, openalgo.api/expiry.

[a, kw] = openalgo.internal.parseArgs('optionchain', varargin, ...
    {'underlying', []; 'exchange', []; 'expiry_date', []; 'strike_count', []}, ...
    {'underlying', 'exchange'}, 0, true);

payload = struct();
payload.apikey = obj.api_key;
payload.underlying = a.underlying;
payload.exchange = a.exchange;
if ~openalgo.internal.isNone(a.expiry_date)
    payload.expiry_date = a.expiry_date;
end
if ~openalgo.internal.isNone(a.strike_count)
    payload.strike_count = openalgo.internal.pyInt(a.strike_count);
end
payload = openalgo.internal.addKwargs(payload, kw, false);

result = obj.makeRequest('optionchain', payload);
end
