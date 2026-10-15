function result = telegram(obj, varargin)
%TELEGRAM Send a custom alert message to a Telegram user.
%   RESULT = CLIENT.TELEGRAM(username=USER, message=TEXT, priority=5)
%
%   Prerequisites:
%   1. The Telegram bot must be running (start it from the OpenAlgo
%      Telegram settings).
%   2. The user must have linked their account with the /link command in
%      Telegram. The username is the OpenAlgo login username, not the
%      Telegram username.
%   3. The API key must be active and valid.
%
%   Parameters:
%     username - OpenAlgo login username (not the Telegram handle).
%                Case-sensitive. Required.
%     message  - Alert message. Supports markdown and line breaks (use
%                newline or "\n" inside sprintf). At most 4096 characters.
%                Required.
%     priority - Message priority, 1 to 10 (higher is more urgent).
%                Default 5. 1-3 low (general updates), 4-6 normal (trade
%                signals, summaries), 7-8 high (price alerts, position
%                updates), 9-10 urgent (stop loss hits, risk alerts).
%     Other name=value pairs are sent as extra fields, as is.
%
%   Payload: apikey, username, message, priority, then the extra fields.
%   The request goes to the telegram/notify endpoint.
%
%   Message formatting: *bold* or **bold**, _italic_ or __italic__,
%   `code`, ```pre-formatted```, [text](url).
%
%   Returns a struct with status and message.
%
%   Error messages from the server include:
%     "Invalid or missing API key"
%     "User not found or not linked to Telegram"
%     "Username and message are required"
%     "Failed to send notification" (the bot is not running)
%
%   Rate limit: 30 requests per minute per user (429 when exceeded).
%
%   Examples:
%     r = client.telegram(username="john_trader", ...
%         message="NIFTY crossed 24000! Consider taking profit on long positions.");
%
%     r = client.telegram(username="john_trader", ...
%         message="URGENT: Stop loss hit on BANKNIFTY position!", priority=10);
%
%     msg = sprintf("Daily Trading Summary\nWinning Trades: 8\nLosing Trades: 2");
%     r = client.telegram(username="john_trader", message=msg, priority=5);
%
%   See also openalgo.api/whatsapp.

[a, kw] = openalgo.internal.parseArgs('telegram', varargin, ...
    {'username', []; 'message', []; 'priority', 5}, {'username', 'message'}, 0, true);

payload = struct();
payload.apikey = obj.api_key;
payload.username = a.username;
payload.message = a.message;
payload.priority = a.priority;
payload = openalgo.internal.addKwargs(payload, kw, false);

result = obj.makeRequest('telegram/notify', payload);
end
