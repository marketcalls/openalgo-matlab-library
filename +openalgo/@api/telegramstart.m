function result = telegramstart(obj, varargin)
%TELEGRAMSTART Start the Telegram bot.
%   RESULT = CLIENT.TELEGRAMSTART()
%
%   It covers the documented
%   POST /api/v1/telegram/start endpoint of the Telegram management surface.
%
%   Parameters:
%     Any name=value pair is sent as an extra field, as is.
%
%   Initializes polling or webhook mode from the stored configuration.
%   Payload: apikey, then the extra fields.
%
%   Returns a struct with status and message. Without a configured bot
%   token the server answers HTTP 400 ("Bot token not configured").
%
%   An invalid or missing API key answers HTTP 401 (an http_error
%   struct).
%
%   Example:
%     r = client.telegramstart();
%
%   See also openalgo.api/telegramstop, openalgo.api/telegramconfig.

[~, kw] = openalgo.internal.parseArgs('telegramstart', varargin, ...
    {}, {}, 0, true);

payload = struct();
payload.apikey = obj.api_key;
payload = openalgo.internal.addKwargs(payload, kw, false);

result = obj.makeRequest('telegram/start', payload);
end
