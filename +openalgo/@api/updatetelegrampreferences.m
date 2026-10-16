function result = updatetelegrampreferences(obj, varargin)
%UPDATETELEGRAMPREFERENCES Update the notification preferences of a Telegram user.
%   RESULT = CLIENT.UPDATETELEGRAMPREFERENCES(TELEGRAM_ID, Name=Value)
%
%   It covers the documented
%   POST /api/v1/telegram/preferences endpoint of the Telegram management surface.
%
%   Parameters:
%     telegram_id         - Telegram user id. Required. Positional or
%                           name=value. Sent as is.
%     order_notifications - true or false. Optional.
%     trade_notifications - true or false. Optional.
%     pnl_notifications   - true or false. Optional.
%     daily_summary       - true or false. Optional.
%     summary_time        - Time of the daily summary, e.g. "18:00". Optional.
%     language            - Language code. Optional.
%     timezone            - Time zone name, e.g. "Asia/Kolkata". Optional.
%     Other name=value pairs are sent as extra fields, as is (the server
%     ignores keys it does not support).
%
%   Only the preferences that were given are sent. Payload: apikey,
%   telegram_id, the given preferences in the order above, then the extra
%   fields.
%
%   Returns a struct with status and message ("Preferences updated
%   successfully").
%
%   An invalid or missing API key answers HTTP 401 (an http_error
%   struct).
%
%   Example:
%     r = client.updatetelegrampreferences(123456789, daily_summary=true, summary_time="18:00");
%
%   See also openalgo.api/telegrampreferences.

[a, kw] = openalgo.internal.parseArgs('updatetelegrampreferences', varargin, ...
    {'telegram_id', []; 'order_notifications', []; 'trade_notifications', []; 'pnl_notifications', []; 'daily_summary', []; 'summary_time', []; 'language', []; 'timezone', []}, {'telegram_id'}, 1, true);

payload = struct();
payload.apikey = obj.api_key;
% Parameters left at [] are not sent.
given = {'telegram_id', a.telegram_id; 'order_notifications', a.order_notifications; 'trade_notifications', a.trade_notifications; 'pnl_notifications', a.pnl_notifications; 'daily_summary', a.daily_summary; 'summary_time', a.summary_time; 'language', a.language; 'timezone', a.timezone};
payload = openalgo.internal.addKwargs(payload, [given; kw], false);

result = obj.makeRequest('telegram/preferences', payload);
end
