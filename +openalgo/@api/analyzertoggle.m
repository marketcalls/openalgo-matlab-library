function result = analyzertoggle(obj, varargin)
%ANALYZERTOGGLE Toggle analyzer mode between analyze and live modes.
%   RESULT = CLIENT.ANALYZERTOGGLE(MODE) or CLIENT.ANALYZERTOGGLE(mode=MODE)
%
%   Parameters:
%     mode - true for analyze mode (simulated), false for live mode.
%            Required. Positional or name=value. Sent as is.
%     Other name=value pairs are sent as extra fields, as is.
%
%   Payload: apikey, mode, then the extra fields. The request goes to the
%   analyzer/toggle endpoint.
%
%   Returns a struct with status and data (mode "live" or "analyze",
%   analyze_mode, total_logs, message).
%
%   Example:
%     r = client.analyzertoggle(true);    % switch to analyze (sandbox) mode
%
%   See also openalgo.api/analyzerstatus.

[a, kw] = openalgo.internal.parseArgs('analyzertoggle', varargin, ...
    {'mode', []}, {'mode'}, 1, true);

payload = struct();
payload.apikey = obj.api_key;
payload.mode = a.mode;
payload = openalgo.internal.addKwargs(payload, kw, false);

result = obj.makeRequest('analyzer/toggle', payload);
end
