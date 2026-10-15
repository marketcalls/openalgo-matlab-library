function result = telegramstop(obj, varargin)
%TELEGRAMSTOP Stop the Telegram bot.
%   RESULT = CLIENT.TELEGRAMSTOP()
%
%   Addition: not present in the Python SDK. It covers the documented
%   POST /api/v1/telegram/stop endpoint of the Telegram management surface.
%
%   Parameters:
%     Any name=value pair is sent as an extra field, as is.
%
%   While the bot is stopped the automatic order-event alerts stop, and
%   telegram (notify) calls are refused with HTTP 409 "Telegram bot is
%   stopped. Start the bot to send notifications."
%   Payload: apikey, then the extra fields.
%
%   Returns a struct with status and message.
%
%   An invalid or missing API key answers HTTP 401 (an http_error
%   struct).
%
%   Example:
%     r = client.telegramstop();
%
%   See also openalgo.api/telegramstart.

[~, kw] = openalgo.internal.parseArgs('telegramstop', varargin, ...
    {}, {}, 0, true);

payload = struct();
payload.apikey = obj.api_key;
payload = openalgo.internal.addKwargs(payload, kw, false);

result = obj.makeRequest('telegram/stop', payload);
end
