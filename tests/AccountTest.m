classdef AccountTest < RestTestCase
    %ACCOUNTTEST Account methods, analyzer toggle and margin processing.

    methods (Test)
        function booksSendTheApiKeyAndKwargs(tc)
            names = {'funds', 'orderbook', 'tradebook', 'positionbook', 'holdings'};
            for i = 1:numel(names)
                tc.Server.reset();
                tc.Client.(names{i})();
                tc.verifySinglePost(names{i}, '{"apikey":"test-api-key"}');
            end
            tc.Server.reset();
            tc.Client.orderbook(x=1);
            tc.verifySinglePost('orderbook', '{"apikey":"test-api-key","x":1}');
            tc.verifyError(@() tc.Client.funds(1), 'openalgo:invalidArguments');
        end

        function fundsResponse(tc)
            tc.respond(['{"status":"success","data":{"availablecash":"320.66",' ...
                '"collateral":"0.00","m2mrealized":"3.27","m2munrealized":"-7.88","utiliseddebits":"679.34"}}']);
            r = tc.Client.funds();
            tc.verifyEqual(r.status, 'success');
            tc.verifyEqual(r.data.availablecash, '320.66');
        end

        function analyzerStatusAndToggle(tc)
            tc.Client.analyzerstatus();
            tc.verifySinglePost('analyzer', '{"apikey":"test-api-key"}');
            tc.Server.reset();
            tc.Client.analyzertoggle(true);
            tc.verifySinglePost('analyzer/toggle', '{"apikey":"test-api-key","mode":true}');
            tc.Server.reset();
            tc.Client.analyzertoggle(mode=false);
            tc.verifySinglePost('analyzer/toggle', '{"apikey":"test-api-key","mode":false}');
            tc.verifyError(@() tc.Client.analyzertoggle(), 'openalgo:missingArgument');
            try
                tc.Client.analyzertoggle();
            catch ME
                tc.verifySubstring(ME.message, 'missing 1 required positional argument: ''mode''');
            end
            tc.verifyError(@() tc.Client.analyzertoggle(true, mode=false), 'openalgo:duplicateArgument');
        end

        function marginProcessesPositions(tc)
            pos = struct('symbol', 'SBIN', 'exchange', 'NSE', 'action', 'BUY', 'product', 'MIS', ...
                'pricetype', 'LIMIT', 'quantity', 10, 'price', 750.5, 'lots', 2);
            tc.Client.margin(positions=pos);   % one struct: still a JSON array
            tc.verifySinglePost('margin', ['{"apikey":"test-api-key","positions":[{"symbol":"SBIN",' ...
                '"exchange":"NSE","action":"BUY","product":"MIS","pricetype":"LIMIT","quantity":"10",' ...
                '"price":"750.5","lots":2,"trigger_price":"0"}]}']);
            tc.Server.reset();
            pos = struct('symbol', 'SBIN', 'quantity', '10', 'price', [], 'trigger_price', 1);
            tc.Client.margin(positions={pos});
            tc.verifySinglePost('margin', ['{"apikey":"test-api-key","positions":[{"symbol":"SBIN",' ...
                '"quantity":"10","price":null,"trigger_price":"1"}]}']);
        end

        function marginValidation(tc)
            c = tc.Client;
            tc.verifyEqual(c.margin(positions=[]), struct('status', 'error', ...
                'message', 'Positions must be an array', 'error_type', 'validation_error'));
            tc.verifyErrorStruct(c.margin(positions="SBIN"), 'validation_error', 'Positions must be an array');
            tc.verifyErrorStruct(c.margin(positions={}), 'validation_error', 'Positions array cannot be empty');
            many = repmat({struct('symbol', 'x')}, 1, 51);
            tc.verifyErrorStruct(c.margin(positions=many), 'validation_error', 'Maximum 50 positions allowed');
            tc.verifyNoRequest();
            c.margin(positions=many(1:50));
            r = tc.Server.lastRequest();
            tc.verifyNumElements(jsondecode(r.body).positions, 50);
        end
    end
end
