function [payload, err] = gttPayload(apiKey, a, kw)
%GTTPAYLOAD Build and validate the flat GTT body shared by place and modify.
%   [PAYLOAD, ERR] = gttPayload(APIKEY, A, KW) mirrors the Python
%   GTTAPI._gtt_payload. A holds the parsed GTT parameters and KW the
%   extra name=value pairs (passed through unchanged). On a bad SINGLE/OCO
%   combination PAYLOAD is [] and ERR is the validation_error struct;
%   otherwise ERR is [].
%
%   Validation mirrors the server's own rules rather than adding to them.
%   It returns an error struct instead of raising, so a trading loop
%   handles it the same way it handles every other failure.

payload = [];
err = [];

triggerType = upper(openalgo.internal.pyStr(a.trigger_type));
if ~any(strcmp(triggerType, {'SINGLE', 'OCO'}))
    err = openalgo.internal.errorResult('trigger_type must be ''SINGLE'' or ''OCO''.', ...
        'validation_error');
    return
end

slTrigger = num(a.triggerprice_sl, 0.0);
tgTrigger = num(a.triggerprice_tg, 0.0);

if strcmp(triggerType, 'OCO')
    slLimit = num(a.stoploss, []);
    tgLimit = num(a.target, []);
    names = {'triggerprice_sl', 'stoploss', 'triggerprice_tg', 'target'};
    values = {slTrigger, slLimit, tgTrigger, tgLimit};
    missingNames = {};
    for i = 1:numel(names)
        if ~openalgo.internal.truthy(values{i})
            missingNames{end+1} = names{i}; %#ok<AGROW>
        end
    end
    if ~isempty(missingNames)
        err = openalgo.internal.errorResult( ...
            sprintf('Required for OCO: %s.', strjoin(missingNames, ', ')), 'validation_error');
        return
    end
    if slTrigger >= tgTrigger
        err = openalgo.internal.errorResult(['Stoploss trigger must be less than target trigger ' ...
            '(triggerprice_sl < triggerprice_tg).'], 'validation_error');
        return
    end
else
    if slTrigger <= 0 && tgTrigger <= 0
        err = openalgo.internal.errorResult(['SINGLE GTT requires a positive triggerprice_sl or ' ...
            'triggerprice_tg.'], 'validation_error');
        return
    end
    if slTrigger > 0 && tgTrigger > 0
        err = openalgo.internal.errorResult(['SINGLE GTT takes exactly one of triggerprice_sl or ' ...
            'triggerprice_tg; set the other to 0.'], 'validation_error');
        return
    end
    % SINGLE has no legs, so the per-leg limits are sent as JSON null.
    slLimit = [];
    tgLimit = [];
end

% Python: float(quantity) if float(quantity) % 1 else int(quantity)
q = openalgo.internal.pyFloat(a.quantity);
if openalgo.internal.truthy(mod(q, 1))
    quantity = openalgo.internal.JsonFloat(q);
else
    quantity = openalgo.internal.pyInt(a.quantity);
end

payload = struct();
payload.apikey = apiKey;
payload.strategy = a.strategy;
payload.trigger_type = triggerType;
payload.exchange = a.exchange;
payload.symbol = a.symbol;
payload.action = upper(openalgo.internal.pyStr(a.action));
payload.product = a.product;
payload.quantity = quantity;
payload.pricetype = a.price_type;
payload.price = openalgo.internal.JsonFloat(num(a.price, 0.0));
payload.triggerprice_sl = openalgo.internal.JsonFloat(slTrigger);
payload.triggerprice_tg = openalgo.internal.JsonFloat(tgTrigger);
payload.stoploss = asFloat(slLimit);   % [] (SINGLE) encodes as JSON null
payload.target = asFloat(tgLimit);
payload = openalgo.internal.addKwargs(payload, kw, false);
end

function v = num(value, default)
% Python _num: coerce to float, treating None and "" as unset.
isText = (ischar(value) && size(value, 1) <= 1) || (isstring(value) && isscalar(value));
if openalgo.internal.isNone(value) || (isText && strlength(string(value)) == 0)
    v = default;
    return
end
v = openalgo.internal.pyFloat(value);
end

function v = asFloat(v)
% Mark a float for JSON; None stays None.
if ~isempty(v)
    v = openalgo.internal.JsonFloat(v);
end
end
