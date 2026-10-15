function [code, text] = httpRequest(method, url, body, timeout, headers, query, segment)
%HTTPREQUEST Send one HTTP request with matlab.net.http and return the raw answer.
%   [CODE, TEXT] = openalgo.internal.httpRequest(METHOD, URL, BODY, TIMEOUT,
%   HEADERS, QUERY) sends METHOD ('POST' or 'GET') to URL.
%
%     BODY     JSON text sent as UTF-8 bytes, or [] for no body.
%     TIMEOUT  seconds, used for the connect and the response timeouts
%              ([] keeps the matlab.net.http defaults).
%     HEADERS  dictionary, containers.Map or struct of header names and
%              values, or [] for none.
%     QUERY    struct of query parameters, or [] for none.
%     SEGMENT  optional extra path segment appended to URL as one segment
%              (characters that are not allowed in a segment, such as a
%              space, %, / or ?, are percent-encoded; others go as is).
%
%   CODE is the numeric HTTP status and TEXT the body decoded as UTF-8.
%   Automatic response conversion is disabled, so TEXT is always the body
%   exactly as received. Redirects are not followed (as in the Python
%   client). Transport failures are raised as MATLAB exceptions; map them
%   with openalgo.internal.transportError.

if nargin < 5
    headers = [];
end
if nargin < 6
    query = [];
end
if nargin < 7
    segment = [];
end

uri = matlab.net.URI(char(url));
if ~isempty(segment)
    uri.Path(end+1) = string(segment);
end
if ~isempty(query) && isstruct(query) && ~isempty(fieldnames(query))
    f = fieldnames(query);
    qp = matlab.net.QueryParameter.empty;
    for i = 1:numel(f)
        value = query.(f{i});
        if openalgo.internal.isNone(value)
            continue   % None query values are left out, as httpx does
        elseif islogical(value) && isscalar(value)
            qtext = 'false';
            if value
                qtext = 'true';   % httpx writes booleans in lower case
            end
        else
            qtext = openalgo.internal.pyStr(value);
        end
        qp(end+1) = matlab.net.QueryParameter(f{i}, qtext); %#ok<AGROW>
    end
    if ~isempty(qp)
        uri.Query = qp;
    end
end

fields = matlab.net.http.HeaderField.empty;
[names, values] = headerPairs(headers);
hasUserAgent = false;
for i = 1:numel(names)
    if strcmpi(names{i}, 'Content-Type')
        fields(end+1) = matlab.net.http.field.ContentTypeField(values{i}); %#ok<AGROW>
    else
        fields(end+1) = matlab.net.http.HeaderField(names{i}, values{i}); %#ok<AGROW>
    end
    if strcmpi(names{i}, 'User-Agent')
        hasUserAgent = true;
    end
end
if ~hasUserAgent
    fields(end+1) = matlab.net.http.HeaderField('User-Agent', ['openalgo-matlab/' openalgo.version()]);
end

msgBody = [];
if ~isempty(body)
    if ~any(strcmpi(names, 'Content-Type'))
        fields(end+1) = matlab.net.http.field.ContentTypeField('application/json');
    end
    msgBody = matlab.net.http.MessageBody();
    msgBody.Payload = unicode2native(char(body), 'UTF-8');
end

req = matlab.net.http.RequestMessage(upper(char(method)), fields, msgBody);
opts = buildOptions(timeout);
resp = send(req, uri, opts);

code = double(resp.StatusCode);
text = bodyText(resp.Body);
end

function opts = buildOptions(timeout)
opts = matlab.net.http.HTTPOptions();
opts.ConvertResponse = false;
opts.MaxRedirects = 0;
try %#ok<TRYNC>
    opts.SavePayload = true;
end
if ~isempty(timeout) && isnumeric(timeout) && isscalar(timeout) && timeout > 0
    t = double(timeout);
    opts.ConnectTimeout = t;
    try %#ok<TRYNC>
        opts.ResponseTimeout = t;
    end
    try %#ok<TRYNC>
        opts.DataTimeout = t;
    end
end
end

function [names, vals] = headerPairs(headers)
names = {};
vals = {};
if isa(headers, 'dictionary')
    if ~isConfigured(headers) || numEntries(headers) == 0
        return
    end
    names = reshape(cellstr(string(keys(headers))), 1, []);
    vals = reshape(cellstr(string(values(headers))), 1, []);
elseif isempty(headers)
    return
elseif isa(headers, 'containers.Map')
    names = keys(headers);
    vals = cellfun(@(v) char(string(v)), values(headers), 'UniformOutput', false);
elseif isstruct(headers)
    names = fieldnames(headers)';
    vals = cellfun(@(f) char(string(headers.(f))), names, 'UniformOutput', false);
end
end

function text = bodyText(body)
text = '';
if isempty(body)
    return
end
data = body.Data;
if ischar(data)
    text = data;
elseif isstring(data)
    text = char(strjoin(data, ''));
elseif isa(data, 'uint8') || isa(data, 'int8')
    text = native2unicode(reshape(uint8(data), 1, []), 'UTF-8');
end
if isempty(text)
    payload = [];
    try
        payload = body.Payload;
    catch
    end
    if ~isempty(payload)
        text = native2unicode(reshape(uint8(payload), 1, []), 'UTF-8');
    end
end
if isempty(text)
    text = '';
end
end
