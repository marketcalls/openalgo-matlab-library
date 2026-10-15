function result = analyzerstatus(obj, varargin)
%ANALYZERSTATUS Get analyzer status information.
%   RESULT = CLIENT.ANALYZERSTATUS()
%
%   Parameters:
%     Any name=value pair is sent as an extra field, as is.
%
%   Payload: apikey, then the extra fields.
%
%   The request goes to the analyzer endpoint.
%
%   Returns a struct with status and data (analyze_mode, mode such as
%   "live" or "analyze", total_logs).
%
%   Example:
%     s = client.analyzerstatus();
%     isSandbox = s.data.analyze_mode;
%
%   See also openalgo.api/analyzertoggle.

[~, kw] = openalgo.internal.parseArgs('analyzerstatus', varargin, {}, {}, 0, true);

payload = struct();
payload.apikey = obj.api_key;
payload = openalgo.internal.addKwargs(payload, kw, false);

result = obj.makeRequest('analyzer', payload);
end
