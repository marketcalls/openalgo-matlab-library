function result = telegrampreferences(obj, varargin)
%TELEGRAMPREFERENCES Read the notification preferences of a Telegram user.
%   RESULT = CLIENT.TELEGRAMPREFERENCES(TELEGRAM_ID)
%
%   Addition: not present in the Python SDK. It covers the documented
%   GET /api/v1/telegram/preferences endpoint of the Telegram management surface.
%
%   Parameters:
%     telegram_id - Telegram user id. Required. Positional or name=value.
%     Other name=value pairs are sent as extra query parameters.
%
%   The request is a GET to telegram/preferences with apikey and
%   telegram_id as query parameters.
%
%   Returns a struct with status and data, the user's preferences.
%
%   An invalid or missing API key answers HTTP 401 (an http_error
%   struct).
%
%   Example:
%     p = client.telegrampreferences(123456789);
%
%   See also openalgo.api/updatetelegrampreferences.

[a, kw] = openalgo.internal.parseArgs('telegrampreferences', varargin, ...
    {'telegram_id', []}, {'telegram_id'}, 1, true);

params = struct();
params.apikey = obj.api_key;
% Parameters left at [] are not sent.
given = {'telegram_id', a.telegram_id};
params = openalgo.internal.addKwargs(params, [given; kw], false);

result = obj.getRequest('telegram/preferences', params);
end
