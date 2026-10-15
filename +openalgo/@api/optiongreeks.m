function result = optiongreeks(obj, varargin)
%OPTIONGREEKS Calculate option Greeks and implied volatility (Black-76 model).
%   RESULT = CLIENT.OPTIONGREEKS(symbol=S, exchange=X, Name=Value)
%
%   Computes Delta, Gamma, Theta, Vega, Rho and the implied volatility of
%   an option. Needs the real-time LTP of the underlying and the option,
%   unless forward_price is given.
%
%   Parameters:
%     symbol              - Option symbol (e.g. NIFTY02DEC2526000CE).
%                           Required.
%     exchange            - Exchange code (NFO, BFO, CDS, MCX). Required.
%     interest_rate       - Risk-free interest rate (annualized %). Server
%                           default 0. Specify the current rate (e.g. 6.5)
%                           for accurate Rho. Optional.
%     forward_price       - Custom forward or synthetic futures price. If
%                           given, the underlying price fetch is skipped.
%                           Useful for synthetic futures pricing, illiquid
%                           underlyings and scenario analysis. Optional.
%     underlying_symbol   - Custom underlying symbol (e.g. NIFTY or
%                           NIFTY30DEC25FUT). Auto-detected if omitted.
%     underlying_exchange - Custom underlying exchange (e.g. NSE_INDEX or
%                           NFO). Auto-detected if omitted.
%     expiry_time         - Custom expiry time in HH:MM format (e.g.
%                           "17:00"). Needed for MCX contracts with
%                           non-standard expiry times. Exchange defaults:
%                           NFO/BFO 15:30, CDS 12:30, MCX 23:30.
%     Other name=value pairs are sent as extra fields, as is.
%
%   Optional parameters left at [] are not sent. Payload: apikey, symbol,
%   exchange, the optional parameters that were given (in the order
%   above), then the extra fields.
%
%   Returns a struct with status, symbol, exchange, underlying, strike,
%   option_type, expiry_date, days_to_expiry, spot_price, option_price,
%   interest_rate, implied_volatility and greeks (delta, gamma, theta,
%   vega, rho).
%
%   Examples:
%     g = client.optiongreeks(symbol="NIFTY02DEC2526000CE", exchange="NFO");
%     g = client.optiongreeks(symbol="BANKNIFTY30DEC2550000CE", exchange="NFO", ...
%         interest_rate=6.5);
%     g = client.optiongreeks(symbol="NIFTY30DEC2526000CE", exchange="NFO", ...
%         underlying_symbol="NIFTY30DEC25FUT", underlying_exchange="NFO");
%     g = client.optiongreeks(symbol="CRUDEOIL17DEC255400CE", exchange="MCX", ...
%         expiry_time="19:00");
%
%   See also openalgo.api/optionchain, openalgo.api/optionsymbol.

[a, kw] = openalgo.internal.parseArgs('optiongreeks', varargin, ...
    {'symbol', []; 'exchange', []; 'interest_rate', []; 'forward_price', []; ...
     'underlying_symbol', []; 'underlying_exchange', []; 'expiry_time', []}, ...
    {'symbol', 'exchange'}, 0, true);

payload = struct();
payload.apikey = obj.api_key;
payload.symbol = a.symbol;
payload.exchange = a.exchange;
optional = {'interest_rate', 'forward_price', 'underlying_symbol', ...
    'underlying_exchange', 'expiry_time'};
for i = 1:numel(optional)
    value = a.(optional{i});
    if ~openalgo.internal.isNone(value)
        payload.(optional{i}) = value;
    end
end
payload = openalgo.internal.addKwargs(payload, kw, false);

result = obj.makeRequest('optiongreeks', payload);
end
