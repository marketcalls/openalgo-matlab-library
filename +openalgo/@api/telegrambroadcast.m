function result = telegrambroadcast(obj, varargin)
%TELEGRAMBROADCAST Broadcast a message to the linked Telegram users.
%   RESULT = CLIENT.TELEGRAMBROADCAST(message=TEXT, filters=S)
%
%   Addition: not present in the Python SDK. It covers the documented
%   POST /api/v1/telegram/broadcast endpoint of the Telegram management surface.
%
%   Parameters:
%     message - Message to broadcast, at most 4096 characters. Required.
%     filters - Optional user filters (a struct), sent as a JSON object.
%     Other name=value pairs are sent as extra fields, as is.
%
%   Payload: apikey, message, filters (when given), then the extra
%   fields.
%
%   Returns a struct with status, message, success_count and fail_count.
%   The server currently validates the request but reports zero
%   deliveries. A missing or empty message, or one longer than 4096
%   characters, is reported before sending as a struct with error_type
%   'validation_error' ('Message is required', 'Message must not exceed
%   4096 characters'). A disabled broadcast answers HTTP 403. Rate limit: 5
%   requests per minute.
%
%   An invalid or missing API key answers HTTP 401 (an http_error
%   struct).
%
%   Example:
%     r = client.telegrambroadcast(message="Markets open in 15 minutes");
%
%   See also openalgo.api/telegram, openalgo.api/telegramusers.

[a, kw] = openalgo.internal.parseArgs('telegrambroadcast', varargin, ...
    {'message', []; 'filters', []}, {'message'}, 0, true);

% Required fields are checked before sending, with the server's messages.
msg = a.message;
isText = (ischar(msg) && size(msg, 1) <= 1) || (isstring(msg) && isscalar(msg) && ~ismissing(msg));
if ~isText || strlength(string(msg)) == 0
    result = openalgo.internal.errorResult('Message is required', 'validation_error');
    return
end
if strlength(string(msg)) > 4096
    result = openalgo.internal.errorResult('Message must not exceed 4096 characters', ...
        'validation_error');
    return
end

payload = struct();
payload.apikey = obj.api_key;
% Parameters left at [] are not sent.
given = {'message', a.message; 'filters', a.filters};
payload = openalgo.internal.addKwargs(payload, [given; kw], false);

result = obj.makeRequest('telegram/broadcast', payload);
end
