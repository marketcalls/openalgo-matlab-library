function result = updatechart(obj, varargin)
%UPDATECHART Update the chart preferences stored for the API key.
%   RESULT = CLIENT.UPDATECHART(Name=Value, ...)
%
%   Addition: not present in the Python SDK. It covers the documented
%   POST /api/v1/chart endpoint.
%
%   Every name=value pair is one preference key and its value, sent as
%   is (a struct value becomes a JSON object). Pairs whose value is []
%   are not sent. The request must carry 1 to 50 preferences, and each
%   key is at most 50 characters; the server also limits each
%   JSON-serialized value to 1 MiB. The count and key length are checked
%   before sending and reported as a struct with error_type
%   'validation_error', with the server's own messages:
%     'No preferences provided to update'
%     'Too many preference keys (max 50)'
%     'Preference key too long: <first 20 characters>... (max 50 chars)'
%
%   Payload: apikey, then the preferences in the order given.
%
%   Returns the JSON response as a struct. An invalid key answers HTTP 403
%   (an http_error struct).
%
%   Example:
%     r = client.updatechart(tv_theme="dark", tv_chart_layout=struct("interval", "15m"));
%
%   See also openalgo.api/chart.

[~, kw] = openalgo.internal.parseArgs('updatechart', varargin, {}, {}, 0, true);

keep = ~cellfun(@openalgo.internal.isNone, kw(:, 2));
prefs = kw(keep, :);
if size(prefs, 1) > 50
    result = openalgo.internal.errorResult('Too many preference keys (max 50)', 'validation_error');
    return
end
for i = 1:size(prefs, 1)
    k = prefs{i, 1};
    if numel(k) > 50
        result = openalgo.internal.errorResult( ...
            sprintf('Preference key too long: %s... (max 50 chars)', k(1:20)), 'validation_error');
        return
    end
end
if isempty(prefs)
    result = openalgo.internal.errorResult('No preferences provided to update', 'validation_error');
    return
end

payload = struct();
payload.apikey = obj.api_key;
payload = openalgo.internal.addKwargs(payload, prefs, false);

result = obj.makeRequest('chart', payload);
end
