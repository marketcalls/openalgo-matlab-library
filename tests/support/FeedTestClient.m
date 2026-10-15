classdef FeedTestClient < openalgo.FeedAPI
    %FEEDTESTCLIENT Minimal feed client for the FeedAPI tests.
    %   c = FeedTestClient(api_key, host, ws_port, ws_url, verbose, auto_reconnect)
    %   declares api_key itself so the feed can be tested without
    %   openalgo.api and openalgo.BaseAPI. Arguments after api_key are
    %   passed to initFeed and may be omitted or empty for defaults.

    properties
        api_key = ''
    end

    methods
        function obj = FeedTestClient(api_key, varargin)
            if nargin >= 1
                obj.api_key = api_key;
            end
            obj.initFeed(varargin{:});
        end

        function reinit(obj, varargin)
            %REINIT Call initFeed again (used to test the URL derivation).
            obj.initFeed(varargin{:});
        end
    end
end
