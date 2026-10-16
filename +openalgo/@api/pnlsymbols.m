function result = pnlsymbols(obj, varargin)
%PNLSYMBOLS Get today's sandbox P&L broken down by symbol.
%   RESULT = CLIENT.PNLSYMBOLS()
%
%   It covers the documented
%   POST /api/v1/pnl/symbols endpoint.
%
%   Returns today's realized and unrealized P&L for the open sandbox
%   positions. Available only while analyzer (sandbox) mode is enabled: in
%   live mode the server answers HTTP 400, and an invalid API key answers
%   HTTP 403 (both as http_error structs).
%
%   Parameters:
%     Any name=value pair is sent as an extra field, as is.
%
%   Payload: apikey, then the extra fields.
%
%   Returns a struct with status, data (one entry per position with
%   symbol, exchange, product, quantity, pnl, unrealized_pnl,
%   today_realized_pnl and total_pnl_today), total_pnl,
%   total_unrealized_pnl, total_today_realized_pnl, total_pnl_today and
%   mode.
%
%   Example:
%     r = client.pnlsymbols();
%
%   See also openalgo.api/positionbook, openalgo.api/analyzerstatus.

[~, kw] = openalgo.internal.parseArgs('pnlsymbols', varargin, {}, {}, 0, true);

payload = struct();
payload.apikey = obj.api_key;
payload = openalgo.internal.addKwargs(payload, kw, false);

result = obj.makeRequest('pnl/symbols', payload);
end
