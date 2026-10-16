function [result, isTransport] = transportError(ME)
%TRANSPORTERROR Map a MATLAB exception from an HTTP call to the SDK error struct.
%   [RESULT, ISTRANSPORT] = openalgo.internal.transportError(ME) classifies
%   an MException raised while sending a request with matlab.net.http:
%
%     timeout (connect or read)          -> timeout_error
%     refused connection, unknown host   -> connection_error
%     any other HTTP or transport error  -> http_error 'HTTP error occurred: ...'
%     anything else                      -> unknown_error 'An unexpected error occurred: ...'
%
%   ISTRANSPORT is false only for the last case, which lets callers that
%   catch transport errors alone (Strategy.send) rethrow everything else.

[ids, msgs] = collect(ME);
idText = lower(strjoin(ids, ' '));
msgText = lower(strjoin(msgs, ' '));

isTimeout = contains(idText, {'timeout', 'timedout'}) || ...
    contains(msgText, {'timed out', 'timeout', 'did not respond within'});

isConnect = contains(idText, {'connectionrefused', 'unknownhost', 'couldnotconnect', ...
        'connectionfailed', 'hostnotfound', 'couldntconnect', 'couldnotresolve', ...
        'cannotconnect', 'noconnection'}) || ...
    contains(msgText, {'connection refused', 'could not establish', 'could not resolve', ...
        'unknown host', 'failed to connect', 'could not connect', 'couldn''t connect', ...
        'couldn''t resolve', 'name or service not known', 'no such host', ...
        'actively refused', 'host not found'});

isHttp = isa(ME, 'matlab.net.http.HTTPException') || ...
    contains(idText, {'matlab:webservices', 'matlab:http', 'matlab.net'});

isTransport = true;
if isTimeout && (isHttp || isConnect || contains(idText, 'webservices'))
    result = openalgo.internal.errorResult( ...
        'Request timed out. The server took too long to respond.', 'timeout_error');
elseif isConnect && isHttp
    result = openalgo.internal.errorResult( ...
        'Failed to connect to the server. Please check if the server is running.', ...
        'connection_error');
elseif isHttp
    result = openalgo.internal.errorResult( ...
        ['HTTP error occurred: ' ME.message], 'http_error');
else
    isTransport = false;
    result = openalgo.internal.errorResult( ...
        ['An unexpected error occurred: ' ME.message], 'unknown_error');
end
end

function [ids, msgs] = collect(ME)
% Identifiers and messages of ME and every exception it wraps.
ids = {ME.identifier};
msgs = {ME.message};
try
    causes = ME.cause;
catch
    causes = {};
end
for i = 1:numel(causes)
    [ci, cm] = collect(causes{i});
    ids = [ids, ci]; %#ok<AGROW>
    msgs = [msgs, cm]; %#ok<AGROW>
end
if isa(ME, 'matlab.net.http.HTTPException')
    try
        hist = ME.History;
        for i = 1:numel(hist)
            ex = hist(i).Exception;
            if ~isempty(ex) && isa(ex, 'MException')
                [ci, cm] = collect(ex);
                ids = [ids, ci]; %#ok<AGROW>
                msgs = [msgs, cm]; %#ok<AGROW>
            end
        end
    catch
    end
end
end
