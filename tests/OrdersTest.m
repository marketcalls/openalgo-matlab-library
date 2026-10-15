classdef OrdersTest < RestTestCase
    %ORDERSTEST Order methods: payloads, defaults, kwargs and argument errors.
    %   Expected bodies are the exact JSON the Python SDK 2.0.5 sends.

    methods (Test)
        function placeorderDefaults(tc)
            tc.respond('{"status":"success","orderid":"250101000001"}');
            r = tc.Client.placeorder(symbol="SBIN", action="BUY", exchange="NSE");
            tc.verifySinglePost('placeorder', ['{"apikey":"test-api-key","strategy":"Python",' ...
                '"symbol":"SBIN","action":"BUY","exchange":"NSE","pricetype":"MARKET",' ...
                '"product":"MIS","quantity":"1"}']);
            tc.verifyEqual(r, struct('status', 'success', 'orderid', '250101000001'));
        end

        function placeorderKwargsAreStringified(tc)
            tc.Client.placeorder(strategy="Test", symbol="SBIN", action="BUY", exchange="NSE", ...
                price_type="LIMIT", product="CNC", quantity=100000, price=750.5, ...
                trigger_price=0, disclosed_quantity=[], flag=true, ratio=0.1 + 0.2, big=10000000);
            tc.verifySinglePost('placeorder', ['{"apikey":"test-api-key","strategy":"Test",' ...
                '"symbol":"SBIN","action":"BUY","exchange":"NSE","pricetype":"LIMIT",' ...
                '"product":"CNC","quantity":"100000","price":"750.5","trigger_price":"0",' ...
                '"flag":"True","ratio":"0.30000000000000004","big":"10000000"}']);
        end

        function placeorderQuantityAsText(tc)
            tc.Client.placeorder(symbol="SBIN", action="SELL", exchange="NSE", quantity="10");
            tc.verifySinglePost('placeorder', ['{"apikey":"test-api-key","strategy":"Python",' ...
                '"symbol":"SBIN","action":"SELL","exchange":"NSE","pricetype":"MARKET",' ...
                '"product":"MIS","quantity":"10"}']);
        end

        function placeorderStringScalarsAndIntegers(tc)
            % string scalars and integer classes encode like char and Python int
            tc.Client.placeorder(symbol='SBIN', action="BUY", exchange='NSE', quantity=int32(7), ...
                price=single(1.5));
            r = tc.Server.lastRequest();
            tc.verifyTrue(contains(r.body, '"quantity":"7","price":"1.5"'));
        end

        function placeorderArgumentErrors(tc)
            c = tc.Client;
            tc.verifyError(@() c.placeorder(symbol="SBIN"), 'openalgo:missingArgument');
            try
                c.placeorder(symbol="SBIN");
            catch ME
                tc.verifySubstring(ME.message, ...
                    'missing 2 required keyword-only arguments: ''action'' and ''exchange''');
            end
            tc.verifyError(@() c.placeorder("SBIN", action="BUY", exchange="NSE"), ...
                'openalgo:invalidArguments');
            dup = @() c.placeorder(symbol="SBIN", symbol="X", action="BUY", exchange="NSE"); %#ok<DUPNAMEARG>
            tc.verifyError(dup, 'openalgo:duplicateArgument');
            tc.verifyError(@() c.placeorder(Symbol="SBIN", action="BUY", exchange="NSE"), ...
                'openalgo:missingArgument');   % names are case-sensitive
            tc.verifyNoRequest();
        end

        function placesmartorder(tc)
            tc.Client.placesmartorder(symbol="TATAMOTORS", action="SELL", exchange="NSE", ...
                quantity=1, position_size=0, price_type="LIMIT", price=900);
            tc.verifySinglePost('placesmartorder', ['{"apikey":"test-api-key","strategy":"Python",' ...
                '"symbol":"TATAMOTORS","action":"SELL","exchange":"NSE","pricetype":"LIMIT",' ...
                '"product":"MIS","quantity":"1","position_size":"0","price":"900"}']);
            tc.verifyError(@() tc.Client.placesmartorder(symbol="A", action="BUY", exchange="NSE"), ...
                'openalgo:missingArgument');
        end

        function basketorderCellOfStructs(tc)
            orders = {struct('symbol', 'BHEL', 'exchange', 'NSE', 'action', 'BUY', 'quantity', 1, ...
                        'pricetype', 'MARKET', 'product', 'MIS'), ...
                      struct('symbol', 'ZOMATO', 'exchange', 'NSE', 'action', 'SELL', ...
                        'quantity', '2', 'price', 10.5, 'flag', true)};
            tc.Client.basketorder(orders=orders, tag=7);
            tc.verifySinglePost('basketorder', ['{"apikey":"test-api-key","strategy":"Python",' ...
                '"orders":[{"symbol":"BHEL","exchange":"NSE","action":"BUY","quantity":"1",' ...
                '"pricetype":"MARKET","product":"MIS"},{"symbol":"ZOMATO","exchange":"NSE",' ...
                '"action":"SELL","quantity":"2","price":"10.5","flag":"True"}],"tag":"7"}']);
        end

        function basketorderOneOrderIsStillAnArray(tc)
            expected = ['{"apikey":"test-api-key","strategy":"S","orders":[{"symbol":"BHEL",' ...
                '"exchange":"NSE","action":"BUY","quantity":"1"}]}'];
            one = struct('symbol', 'BHEL', 'exchange', 'NSE', 'action', 'BUY', 'quantity', 1);
            tc.Client.basketorder(strategy="S", orders=one);          % 1x1 struct array
            tc.verifySinglePost('basketorder', expected);
            tc.Server.reset();
            tc.Client.basketorder(strategy="S", orders={one});        % 1x1 cell
            tc.verifySinglePost('basketorder', expected);
            tc.Server.reset();
            two = struct('symbol', {'A', 'B'}, 'exchange', 'NSE', 'action', 'BUY', 'quantity', 1);
            tc.Client.basketorder(orders=two);                        % 1x2 struct array
            r = tc.Server.lastRequest();
            tc.verifySubstring(r.body, '"orders":[{"symbol":"A",');
            tc.verifySubstring(r.body, '},{"symbol":"B",');
        end

        function basketorderRejectsNonList(tc)
            % Python: TypeError 'NoneType' object is not iterable
            tc.verifyError(@() tc.Client.basketorder(orders=[]), 'openalgo:typeError');
            tc.verifyError(@() tc.Client.basketorder(orders='x'), 'openalgo:typeError');
            tc.verifyError(@() tc.Client.basketorder(orders={1}), 'openalgo:typeError');
            tc.verifyError(@() tc.Client.basketorder(), 'openalgo:missingArgument');
            tc.verifyNoRequest();
        end

        function splitorder(tc)
            tc.Client.splitorder(symbol="YESBANK", exchange="NSE", action="SELL", quantity=105, ...
                splitsize=20, price=16.25);
            tc.verifySinglePost('splitorder', ['{"apikey":"test-api-key","strategy":"Python",' ...
                '"symbol":"YESBANK","action":"SELL","exchange":"NSE","quantity":"105",' ...
                '"splitsize":"20","pricetype":"MARKET","product":"MIS","price":"16.25"}']);
        end

        function orderstatus(tc)
            tc.Client.orderstatus(order_id="24120900146469", strategy="Test Strategy", extra=5);
            tc.verifySinglePost('orderstatus', ['{"apikey":"test-api-key","strategy":"Test Strategy",' ...
                '"orderid":"24120900146469","extra":"5"}']);
            tc.verifyError(@() tc.Client.orderstatus(), 'openalgo:missingArgument');
        end

        function openposition(tc)
            tc.Client.openposition(symbol="YESBANK", exchange="NSE", product="CNC");
            tc.verifySinglePost('openposition', ['{"apikey":"test-api-key","strategy":"Python",' ...
                '"symbol":"YESBANK","exchange":"NSE","product":"CNC"}']);
        end

        function modifyorderDefaults(tc)
            tc.Client.modifyorder(order_id="24120900146469", symbol="YESBANK", action="BUY", ...
                exchange="NSE", product="CNC", quantity=1, price=16.5);
            tc.verifySinglePost('modifyorder', ['{"apikey":"test-api-key","orderid":"24120900146469",' ...
                '"strategy":"Python","symbol":"YESBANK","action":"BUY","exchange":"NSE",' ...
                '"pricetype":"LIMIT","product":"CNC","quantity":"1","price":"16.5",' ...
                '"disclosed_quantity":"0","trigger_price":"0"}']);
        end

        function modifyorderAllFields(tc)
            % order_id is sent as given (a number stays a number, as in Python)
            tc.Client.modifyorder(order_id=123, strategy="S", symbol="YESBANK", action="BUY", ...
                exchange="NSE", price_type="SL", product="MIS", quantity="5", price="16.5", ...
                disclosed_quantity=1, trigger_price=16.4, tag="x");
            tc.verifySinglePost('modifyorder', ['{"apikey":"test-api-key","orderid":123,' ...
                '"strategy":"S","symbol":"YESBANK","action":"BUY","exchange":"NSE",' ...
                '"pricetype":"SL","product":"MIS","quantity":"5","price":"16.5",' ...
                '"disclosed_quantity":"1","trigger_price":"16.4","tag":"x"}']);
            tc.verifyError(@() tc.Client.modifyorder(order_id="1", symbol="A", action="BUY", ...
                exchange="NSE", product="CNC", quantity=1), 'openalgo:missingArgument');
        end

        function cancelorder(tc)
            tc.Client.cancelorder(order_id="24120900146469");
            tc.verifySinglePost('cancelorder', ['{"apikey":"test-api-key",' ...
                '"orderid":"24120900146469","strategy":"Python"}']);
        end

        function closeposition(tc)
            tc.Client.closeposition(strategy="Test Strategy");
            tc.verifySinglePost('closeposition', '{"apikey":"test-api-key","strategy":"Test Strategy"}');
        end

        function cancelallorderSkipsNoneKwargs(tc)
            tc.Client.cancelallorder(note=[], n=3);
            tc.verifySinglePost('cancelallorder', '{"apikey":"test-api-key","strategy":"Python","n":"3"}');
        end

        function apiErrorIsReturned(tc)
            tc.respond('{"status":"error","message":"Insufficient funds"}');
            r = tc.Client.placeorder(symbol="SBIN", action="BUY", exchange="NSE");
            tc.verifyEqual(r, struct('status', 'error', 'message', 'Insufficient funds', ...
                'code', 200, 'error_type', 'api_error'));
        end
    end
end
