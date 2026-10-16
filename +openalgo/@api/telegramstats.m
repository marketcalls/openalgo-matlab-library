function result = telegramstats(obj, varargin)
%TELEGRAMSTATS Get Telegram bot command statistics.
%   RESULT = CLIENT.TELEGRAMSTATS() or CLIENT.TELEGRAMSTATS(DAYS)
%
%   It covers the documented
%   GET /api/v1/telegram/stats endpoint of the Telegram management surface.
%
%   Parameters:
%     days - Number of days, 1 to 365. Optional (server default 7; values
%            outside the range are clamped). Positional or name=value.
%     Other name=value pairs are sent as extra query parameters.
%
%   The request is a GET to telegram/stats with apikey and days (when
%   given) as query parameters.
%
%   Returns a struct with status and data, the command statistics.
%
%   An invalid or missing API key answers HTTP 401 (an http_error
%   struct).
%
%   Example:
%     s = client.telegramstats(30);
%
%   See also openalgo.api/telegramusers.

[a, kw] = openalgo.internal.parseArgs('telegramstats', varargin, ...
    {'days', []}, {}, 1, true);

params = struct();
params.apikey = obj.api_key;
% Parameters left at [] are not sent.
given = {'days', a.days};
params = openalgo.internal.addKwargs(params, [given; kw], false);

result = obj.getRequest('telegram/stats', params);
end
