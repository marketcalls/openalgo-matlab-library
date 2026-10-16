function result = parsePostResponse(code, text, nonJsonAsHttp)
%PARSEPOSTRESPONSE Response handling of BaseAPI.post and Strategy.send.
%   RESULT = openalgo.internal.parsePostResponse(CODE, TEXT, NONJSONASHTTP)
%   returns the decoded JSON object. A non-200 answer whose body is a JSON
%   object is returned as is, with status set to 'error' when the server
%   did not send one and code attached, because the strategy and GTT
%   surfaces put what a caller must act on inside that body.
%
%   A body that is not JSON gives an http_error 'HTTP <code>: <body>' when
%   the status is not 200 (or always, when NONJSONASHTTP is true, as in
%   Strategy.send), otherwise a json_error. A JSON value that is not an
%   object gives a json_error 'Unexpected JSON response from server'.

if nargin < 3
    nonJsonAsHttp = false;
end

[ok, data, typeName] = openalgo.internal.decodeJson(text);
if ~ok
    if code ~= 200 || nonJsonAsHttp
        result = openalgo.internal.errorResult(sprintf('HTTP %d: %s', code, text), ...
            'http_error', 'raw_response', text, 'code', code);
    else
        result = openalgo.internal.errorResult('Invalid JSON response from server', ...
            'json_error', 'raw_response', text, 'code', code);
    end
    return
end

if ~strcmp(typeName, 'dict')
    result = openalgo.internal.errorResult('Unexpected JSON response from server', ...
        'json_error', 'raw_response', data, 'code', code);
    return
end

if code ~= 200
    % status is set to 'error' and appended only when it is absent.
    if ~isfield(data, 'status')
        data.status = 'error';
    end
    data.code = code;
end
result = data;
end
