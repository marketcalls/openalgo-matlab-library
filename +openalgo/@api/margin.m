function result = margin(obj, varargin)
%MARGIN Calculate margin requirements for a basket of positions.
%   RESULT = CLIENT.MARGIN(positions=POSITIONS)
%
%   Calculates the total margin required for one or more positions,
%   taking into account margin benefits for hedged positions where the
%   broker supports them.
%
%   Parameters:
%     positions - List of positions (at most 50), a cell array of structs
%                 or a struct array. Required. Each position has:
%                   symbol        - Trading symbol (e.g. "SBIN",
%                                   "NIFTY30DEC2526000CE"). Required.
%                   exchange      - NSE, BSE, NFO, BFO, CDS or MCX. Required.
%                   action        - "BUY" or "SELL". Required.
%                   product       - CNC, MIS or NRML. Required.
%                   pricetype     - MARKET, LIMIT, SL or SL-M. Required.
%                   quantity      - Quantity to trade. Required.
%                   price         - Price for LIMIT orders. Default "0".
%                   trigger_price - Trigger price for SL and SL-M orders.
%                                   Default "0".
%                 quantity, price and trigger_price are sent as text; a
%                 missing price or trigger_price is added as "0".
%     Other name=value pairs are sent as extra fields, as is.
%
%   Payload: apikey, positions (always a JSON array), then the extra
%   fields.
%
%   Returns a struct with status and data (total_margin_required and,
%   for most brokers, span_margin and exposure_margin). Invalid input is
%   reported as a struct with error_type 'validation_error':
%     'Positions must be an array'
%     'Positions array cannot be empty'
%     'Maximum 50 positions allowed'
%
%   Notes:
%   - Basket margin calculation may provide a margin benefit for hedged
%     positions. Behaviour varies by broker: some support a batch margin
%     call, some calculate single positions and aggregate them, some
%     return an account-level margin.
%   - For MARKET orders, price can be "0"; LIMIT orders need a price and
%     SL or SL-M orders need a trigger_price.
%
%   Examples:
%     % Single position
%     r = client.margin(positions={struct("symbol","SBIN","exchange","NSE", ...
%         "action","BUY","product","MIS","pricetype","LIMIT", ...
%         "quantity","10","price","750.50")});
%
%     % Basket (short strangle)
%     p1 = struct("symbol","NIFTY30DEC2526000CE","exchange","NFO","action","SELL", ...
%         "product","NRML","pricetype","LIMIT","quantity","75","price","150.75");
%     p2 = struct("symbol","NIFTY30DEC2526000PE","exchange","NFO","action","SELL", ...
%         "product","NRML","pricetype","LIMIT","quantity","75","price","125.50");
%     r = client.margin(positions={p1, p2});
%
%   See also openalgo.api/funds.

[a, kw] = openalgo.internal.parseArgs('margin', varargin, ...
    {'positions', []}, {'positions'}, 0, true);

[positions, isList] = openalgo.internal.toList(a.positions);
if ~isList || ~(iscell(a.positions) || isstruct(a.positions))
    result = openalgo.internal.errorResult('Positions must be an array', 'validation_error');
    return
end
if isempty(positions)
    result = openalgo.internal.errorResult('Positions array cannot be empty', 'validation_error');
    return
end
if numel(positions) > 50
    result = openalgo.internal.errorResult('Maximum 50 positions allowed', 'validation_error');
    return
end

processed = cell(1, numel(positions));
for i = 1:numel(positions)
    position = positions{i};
    if ~isstruct(position)
        error('openalgo:typeError', 'Each position must be a struct (dict), got %s', class(position));
    end
    p = struct();
    f = fieldnames(position);
    for j = 1:numel(f)
        value = position.(f{j});
        if any(strcmp(f{j}, {'quantity', 'price', 'trigger_price'})) && ~openalgo.internal.isNone(value)
            p.(f{j}) = openalgo.internal.pyStr(value);
        else
            p.(f{j}) = value;
        end
    end
    if ~isfield(p, 'price')
        p.price = '0';
    end
    if ~isfield(p, 'trigger_price')
        p.trigger_price = '0';
    end
    processed{i} = p;
end

payload = struct();
payload.apikey = obj.api_key;
payload.positions = processed;
payload = openalgo.internal.addKwargs(payload, kw, false);

result = obj.makeRequest('margin', payload);
end
