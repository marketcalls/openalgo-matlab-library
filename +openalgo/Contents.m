% OPENALGO  OpenAlgo client library for MATLAB.
% Version 1.1.0
%
% The OpenAlgo REST API, strategy webhook and live WebSocket feed for
% MATLAB. It uses only base MATLAB (matlab.net.http, jsonencode and
% jsondecode).
%
% Classes
%   openalgo.api      - OpenAlgo API client (all REST methods and the
%                       WebSocket feed). See: help openalgo.api
%   openalgo.Strategy - Sender for the public strategy webhook.
%   openalgo.BaseAPI  - Base class with the REST request handling.
%   openalgo.FeedAPI  - WebSocket market data feed (inherited by api).
%
% Functions
%   openalgo.version  - Library version.
%
% Calling convention
%   Methods take name=value arguments with exact, case-sensitive
%   names, for example
%
%     client = openalgo.api(api_key="your_api_key", host="http://127.0.0.1:5000");
%     resp = client.placeorder(strategy="MATLAB Strategy", symbol="SBIN", action="BUY", ...
%         exchange="NSE", price_type="MARKET", product="MIS", quantity=1);
%
%   A few methods also accept their main value as a leading
%   positional value (analyzertoggle(mode), holidays(year), timings(date),
%   whatsapp(message), Strategy.start(mode), Strategy.signal(action)).
%   [] means "not set": optional values left at [] are not sent.
%   Extra name=value pairs are sent as extra payload fields on the
%   methods that accept them. Lists are cell arrays or struct arrays
%   and always go out as JSON arrays.
%
%   Utility and management methods (ping, pnlsymbols,
%   multioptiongreeks, ticker, chart, updatechart and the Telegram
%   management methods) are listed in: help openalgo.api
%
%   REST methods return the decoded JSON as a struct and report failures
%   as a struct with status 'error', message and error_type instead of
%   raising. history returns a timetable and instruments a table.
%
% Example
%   client = openalgo.api(api_key=getenv("OPENALGO_API_KEY"));
%   f = client.funds();
%   q = client.quotes(symbol="SBIN", exchange="NSE");
