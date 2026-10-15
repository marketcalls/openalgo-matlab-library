function result = updatetelegramconfig(obj, varargin)
%UPDATETELEGRAMCONFIG Update the Telegram bot configuration.
%   RESULT = CLIENT.UPDATETELEGRAMCONFIG(Name=Value)
%
%   Addition: not present in the Python SDK. It covers the documented
%   POST /api/v1/telegram/config endpoint of the Telegram management surface.
%
%   Parameters (all optional; only the ones given are sent):
%     token                 - Bot token.
%     webhook_url           - Webhook URL for webhook mode.
%     polling_mode          - true for polling mode, false for webhook mode.
%     broadcast_enabled     - Allow broadcasts (true or false).
%     rate_limit_per_minute - Integer from 1 to 120.
%     Other name=value pairs are sent as extra fields, as is.
%
%   Payload: apikey, then the parameters that were given in the order
%   above, then the extra fields.
%
%   Returns a struct with status and message ("Bot configuration
%   updated"). A rate_limit_per_minute outside 1 to 120, or not an
%   integer, answers HTTP 400.
%
%   An invalid or missing API key answers HTTP 401 (an http_error
%   struct).
%
%   Example:
%     r = client.updatetelegramconfig(polling_mode=true, rate_limit_per_minute=30);
%
%   See also openalgo.api/telegramconfig.

[a, kw] = openalgo.internal.parseArgs('updatetelegramconfig', varargin, ...
    {'token', []; 'webhook_url', []; 'polling_mode', []; 'broadcast_enabled', []; 'rate_limit_per_minute', []}, {}, 0, true);

payload = struct();
payload.apikey = obj.api_key;
% Parameters left at [] are not sent.
given = {'token', a.token; 'webhook_url', a.webhook_url; 'polling_mode', a.polling_mode; 'broadcast_enabled', a.broadcast_enabled; 'rate_limit_per_minute', a.rate_limit_per_minute};
payload = openalgo.internal.addKwargs(payload, [given; kw], false);

result = obj.makeRequest('telegram/config', payload);
end
