function result = whatsapp(obj, varargin)
%WHATSAPP Send a WhatsApp message through the OpenAlgo paired device.
%   RESULT = CLIENT.WHATSAPP(MESSAGE, Name=Value)
%   RESULT = CLIENT.WHATSAPP(message=MESSAGE, Name=Value)
%
%   One call handles every common case: send to self, to a single number
%   or to a small broadcast (at most 5 recipients), with text, image or
%   document attachments. The OpenAlgo server must already be paired to a
%   WhatsApp account from the /whatsapp admin page; pairing is
%   deliberately not exposed through the API, so a leaked API key cannot
%   re-pair the device.
%
%   Recipient (give exactly one form; defaults to self when none):
%     to       - One E.164 digit string such as "919876543210", or a list
%                of up to 5 such strings (a cell array or a string array
%                with more than one element). A list is always sent as a
%                JSON array, even with one element ({"9198..."}).
%                Recipients beyond 5 are dropped server-side.
%     username - OpenAlgo username, resolved through the linked-users
%                table on the server. Wins over to.
%     (neither)  sends to the paired device's own number (self: true).
%
%   Content (combine freely):
%     message  - Plain text body, at most 4096 characters. Positional or
%                name=value.
%     image    - Server-local path to an image file. The caption falls
%                back to message when no caption is given.
%     document - Server-local path to a document (PDF, CSV, ...).
%     caption  - Caption for an image, or follow-up text for a document.
%     filename - Display name of the document on the recipient's device.
%
%   Behaviour:
%     wait_for_delivery - When true (default) the call blocks until
%                         WhatsApp confirms delivery and returns a
%                         per-recipient report. When false the call is
%                         fire-and-forget and returns a "queued"
%                         acknowledgement. Sent as a JSON boolean.
%
%   Other name=value pairs are forwarded as is, unless the payload already
%   has that field.
%
%   Payload: apikey, then username, phones, phone or self (exactly one),
%   message, image_path, document_path, caption, filename (each when
%   given), wait_for_delivery, then the extra fields. The request goes to
%   the whatsapp/notify endpoint.
%
%   Returns a struct. With wait_for_delivery true: status, message (for
%   example "Delivered to 1, failed 0") and data with sent, failed and
%   skipped. With wait_for_delivery false: status, message (for example
%   "Queued for 1 recipient(s)") and queued.
%
%   Error messages from the server include:
%     "WhatsApp is not paired or not connected. Pair the device first from
%      the /whatsapp page in OpenAlgo before sending."
%     "Username not found or not linked to WhatsApp"
%     "image_path is not allowed" / "document_path is not allowed" (the
%      path is outside the allowed attachment roots)
%     "Provide at least one of: message, image_path, document_path"
%     "Invalid or missing API key"
%
%   Rate limit: 30 requests per minute by default; broadcasts (several
%   recipients) 5 per minute (429 when exceeded).
%
%   Notes:
%   - Attachments are read from the OpenAlgo server's file system, not
%     uploaded by the API call. Place files under the configured
%     attachment roots (by default <openalgo>/db/attachments/).
%   - This call uses the notify endpoint, the only public REST surface for
%     WhatsApp; pairing, users, configuration and statistics are
%     admin-only in the web interface.
%
%   Examples:
%     client.whatsapp("Build #482 deployed. P&L: +1.2%");          % to self
%     client.whatsapp("Are you free for a quick call?", to="919876543210");
%     client.whatsapp("Server maintenance in 10 minutes", ...
%         to={"919876543210", "919812345678", "919900112233"});
%     client.whatsapp("NIFTY end-of-day chart", to="919876543210", ...
%         image="/srv/charts/nifty_eod.png");
%     client.whatsapp("Daily P&L report attached", username="alice", ...
%         document="/srv/reports/2026-05-17.pdf", filename="summary.pdf");
%     client.whatsapp("Stop-loss hit on BANKNIFTY!", wait_for_delivery=false);
%
%   See also openalgo.api/telegram.

[a, kw] = openalgo.internal.parseArgs('whatsapp', varargin, ...
    {'message', []; 'to', []; 'username', []; 'image', []; 'document', []; ...
     'caption', []; 'filename', []; 'wait_for_delivery', true}, {}, 1, true);

payload = struct();
payload.apikey = obj.api_key;

to = a.to;
if openalgo.internal.truthy(a.username)
    payload.username = a.username;
elseif iscell(to) || (isstring(to) && ~isscalar(to))
    payload.phones = openalgo.internal.toList(to);
elseif ((ischar(to) && size(to, 1) <= 1) || (isstring(to) && isscalar(to) && ~ismissing(to))) ...
        && strlength(strtrim(string(to))) > 0
    payload.phone = to;
else
    payload.self = true;
end

if ~openalgo.internal.isNone(a.message)
    payload.message = a.message;
end
if ~openalgo.internal.isNone(a.image)
    payload.image_path = a.image;
end
if ~openalgo.internal.isNone(a.document)
    payload.document_path = a.document;
end
if ~openalgo.internal.isNone(a.caption)
    payload.caption = a.caption;
end
if ~openalgo.internal.isNone(a.filename)
    payload.filename = a.filename;
end
payload.wait_for_delivery = openalgo.internal.truthy(a.wait_for_delivery);

% Forward unrecognised name=value pairs so future server-side fields work
% without a library release.
payload = openalgo.internal.addKwargs(payload, kw, false, true);

result = obj.makeRequest('whatsapp/notify', payload);
end
