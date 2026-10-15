% OPENALGO  OpenAlgo client library for MATLAB.
% Version 1.0.0
%
% A MATLAB port of the OpenAlgo Python SDK: the same method names,
% parameter names, defaults, request payloads and error structs. It uses
% only base MATLAB (matlab.net.http, jsonencode and jsondecode).
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
%   Methods take name=value arguments with the exact, case-sensitive
%   names of the Python SDK, for example
%
%     client = openalgo.api(api_key="your_api_key", host="http://127.0.0.1:5000");
%     resp = client.placeorder(strategy="Python", symbol="SBIN", action="BUY", ...
%         exchange="NSE", price_type="MARKET", product="MIS", quantity=1);
%
%   Parameters that are positional in Python also accept a leading
%   positional value (analyzertoggle(mode), holidays(year), timings(date),
%   whatsapp(message), Strategy.start(mode), Strategy.signal(action)).
%   [] stands for Python None: optional values left at [] are not sent.
%   Extra name=value pairs are sent as extra payload fields where the
%   Python method takes **kwargs. Lists are cell arrays or struct arrays
%   and always go out as JSON arrays.
%
%   Methods that the Python SDK does not have (ping, pnlsymbols,
%   multioptiongreeks, ticker, chart, updatechart and the Telegram
%   management methods) are listed under ADDITIONS in: help openalgo.api
%
%   REST methods return the decoded JSON as a struct and report failures
%   as a struct with status 'error', message and error_type instead of
%   raising. history returns a timetable and instruments a table.
%
% Example
%   client = openalgo.api(api_key=getenv("OPENALGO_API_KEY"));
%   f = client.funds();
%   q = client.quotes(symbol="SBIN", exchange="NSE");
