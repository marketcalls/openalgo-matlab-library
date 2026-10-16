function result = telegramusers(obj, varargin)
%TELEGRAMUSERS List the users linked to the Telegram bot.
%   RESULT = CLIENT.TELEGRAMUSERS(broker=B, notifications_enabled=TF)
%
%   It covers the documented
%   GET /api/v1/telegram/users endpoint of the Telegram management surface.
%
%   Parameters (optional filters, sent as query parameters when given):
%     broker                - Only users of this broker.
%     notifications_enabled - true or false (sent as "true" or "false").
%     Other name=value pairs are sent as extra query parameters.
%
%   The request is a GET to telegram/users with apikey and the filters
%   as query parameters.
%
%   Returns a struct with status, data (one entry per linked user) and
%   count.
%
%   An invalid or missing API key answers HTTP 401 (an http_error
%   struct).
%
%   Example:
%     users = client.telegramusers(notifications_enabled=true);
%
%   See also openalgo.api/telegrampreferences, openalgo.api/telegrambroadcast.

[a, kw] = openalgo.internal.parseArgs('telegramusers', varargin, ...
    {'broker', []; 'notifications_enabled', []}, {}, 0, true);

params = struct();
params.apikey = obj.api_key;
% Parameters left at [] are not sent.
given = {'broker', a.broker; 'notifications_enabled', a.notifications_enabled};
params = openalgo.internal.addKwargs(params, [given; kw], false);

result = obj.getRequest('telegram/users', params);
end
