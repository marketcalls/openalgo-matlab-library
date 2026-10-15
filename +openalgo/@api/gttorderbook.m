function result = gttorderbook(obj, varargin)
%GTTORDERBOOK List the authenticated user's GTT triggers.
%   RESULT = CLIENT.GTTORDERBOOK() or CLIENT.GTTORDERBOOK(status="all")
%
%   By default only active triggers are returned, the ones that can still
%   fire. Pass status="all" for the history as well (triggered, cancelled,
%   expired, rejected), ordered active first. Needs an OpenAlgo server
%   that accepts the status field; older servers refuse it as an unknown
%   field.
%
%   Parameters (all name=value, passed through unchanged):
%     status - "active" (server default) or "all". Optional.
%     Any other name=value pair is passed through for future extensions.
%
%   Payload: apikey, then the name=value pairs.
%
%   Returns a struct with status "success" and data, one entry per trigger
%   carrying trigger_id, trigger_type ("single" or "two-leg"), status,
%   symbol, exchange, trigger_prices (ascending), last_price, legs,
%   created_at, updated_at and expires_at. A SINGLE has one trigger price
%   and one leg; an OCO has two of each, stoploss first.
%
%   Example:
%     book = client.gttorderbook(status="all");
%
%   See also openalgo.api/placegttorder.

[~, kw] = openalgo.internal.parseArgs('gttorderbook', varargin, {}, {}, 0, true);

payload = struct();
payload.apikey = obj.api_key;
payload = openalgo.internal.addKwargs(payload, kw, false);

result = obj.post('gttorderbook', payload);
end
