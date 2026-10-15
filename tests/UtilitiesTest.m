classdef UtilitiesTest < RestTestCase
    %UTILITIESTEST Market calendar methods (holidays and timings).

    methods (Test)
        function holidays(tc)
            tc.Client.holidays();
            tc.verifySinglePost('market/holidays', '{"apikey":"test-api-key"}');
            tc.Server.reset();
            tc.Client.holidays(2025);
            tc.verifySinglePost('market/holidays', '{"apikey":"test-api-key","year":2025}');
            tc.Server.reset();
            tc.Client.holidays(year=2026);
            tc.verifySinglePost('market/holidays', '{"apikey":"test-api-key","year":2026}');
        end

        function holidaysResponse(tc)
            tc.respond(['{"status":"success","data":[{"date":"2025-02-26","description":"Maha Shivaratri",' ...
                '"holiday_type":"TRADING_HOLIDAY","closed_exchanges":["NSE","BSE"],"open_exchanges":[]}]}']);
            r = tc.Client.holidays(2025);
            tc.verifyEqual(r.data.date, '2025-02-26');
            tc.verifyEqual(r.data.closed_exchanges, {'NSE'; 'BSE'});
            tc.verifyEmpty(r.data.open_exchanges);
        end

        function timings(tc)
            tc.Client.timings("2025-01-15");
            tc.verifySinglePost('market/timings', '{"apikey":"test-api-key","date":"2025-01-15"}');
            tc.Server.reset();
            tc.Client.timings(date="2025-01-16");
            tc.verifySinglePost('market/timings', '{"apikey":"test-api-key","date":"2025-01-16"}');
        end

        function timingsDefaultsToToday(tc)
            before = char(datetime('now', 'Format', 'yyyy-MM-dd'));
            tc.Client.timings();
            after = char(datetime('now', 'Format', 'yyyy-MM-dd'));
            r = tc.Server.lastRequest();
            body = jsondecode(r.body);
            tc.verifyTrue(any(strcmp(body.date, {before, after})), body.date);
            tc.verifyEqual(fieldnames(body), {'apikey'; 'date'});
        end

        function argumentErrors(tc)
            % holidays and timings take no **kwargs in Python
            tc.verifyError(@() tc.Client.holidays(2025, 2026), 'openalgo:invalidArguments');
            tc.verifyError(@() tc.Client.holidays(month=1), 'openalgo:unexpectedArgument');
            tc.verifyError(@() tc.Client.timings("2025-01-15", exchange="NSE"), 'openalgo:unexpectedArgument');
            tc.verifyNoRequest();
        end
    end
end
