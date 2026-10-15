classdef BaseAPI < handle
%BASEAPI Base class that handles the REST calls to OpenAlgo.
%   BaseAPI holds the client configuration and the request helpers shared
%   by every REST method. You normally do not create it directly: use
%   openalgo.api, which inherits from it.
%
%   OBJ = openalgo.BaseAPI(api_key, host, version, timeout) or with
%   name=value arguments:
%
%     api_key  - User's API key. Required.
%     host     - Base URL for the API endpoints. Default
%                "http://127.0.0.1:5000".
%     version  - API version. Default "v1".
%     timeout  - Request timeout in seconds. Default 120.
%
%   BaseAPI properties:
%     api_key  - User's API key.
%     base_url - REST base URL, "{host}/api/{version}/".
%     headers  - Headers sent with every POST (a dictionary), by default
%                Content-Type: application/json.
%     timeout  - Request timeout in seconds (connect and response).
%
%   BaseAPI methods:
%     close    - Release the HTTP resources. Later REST calls return an
%                unknown_error, as in the Python SDK after close().
%
%   Every REST call returns a struct and never raises for server or
%   network problems: failures come back as a struct with status 'error',
%   a message and an error_type (http_error, json_error, api_error,
%   timeout_error, connection_error, unknown_error, validation_error,
%   no_data or processing_error).
%
%   See also openalgo.api, openalgo.Strategy.

    properties
        %API_KEY User's API key.
        api_key
        %BASE_URL REST base URL, "{host}/api/{version}/".
        base_url
        %HEADERS Headers sent with every POST request (dictionary).
        headers
        %TIMEOUT Request timeout in seconds.
        timeout
    end

    properties (Access = private, Hidden)
        RestClientClosed = false
    end

    methods
        function obj = BaseAPI(varargin)
            %BASEAPI Initialize the client configuration.
            %   OBJ = openalgo.BaseAPI(api_key, host="http://127.0.0.1:5000",
            %   version="v1", timeout=120)
            if nargin == 0
                return
            end
            a = openalgo.internal.parseArgs('BaseAPI', varargin, ...
                {'api_key', []; 'host', 'http://127.0.0.1:5000'; 'version', 'v1'; 'timeout', 120.0}, ...
                {'api_key'}, 4, false);
            obj.api_key = a.api_key;
            obj.base_url = [openalgo.internal.pyStr(a.host) '/api/' openalgo.internal.pyStr(a.version) '/'];
            obj.headers = dictionary("Content-Type", "application/json");
            obj.timeout = a.timeout;
        end

        function close(obj)
            %CLOSE Release the HTTP resources used by the REST methods.
            %   CLIENT.CLOSE() mirrors the Python close(). MATLAB opens a
            %   connection per request, so there is no pool to drain; after
            %   close() every REST call returns the error the Python SDK
            %   returns on a closed client.
            obj.RestClientClosed = true;
        end
    end

    methods (Access = protected)
        function result = makeRequest(obj, endpoint, payload)
            %MAKEREQUEST POST a JSON payload and run it through handleResponse.
            %   RESULT = makeRequest(OBJ, ENDPOINT, PAYLOAD) is the Python
            %   OrderAPI._make_request plus _handle_response. Transport
            %   failures become timeout_error, connection_error, http_error
            %   or unknown_error structs.
            url = [obj.base_url char(endpoint)];
            try
                body = openalgo.internal.toJson(payload);
                [code, text] = obj.sendHttp('POST', url, body, obj.headers, []);
            catch ME
                result = openalgo.internal.transportError(ME);
                return
            end
            result = openalgo.internal.handleResponse(code, text);
        end

        function result = post(obj, endpoint, payload)
            %POST POST a JSON payload and return the parsed body.
            %   RESULT = post(OBJ, ENDPOINT, PAYLOAD) is the Python
            %   BaseAPI._post used by the GTT and strategy module methods.
            %   A non-200 answer with a JSON object body is returned as is,
            %   with status defaulted to 'error' and code attached.
            url = [obj.base_url char(endpoint)];
            try
                body = openalgo.internal.toJson(payload);
                [code, text] = obj.sendHttp('POST', url, body, obj.headers, []);
            catch ME
                result = openalgo.internal.transportError(ME);
                return
            end
            result = openalgo.internal.parsePostResponse(code, text, false);
        end

        function result = getRequest(obj, endpoint, params)
            %GETREQUEST GET with query parameters and run it through handleResponse.
            %   RESULT = getRequest(OBJ, ENDPOINT, PARAMS) sends PARAMS (a
            %   struct) as the query string, without the JSON headers, as the
            %   Python client.get call does. Transport failures are mapped
            %   to the same error structs as makeRequest.
            [code, text, err] = obj.getRequestRaw(endpoint, params);
            if ~isempty(err)
                result = err;
                return
            end
            result = openalgo.internal.handleResponse(code, text);
        end

        function [code, text, err] = getRequestRaw(obj, endpoint, params, segment)
            %GETREQUESTRAW GET with query parameters, returning the raw answer.
            %   [CODE, TEXT, ERR] = getRequestRaw(OBJ, ENDPOINT, PARAMS)
            %   returns the HTTP status and body text. On a transport
            %   failure CODE is [], TEXT is '' and ERR is the mapped error
            %   struct (as in makeRequest); otherwise ERR is [].
            %   getRequestRaw(OBJ, ENDPOINT, PARAMS, SEGMENT) appends SEGMENT
            %   to the URL as one path segment (encoded where needed).
            if nargin < 4
                segment = [];
            end
            url = [obj.base_url char(endpoint)];
            err = [];
            try
                [code, text] = obj.sendHttp('GET', url, [], [], params, segment);
            catch ME
                code = [];
                text = '';
                err = openalgo.internal.transportError(ME);
            end
        end

        function [code, text] = sendHttp(obj, method, url, body, headers, query, segment)
            %SENDHTTP Send one request, refusing once the client is closed.
            if nargin < 7
                segment = [];
            end
            if obj.RestClientClosed
                error('openalgo:clientClosed', ...
                    'Cannot send a request, as the client has been closed.');
            end
            timeoutValue = obj.timeout;
            if ~isnumeric(timeoutValue)
                timeoutValue = [];
            end
            [code, text] = openalgo.internal.httpRequest(method, url, body, timeoutValue, headers, query, segment);
        end
    end
end
