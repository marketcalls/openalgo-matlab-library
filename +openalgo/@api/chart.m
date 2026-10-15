function result = chart(obj, varargin)
%CHART Read the chart preferences stored for the API key.
%   RESULT = CLIENT.CHART()
%
%   Addition: not present in the Python SDK. It covers the documented
%   GET /api/v1/chart endpoint.
%
%   Parameters:
%     Any name=value pair is sent as an extra query parameter.
%
%   The request is a GET to chart with apikey as a query parameter.
%
%   Returns a struct with status and data, holding every stored
%   preference key. An invalid key answers HTTP 403 (an http_error
%   struct). Preference names that are not valid MATLAB identifiers are
%   renamed by jsondecode.
%
%   Example:
%     prefs = client.chart();
%
%   See also openalgo.api/updatechart.

[~, kw] = openalgo.internal.parseArgs('chart', varargin, {}, {}, 0, true);

params = struct();
params.apikey = obj.api_key;
params = openalgo.internal.addKwargs(params, kw, false);

result = obj.getRequest('chart', params);
end
