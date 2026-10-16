function result = ping(obj, varargin)
%PING Check API connectivity and authentication.
%   RESULT = CLIENT.PING()
%
%   It covers the documented
%   POST /api/v1/ping endpoint.
%
%   Verifies that the API key resolves to an active broker session. This
%   is not an anonymous health check: an invalid key or a revoked or
%   missing broker session answers HTTP 403 (an http_error struct).
%
%   Parameters:
%     Any name=value pair is sent as an extra field, as is.
%
%   Payload: apikey, then the extra fields.
%
%   Returns a struct with status "success" and data (message "pong" and
%   the broker name).
%
%   Example:
%     r = client.ping();
%     if strcmp(r.status, "success"), disp(r.data.message), end
%
%   See also openalgo.api/funds, openalgo.api/analyzerstatus.

[~, kw] = openalgo.internal.parseArgs('ping', varargin, {}, {}, 0, true);

payload = struct();
payload.apikey = obj.api_key;
payload = openalgo.internal.addKwargs(payload, kw, false);

result = obj.makeRequest('ping', payload);
end
