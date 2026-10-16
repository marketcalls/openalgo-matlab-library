classdef GTTTest < RestTestCase
    %GTTTEST GTT methods: numeric payloads, null legs, validation and the
    %   BaseAPI.post response handling (non-200 JSON bodies pass through).

    methods (Test)
        function singleDefaults(tc)
            tc.respond('{"status":"success","trigger_id":"GTT-1","mode":"analyze"}');
            r = tc.Client.placegttorder(symbol="SBIN", exchange="NSE", action="buy", quantity=1, ...
                price=700, triggerprice_sl=701);
            tc.verifySinglePost('placegttorder', ['{"apikey":"test-api-key","strategy":"MATLAB",' ...
                '"trigger_type":"SINGLE","exchange":"NSE","symbol":"SBIN","action":"BUY",' ...
                '"product":"CNC","quantity":1,"pricetype":"LIMIT","price":700.0,' ...
                '"triggerprice_sl":701.0,"triggerprice_tg":0.0,"stoploss":null,"target":null}']);
            tc.verifyEqual(r, struct('status', 'success', 'trigger_id', 'GTT-1', 'mode', 'analyze'));
        end

        function singleTargetTextValuesAndKwargs(tc)
            % lower case trigger type is upper-cased; text numbers become
            % numbers; extra fields pass through unchanged (true stays true)
            tc.Client.placegttorder(strategy="G", symbol="SBIN", exchange="NSE", action="SELL", ...
                trigger_type="single", product="NRML", quantity="2", price_type="MARKET", ...
                triggerprice_tg="850.5", tag="t", flag=true, n=5);
            tc.verifySinglePost('placegttorder', ['{"apikey":"test-api-key","strategy":"G",' ...
                '"trigger_type":"SINGLE","exchange":"NSE","symbol":"SBIN","action":"SELL",' ...
                '"product":"NRML","quantity":2,"pricetype":"MARKET","price":0.0,' ...
                '"triggerprice_sl":0.0,"triggerprice_tg":850.5,"stoploss":null,"target":null,' ...
                '"tag":"t","flag":true,"n":5}']);
        end

        function ocoWithFractionalQuantity(tc)
            tc.Client.placegttorder(symbol="SBIN", exchange="NSE", action="SELL", trigger_type="OCO", ...
                quantity=1.5, triggerprice_sl=700, stoploss=699, triggerprice_tg=850, target=849.25);
            tc.verifySinglePost('placegttorder', ['{"apikey":"test-api-key","strategy":"MATLAB",' ...
                '"trigger_type":"OCO","exchange":"NSE","symbol":"SBIN","action":"SELL",' ...
                '"product":"CNC","quantity":1.5,"pricetype":"LIMIT","price":0.0,' ...
                '"triggerprice_sl":700.0,"triggerprice_tg":850.0,"stoploss":699.0,"target":849.25}']);
        end

        function largeNumbersAreNotExponents(tc)
            tc.Client.placegttorder(symbol="SBIN", exchange="NSE", action="BUY", quantity=100000, ...
                price=0.1, triggerprice_sl=10000000);
            tc.verifySinglePost('placegttorder', ['{"apikey":"test-api-key","strategy":"MATLAB",' ...
                '"trigger_type":"SINGLE","exchange":"NSE","symbol":"SBIN","action":"BUY",' ...
                '"product":"CNC","quantity":100000,"pricetype":"LIMIT","price":0.1,' ...
                '"triggerprice_sl":10000000.0,"triggerprice_tg":0.0,"stoploss":null,"target":null}']);
        end

        function validationErrorsAreReturnedNotSent(tc)
            c = tc.Client;
            r = c.placegttorder(symbol="SBIN", exchange="NSE", action="BUY", trigger_type="TWO", ...
                triggerprice_sl=1);
            tc.verifyEqual(r, struct('status', 'error', ...
                'message', 'trigger_type must be ''SINGLE'' or ''OCO''.', 'error_type', 'validation_error'));
            r = c.placegttorder(symbol="SBIN", exchange="NSE", action="BUY", trigger_type="oco", ...
                triggerprice_sl=700, triggerprice_tg=0);
            tc.verifyErrorStruct(r, 'validation_error', 'Required for OCO: stoploss, triggerprice_tg, target.');
            r = c.placegttorder(symbol="SBIN", exchange="NSE", action="BUY", trigger_type="OCO", ...
                triggerprice_sl=900, stoploss=899, triggerprice_tg=850, target=849);
            tc.verifyErrorStruct(r, 'validation_error', ...
                'Stoploss trigger must be less than target trigger (triggerprice_sl < triggerprice_tg).');
            r = c.placegttorder(symbol="SBIN", exchange="NSE", action="BUY");
            tc.verifyErrorStruct(r, 'validation_error', ...
                'SINGLE GTT requires a positive triggerprice_sl or triggerprice_tg.');
            r = c.placegttorder(symbol="SBIN", exchange="NSE", action="BUY", triggerprice_sl=1, ...
                triggerprice_tg=2);
            tc.verifyErrorStruct(r, 'validation_error', ...
                'SINGLE GTT takes exactly one of triggerprice_sl or triggerprice_tg; set the other to 0.');
            r = c.modifygttorder(trigger_id="1", symbol="SBIN", exchange="NSE", action="BUY", ...
                triggerprice_sl="", triggerprice_tg=[]);   % "" and [] count as unset
            tc.verifyErrorStruct(r, 'validation_error', ...
                'SINGLE GTT requires a positive triggerprice_sl or triggerprice_tg.');
            tc.verifyNoRequest();
        end

        function conversionErrorsRaise(tc)
            % Text that is not a valid integer or number raises valueError
            tc.verifyError(@() tc.Client.placegttorder(symbol="SBIN", exchange="NSE", action="BUY", ...
                quantity="1.0", triggerprice_sl=1), 'openalgo:valueError');
            tc.verifyError(@() tc.Client.placegttorder(symbol="SBIN", exchange="NSE", action="BUY", ...
                triggerprice_sl="abc"), 'openalgo:valueError');
            tc.verifyError(@() tc.Client.placegttorder(symbol="SBIN", exchange="NSE"), ...
                'openalgo:missingArgument');
            tc.verifyNoRequest();
        end

        function modifyAppendsTriggerIdAsText(tc)
            tc.Client.modifygttorder(trigger_id=12345, symbol="SBIN", exchange="NSE", action="BUY", ...
                quantity=2, price=695, triggerprice_sl=696);
            tc.verifySinglePost('modifygttorder', ['{"apikey":"test-api-key","strategy":"MATLAB",' ...
                '"trigger_type":"SINGLE","exchange":"NSE","symbol":"SBIN","action":"BUY",' ...
                '"product":"CNC","quantity":2,"pricetype":"LIMIT","price":695.0,' ...
                '"triggerprice_sl":696.0,"triggerprice_tg":0.0,"stoploss":null,"target":null,' ...
                '"trigger_id":"12345"}']);
            tc.verifyError(@() tc.Client.modifygttorder(symbol="SBIN", exchange="NSE", action="BUY", ...
                triggerprice_sl=1), 'openalgo:missingArgument');
        end

        function cancelPassesExtraFieldsUnchanged(tc)
            tc.Client.cancelgttorder(trigger_id="GTT-1", note="x", n=1.5);
            tc.verifySinglePost('cancelgttorder', ['{"apikey":"test-api-key","strategy":"MATLAB",' ...
                '"trigger_id":"GTT-1","note":"x","n":1.5}']);
        end

        function orderbook(tc)
            tc.Client.gttorderbook();
            tc.verifySinglePost('gttorderbook', '{"apikey":"test-api-key"}');
            tc.Server.reset();
            tc.Client.gttorderbook(status="all");
            tc.verifySinglePost('gttorderbook', '{"apikey":"test-api-key","status":"all"}');
        end

        function non200JsonBodyPassesThroughWithCode(tc)
            tc.respond('{"status":"error","message":{"price":"must be positive"},"stop_pending":true}', 409);
            r = tc.Client.placegttorder(symbol="SBIN", exchange="NSE", action="BUY", triggerprice_sl=1);
            tc.verifyEqual(r.status, 'error');
            tc.verifyEqual(r.message, struct('price', 'must be positive'));
            tc.verifyEqual(r.stop_pending, true);
            tc.verifyEqual(r.code, 409);
            tc.verifyEqual(fieldnames(r), {'status'; 'message'; 'stop_pending'; 'code'});
            tc.verifyFalse(isfield(r, 'error_type'));
        end

        function non200WithoutStatusGetsErrorStatus(tc)
            tc.respond('{"message":"bad"}', 400);
            r = tc.Client.gttorderbook();
            tc.verifyEqual(r, struct('message', 'bad', 'status', 'error', 'code', 400));
        end

        function non200SuccessStatusIsKept(tc)
            tc.respond('{"status":"success","trigger_id":"T"}', 201);
            r = tc.Client.gttorderbook();
            tc.verifyEqual(r, struct('status', 'success', 'trigger_id', 'T', 'code', 201));
        end

        function nonJsonBodies(tc)
            tc.respondText('not json');
            r = tc.Client.gttorderbook();
            tc.verifyEqual(r, struct('status', 'error', 'message', 'Invalid JSON response from server', ...
                'raw_response', 'not json', 'code', 200, 'error_type', 'json_error'));
            tc.respondText('Bad Gateway', 502);
            r = tc.Client.gttorderbook();
            tc.verifyEqual(r, struct('status', 'error', 'message', 'HTTP 502: Bad Gateway', ...
                'raw_response', 'Bad Gateway', 'code', 502, 'error_type', 'http_error'));
        end

        function arrayBodyIsJsonError(tc)
            tc.respond('[1,2]');
            r = tc.Client.gttorderbook();
            tc.verifyEqual(r, struct('status', 'error', 'message', 'Unexpected JSON response from server', ...
                'raw_response', [1; 2], 'code', 200, 'error_type', 'json_error'));
        end

        function connectionRefused(tc)
            c = openalgo.api(api_key="k", host=tc.Server.ClosedUrl);
            r = c.gttorderbook();
            tc.verifyEqual(r, struct('status', 'error', 'message', ...
                'Failed to connect to the server. Please check if the server is running.', ...
                'error_type', 'connection_error'));
        end
    end
end
