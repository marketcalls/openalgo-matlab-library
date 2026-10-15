classdef NotificationsTest < RestTestCase
    %NOTIFICATIONSTEST telegram and whatsapp notification methods.

    methods (Test)
        function telegramDefaults(tc)
            tc.Client.telegram(username="u", message="hi"); %#ok<XCREDS> test data, not a credential
            tc.verifySinglePost('telegram/notify', ['{"apikey":"test-api-key","username":"u",' ...
                '"message":"hi","priority":5}']);
            tc.Server.reset();
            tc.Client.telegram(username="u", message="hi", priority=9, x=[], y="z"); %#ok<XCREDS> test data, not a credential
            tc.verifySinglePost('telegram/notify', ['{"apikey":"test-api-key","username":"u",' ...
                '"message":"hi","priority":9,"y":"z"}']);
            tc.verifyError(@() tc.Client.telegram(username="u"), 'openalgo:missingArgument'); %#ok<XCREDS> test data, not a credential
            tc.verifyError(@() tc.Client.telegram(1, 2), 'openalgo:invalidArguments');
        end

        function whatsappToSelf(tc)
            tc.Client.whatsapp("hello");
            tc.verifySinglePost('whatsapp/notify', ['{"apikey":"test-api-key","self":true,' ...
                '"message":"hello","wait_for_delivery":true}']);
            tc.Server.reset();
            tc.Client.whatsapp();
            tc.verifySinglePost('whatsapp/notify', '{"apikey":"test-api-key","self":true,"wait_for_delivery":true}');
            tc.Server.reset();
            tc.Client.whatsapp("m", to="   ", wait_for_delivery=0);
            tc.verifySinglePost('whatsapp/notify', ['{"apikey":"test-api-key","self":true,' ...
                '"message":"m","wait_for_delivery":false}']);
        end

        function whatsappToPhoneWithImage(tc)
            tc.Client.whatsapp("m", to="919876543210", image="a.png", caption="c", wait_for_delivery=false);
            tc.verifySinglePost('whatsapp/notify', ['{"apikey":"test-api-key","phone":"919876543210",' ...
                '"message":"m","image_path":"a.png","caption":"c","wait_for_delivery":false}']);
        end

        function whatsappPhoneListIsAnArray(tc)
            expected = ['{"apikey":"test-api-key","phones":["919876543210"],"message":"m",' ...
                '"document_path":"d.pdf","filename":"f.pdf","wait_for_delivery":true}'];
            tc.Client.whatsapp("m", to={'919876543210'}, document="d.pdf", filename="f.pdf");
            tc.verifySinglePost('whatsapp/notify', expected);
            tc.Server.reset();
            tc.Client.whatsapp(message="m", to=["911", "912"]);
            tc.verifySinglePost('whatsapp/notify', ['{"apikey":"test-api-key","phones":["911","912"],' ...
                '"message":"m","wait_for_delivery":true}']);
        end

        function whatsappUsernameWinsAndKwargsDoNotOverwrite(tc)
            tc.Client.whatsapp(message="m", username="trader", to="91", apikey="other", extra=1, phone="x"); %#ok<XCREDS> test data, not a credential
            tc.verifySinglePost('whatsapp/notify', ['{"apikey":"test-api-key","username":"trader",' ...
                '"message":"m","wait_for_delivery":true,"extra":1,"phone":"x"}']);
        end

        function whatsappTextThatIsAParameterName(tc)
            % A positional value equal to a parameter name stays a value
            % when it cannot start a name=value list.
            tc.Client.whatsapp("message");
            tc.verifySinglePost('whatsapp/notify', ['{"apikey":"test-api-key","self":true,' ...
                '"message":"message","wait_for_delivery":true}']);
            tc.Server.reset();
            tc.Client.whatsapp("to", to="91");
            tc.verifySinglePost('whatsapp/notify', ['{"apikey":"test-api-key","phone":"91",' ...
                '"message":"to","wait_for_delivery":true}']);
        end

        function whatsappArgumentErrors(tc)
            tc.verifyError(@() tc.Client.whatsapp("a b", "c"), 'openalgo:invalidArguments');
            % A leading text that is a valid name followed by a value reads
            % as a name=value pair (an extra field), not as two positionals.
            tc.Client.whatsapp("note", "x");
            r = tc.Server.lastRequest();
            tc.verifyEqual(r.body, '{"apikey":"test-api-key","self":true,"wait_for_delivery":true,"note":"x"}');
            tc.Server.reset();
            tc.verifyError(@() tc.Client.whatsapp("a", message="b"), 'openalgo:duplicateArgument');
            tc.verifyNoRequest();
        end

        function apiErrorIsReturned(tc)
            tc.respond('{"status":"error","message":"Bot is not running"}');
            r = tc.Client.telegram(username="u", message="hi"); %#ok<XCREDS> test data, not a credential
            tc.verifyEqual(r, struct('status', 'error', 'message', 'Bot is not running', ...
                'code', 200, 'error_type', 'api_error'));
            % The unified client uses the order handler for WhatsApp too, so a
            % non-200 answer is 'HTTP <code>: <body>' even when it is JSON.
            tc.respond('{"status":"error","message":"Rate limited"}', 429);
            r = tc.Client.whatsapp("x");
            tc.verifyEqual(r, struct('status', 'error', ...
                'message', 'HTTP 429: {"status":"error","message":"Rate limited"}', ...
                'code', 429, 'error_type', 'http_error'));
        end
    end
end
