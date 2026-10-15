classdef (Abstract) RestTestCase < matlab.unittest.TestCase
    %RESTTESTCASE Base class of the REST test classes.
    %   Starts tests/support/mock_http_server.py once per test class on a
    %   free port (TestClassSetup), stops it in the class teardown, resets it
    %   before every test and creates a fresh client (tc.Client) pointing at
    %   it. Request bodies are compared as raw JSON text, so key order,
    %   number formatting and value types (strings, numbers, true/false,
    %   null, arrays) are all checked exactly. The expected bodies are the
    %   ones the Python SDK 2.0.5 sends for the same call.

    properties (Constant)
        ApiKey = 'test-api-key'
    end

    properties
        Server
        Client
    end

    methods (TestClassSetup)
        function startMockServer(tc)
            support = fileparts(mfilename('fullpath'));
            root = fileparts(fileparts(support));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(root));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(support));
            tc.Server = MockHttpServer();
            tc.addTeardown(@() tc.Server.stop());
            tc.Server.start();
        end
    end

    methods (TestMethodSetup)
        function resetMockServer(tc)
            tc.Server.reset();
            tc.Client = openalgo.api(api_key=tc.ApiKey, host=tc.Server.Url);
        end
    end

    methods
        function respond(tc, body, status)
            %RESPOND Queue a JSON answer for the next request.
            if nargin < 3
                status = 200;
            end
            tc.Server.respond(body, status);
        end

        function respondText(tc, body, status)
            if nargin < 3
                status = 200;
            end
            tc.Server.respondText(body, status);
        end

        function r = verifySinglePost(tc, endpoint, expectedBody)
            %VERIFYSINGLEPOST Exactly one POST to /api/v1/<endpoint> with this body.
            reqs = tc.Server.requests();
            tc.verifyNumElements(reqs, 1, 'Expected exactly one request');
            if isempty(reqs)
                r = [];
                return
            end
            r = reqs{end};
            tc.verifyEqual(r.method, 'POST');
            tc.verifyEqual(r.path, ['/api/v1/' endpoint]);
            tc.verifyEqual(r.raw_query, '');
            tc.verifyEqual(r.headers.content_type, 'application/json');
            tc.verifyEqual(r.body, expectedBody);
        end

        function r = verifySingleGet(tc, rawPath, expectedQuery)
            %VERIFYSINGLEGET Exactly one GET with this raw path and raw query.
            reqs = tc.Server.requests();
            tc.verifyNumElements(reqs, 1, 'Expected exactly one request');
            if isempty(reqs)
                r = [];
                return
            end
            r = reqs{end};
            tc.verifyEqual(r.method, 'GET');
            tc.verifyEqual(r.raw_path, rawPath);
            tc.verifyEqual(r.raw_query, expectedQuery);
            tc.verifyFalse(isfield(r.headers, 'content_type'), 'A GET must not send Content-Type');
            tc.verifyEqual(r.body, '');
        end

        function verifyNoRequest(tc)
            tc.verifyEmpty(tc.Server.requests(), 'No request should have been sent');
        end

        function verifyErrorStruct(tc, result, errorType, message)
            %VERIFYERRORSTRUCT A returned (not raised) SDK error struct.
            tc.verifyClass(result, 'struct');
            tc.verifyEqual(result.status, 'error');
            tc.verifyEqual(result.error_type, errorType);
            if nargin >= 4
                tc.verifyEqual(result.message, message);
            end
        end
    end

    methods (Static)
        function [msg, id] = lastWarningOf(fcn) %#ok<INUSD> used inside evalc
            %LASTWARNINGOF Message and identifier of the last warning FCN issues.
            %   The warning text is captured, so it does not clutter the log.
            lastwarn('');
            evalc('fcn();');
            [msg, id] = lastwarn();
        end
    end
end
