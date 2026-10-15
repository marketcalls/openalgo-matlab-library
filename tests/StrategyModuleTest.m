classdef StrategyModuleTest < RestTestCase
    %STRATEGYMODULETEST Strategy module methods (POST /api/v1/strategy/...).

    methods (Test)
        function strategylist(tc)
            tc.Client.strategylist();
            tc.verifySinglePost('strategy/list', '{"apikey":"test-api-key"}');
            tc.Server.reset();
            tc.Client.strategylist(status="running", q="iron", extra=[], x=2);
            tc.verifySinglePost('strategy/list', '{"apikey":"test-api-key","status":"running","q":"iron","x":2}');
        end

        function strategyIdIsAnInteger(tc)
            tc.Client.strategystatus(strategy_id="12");
            tc.verifySinglePost('strategy/status', '{"apikey":"test-api-key","strategy_id":12}');
            tc.Server.reset();
            tc.Client.strategystatus(strategy_id=12.7);   % int() truncates
            tc.verifySinglePost('strategy/status', '{"apikey":"test-api-key","strategy_id":12}');
            tc.verifyError(@() tc.Client.strategystatus(strategy_id="abc"), 'openalgo:valueError');
            tc.verifyError(@() tc.Client.strategystatus(), 'openalgo:missingArgument');
            tc.verifyError(@() tc.Client.strategystatus(12), 'openalgo:invalidArguments');
        end

        function strategystartModeIsRequiredAndUnchanged(tc)
            tc.Client.strategystart(strategy_id=12, mode="Sandbox");
            tc.verifySinglePost('strategy/start', '{"apikey":"test-api-key","strategy_id":12,"mode":"Sandbox"}');
            tc.verifyError(@() tc.Client.strategystart(strategy_id=12), 'openalgo:missingArgument');
        end

        function stopPassesThrough409(tc)
            tc.respond(['{"status":"error","message":"Stop pending","stop_pending":true,' ...
                '"exits":[{"leg_id":1,"ok":false}]}'], 409);
            r = tc.Client.strategystop(strategy_id=12);
            tc.verifySinglePost('strategy/stop', '{"apikey":"test-api-key","strategy_id":12}');
            tc.verifyEqual(r.status, 'error');
            tc.verifyEqual(r.code, 409);
            tc.verifyTrue(r.stop_pending);
            tc.verifyEqual(r.exits, struct('leg_id', 1, 'ok', false));
        end

        function notFoundPassesThrough(tc)
            tc.respond('{"status":"error","message":"Strategy not found"}', 404);
            r = tc.Client.strategystatus(strategy_id=99);
            tc.verifyEqual(r, struct('status', 'error', 'message', 'Strategy not found', 'code', 404));
        end

        function successBody(tc)
            tc.respond(['{"status":"success","run_id":5,"mode":"sandbox","legs":[' ...
                '{"leg_id":1,"ok":true,"acknowledged":true,"symbol":"A","broker_order_id":"x","error":null},' ...
                '{"leg_id":2,"ok":false,"acknowledged":false,"symbol":"B","broker_order_id":null,"error":"rejected"}]}']);
            r = tc.Client.strategystart(strategy_id=1, mode="sandbox");
            tc.verifyEqual(r.run_id, 5);
            tc.verifyFalse(isfield(r, 'code'));
            tc.verifyClass(r.legs, 'struct');
            tc.verifyEqual([r.legs.leg_id], [1 2]);
        end

        function closeAllAndCloseLeg(tc)
            tc.Client.strategycloseall(strategy_id=3);
            tc.verifySinglePost('strategy/close_all', '{"apikey":"test-api-key","strategy_id":3}');
            tc.Server.reset();
            tc.Client.strategycloseleg(strategy_id=3, leg_id="7");
            tc.verifySinglePost('strategy/close_leg', '{"apikey":"test-api-key","strategy_id":3,"leg_id":7}');
            tc.verifyError(@() tc.Client.strategycloseleg(strategy_id=3), 'openalgo:missingArgument');
        end

        function runsOrdersEvents(tc)
            tc.Client.strategyruns(strategy_id=3, limit=50);
            tc.verifySinglePost('strategy/runs', '{"apikey":"test-api-key","strategy_id":3,"limit":50}');
            tc.Server.reset();
            tc.Client.strategyruns(strategy_id=3);
            tc.verifySinglePost('strategy/runs', '{"apikey":"test-api-key","strategy_id":3}');
            tc.Server.reset();
            tc.Client.strategyorders(strategy_id=3, run_id=9);
            tc.verifySinglePost('strategy/orders', '{"apikey":"test-api-key","strategy_id":3,"run_id":9}');
            tc.Server.reset();
            tc.Client.strategyevents(strategy_id=3, kind="run_stop_failed", severity="critical", limit=10);
            tc.verifySinglePost('strategy/events', ['{"apikey":"test-api-key","strategy_id":3,' ...
                '"kind":"run_stop_failed","severity":"critical","limit":10}']);
            tc.Server.reset();
            tc.Client.strategyevents(strategy_id=3);
            tc.verifySinglePost('strategy/events', '{"apikey":"test-api-key","strategy_id":3}');
        end

        function transportErrors(tc)
            dead = openalgo.api(api_key="k", host=tc.Server.ClosedUrl);
            r = dead.strategylist();
            tc.verifyErrorStruct(r, 'connection_error', ...
                'Failed to connect to the server. Please check if the server is running.');
        end
    end
end
