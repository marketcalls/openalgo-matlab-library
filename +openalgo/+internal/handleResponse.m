function result = handleResponse(code, text)
%HANDLERESPONSE Turn an HTTP status and body into the SDK result struct.
%   RESULT = openalgo.internal.handleResponse(CODE, TEXT) mirrors the Python
%   OrderAPI._handle_response, which the unified client uses for every
%   order, data, account, options, notification and utilities call:
%
%     status ~= 200             -> http_error 'HTTP <code>: <body>' with code
%     body is not JSON          -> json_error with raw_response
%     JSON is not an object     -> unknown_error "'list' object has no attribute 'get'"
%     JSON status == "error"    -> api_error with message and code
%     otherwise                 -> the decoded JSON object

if code ~= 200
    result = openalgo.internal.errorResult(sprintf('HTTP %d: %s', code, text), ...
        'http_error', 'code', code);
    return
end

[ok, data, typeName] = openalgo.internal.decodeJson(text);
if ~ok
    result = openalgo.internal.errorResult('Invalid JSON response from server', ...
        'json_error', 'raw_response', text);
    return
end

if ~strcmp(typeName, 'dict')
    % Python calls data.get(...) on a non-dict and reports the AttributeError.
    result = openalgo.internal.errorResult( ...
        sprintf('''%s'' object has no attribute ''get''', typeName), 'unknown_error');
    return
end

if isfield(data, 'status') && openalgo.internal.textEquals(data.status, 'error')
    if isfield(data, 'message')
        msg = data.message;
    else
        msg = 'Unknown error';
    end
    result = openalgo.internal.errorResult(msg, 'api_error', 'code', code);
    return
end

result = data;
end
