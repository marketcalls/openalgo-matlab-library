function result = telegramconfig(obj, varargin)
%TELEGRAMCONFIG Read the Telegram bot configuration.
%   RESULT = CLIENT.TELEGRAMCONFIG()
%
%   It covers the documented
%   GET /api/v1/telegram/config endpoint of the Telegram management surface.
%
%   Parameters:
%     Any name=value pair is sent as an extra query parameter.
%
%   The request is a GET to telegram/config with apikey as a query
%   parameter.
%
%   Returns a struct with status and data, the bot configuration with the
%   bot token masked (its first 10 characters followed by "...").
%
%   An invalid or missing API key answers HTTP 401 (an http_error
%   struct).
%
%   Example:
%     cfg = client.telegramconfig();
%
%   See also openalgo.api/updatetelegramconfig, openalgo.api/telegramstart.

[~, kw] = openalgo.internal.parseArgs('telegramconfig', varargin, ...
    {}, {}, 0, true);

params = struct();
params.apikey = obj.api_key;
params = openalgo.internal.addKwargs(params, kw, false);

result = obj.getRequest('telegram/config', params);
end
