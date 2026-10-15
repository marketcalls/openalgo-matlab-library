classdef WebSocketClient < handle
    %WEBSOCKETCLIENT Minimal RFC 6455 WebSocket client written in MATLAB.
    %   MATLAB has no built-in WebSocket client, so the market data feed
    %   uses this small implementation. All framing lives here; the bytes
    %   travel over a pluggable transport object:
    %       ws://   openalgo.internal.TcpTransport (tcpclient)
    %       wss://  the first available of
    %               openalgo.internal.DotNetTlsTransport  (.NET, Windows)
    %               openalgo.internal.PythonTlsTransport  (Python interface)
    %               openalgo.internal.JavaTlsTransport    (JVM)
    %   Every TLS transport sends the host name (SNI) and verifies the
    %   server certificate chain and host name.
    %
    %   The client is non-blocking after the opening handshake: call poll()
    %   regularly to read whatever bytes have arrived. poll() answers pings,
    %   tracks pongs, sends keepalive pings, completes the closing handshake
    %   and returns the complete text messages received since the last call.
    %
    %   client = openalgo.internal.WebSocketClient(url) creates an unopened
    %   client. Optional name-value arguments:
    %       PingInterval       seconds between keepalive pings (default 20, 0 = off)
    %       PingTimeout        seconds to wait for a pong before the connection
    %                          is treated as dropped (default 10, 0 = off)
    %       TlsTransport       'auto' (default), 'dotnet', 'python' or 'java'
    %       VerifyCertificate  true (default). false accepts any certificate
    %                          and is meant only for tests with self-signed
    %                          certificates (not possible with Java).
    %       CaFile             PEM file with one or more CA certificates that
    %                          are trusted in addition to the system trust
    %                          store, for a server with a private CA. The host
    %                          name is still verified.
    %
    %   Example:
    %       c = openalgo.internal.WebSocketClient('ws://127.0.0.1:8765');
    %       c.open(5);
    %       c.send('{"action":"authenticate","api_key":"..."}');
    %       pause(0.5);
    %       msgs = c.poll();
    %       c.close();
    %
    %   This class is internal to the openalgo package; its interface may
    %   change between releases.

    properties (SetAccess = private)
        Url = ''            % URL given to the constructor
        Scheme = ''         % 'ws' or 'wss'
        Host = ''           % host name or address
        Port = 0            % TCP port
        Resource = '/'      % request path and query
        State = 'new'       % 'new', 'connecting', 'open', 'closing' or 'closed'
        CloseCode = []      % status code of the close frame received, if any
        CloseReason = ''    % reason text of the close frame received, if any
        LastError = ''      % transport or protocol error that closed the connection
        TransportName = ''  % 'tcp', 'dotnet', 'python' or 'java' once opened
    end

    properties
        PingInterval = 20   % seconds between keepalive pings, 0 disables
        PingTimeout = 10    % seconds to wait for a pong, 0 disables
        CloseTimeout = 3    % seconds to wait for the close reply
    end

    properties (Hidden)
        CloseHandled = false    % set by the owner once it has handled the close
        PumpBusy = false        % re-entrancy guard owned by the feed
        TlsTransport = 'auto'   % 'auto', 'dotnet', 'python' or 'java'
        VerifyCertificate = true % false only for tests with self-signed certificates
        CaFile = ''              % extra trusted CA certificates (PEM file)
    end

    properties (Access = private)
        Transport = []                      % byte transport object
        RxBuf = zeros(1, 0, 'uint8')
        FragOpcode = 0
        FragData = zeros(1, 0, 'uint8')
        Clock = []
        NextPingAt = Inf
        LastPingAt = -Inf
        LastPongAt = -Inf
        ClosingSince = Inf
        PeerError = ''
    end

    properties (Constant, Hidden)
        GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'
    end

    methods
        function obj = WebSocketClient(url, varargin)
            %WEBSOCKETCLIENT Create an unopened client for a ws:// or wss:// URL.
            obj.Clock = tic;
            url = char(url);
            obj.Url = url;
            parts = regexp(url, ['^(?<scheme>[A-Za-z][A-Za-z0-9+.-]*)://' ...
                '(?<host>\[[^\]]+\]|[^/:?#]+)(?<port>(?::\d+)?)(?<path>(?:[/?][^#]*)?)'], ...
                'names', 'once');
            if ~isempty(parts)
                parts.port = regexprep(parts.port, '^:', '');
            end
            if isempty(parts)
                error('openalgo:WebSocketClient:badUrl', 'Invalid WebSocket URL: %s', url);
            end
            scheme = lower(parts.scheme);
            if ~any(strcmp(scheme, {'ws', 'wss'}))
                error('openalgo:WebSocketClient:badUrl', 'scheme %s is invalid', scheme);
            end
            obj.Scheme = scheme;
            obj.Host = regexprep(parts.host, '^\[(.*)\]$', '$1');
            if isempty(parts.port)
                if strcmp(scheme, 'wss')
                    obj.Port = 443;
                else
                    obj.Port = 80;
                end
            else
                obj.Port = str2double(parts.port);
            end
            path = parts.path;
            if isempty(path)
                path = '/';
            elseif path(1) == '?'
                path = ['/' path];
            end
            obj.Resource = path;
            for k = 1:2:numel(varargin)
                name = char(varargin{k});
                switch lower(name)
                    case 'pinginterval'
                        obj.PingInterval = double(varargin{k + 1});
                    case 'pingtimeout'
                        obj.PingTimeout = double(varargin{k + 1});
                    case 'closetimeout'
                        obj.CloseTimeout = double(varargin{k + 1});
                    case 'tlstransport'
                        obj.TlsTransport = lower(char(varargin{k + 1}));
                    case 'verifycertificate'
                        obj.VerifyCertificate = logical(varargin{k + 1});
                    case 'cafile'
                        obj.CaFile = char(varargin{k + 1});
                    otherwise
                        error('openalgo:WebSocketClient:badOption', 'Unknown option: %s', name);
                end
            end
        end

        function open(obj, timeout)
            %OPEN Connect the socket and perform the opening handshake.
            %   client.open(timeout) blocks for at most timeout seconds
            %   (default 5) and throws an error if the TCP connection, the
            %   TLS handshake or the HTTP Upgrade fails.
            if nargin < 2 || isempty(timeout)
                timeout = 5;
            end
            if ~strcmp(obj.State, 'new')
                error('openalgo:WebSocketClient:state', 'The client has already been opened.');
            end
            obj.State = 'connecting';
            try
                obj.connectTransport(timeout);
                obj.handshake(timeout);
            catch err
                obj.closeTransport();
                obj.State = 'closed';
                obj.LastError = err.message;
                rethrow(err);
            end
            obj.State = 'open';
            if obj.PingInterval > 0
                obj.NextPingAt = obj.elapsed() + obj.PingInterval;
            end
        end

        function send(obj, text)
            %SEND Send a text message (masked client frame).
            if ~strcmp(obj.State, 'open')
                error('openalgo:WebSocketClient:closed', 'Connection is already closed.');
            end
            obj.sendFrame(1, unicode2native(char(text), 'UTF-8'));
        end

        function ping(obj, payload)
            %PING Send a ping control frame.
            if nargin < 2
                payload = zeros(1, 0, 'uint8');
            end
            if ~strcmp(obj.State, 'open')
                error('openalgo:WebSocketClient:closed', 'Connection is already closed.');
            end
            obj.sendFrame(9, uint8(payload));
            t = obj.elapsed();
            obj.LastPingAt = t;
            if obj.PingInterval > 0
                obj.NextPingAt = t + obj.PingInterval;
            end
        end

        function msgs = poll(obj)
            %POLL Read available data without blocking.
            %   msgs = client.poll() returns a cell array of the complete
            %   text messages (char row vectors) received since the last
            %   call. Binary messages are decoded as UTF-8 text as well.
            %   Pings are answered, pongs recorded, keepalive pings sent and
            %   the closing handshake completed here.
            msgs = {};
            if ~any(strcmp(obj.State, {'open', 'closing'}))
                return
            end
            data = obj.readRaw();
            if ~isempty(data)
                obj.RxBuf = [obj.RxBuf, data];
            end
            if ~isempty(obj.RxBuf)
                msgs = obj.parseFrames();
            end
            if ~any(strcmp(obj.State, {'open', 'closing'}))
                return
            end
            if ~isempty(obj.PeerError)
                obj.fail(obj.PeerError);
                return
            end
            if strcmp(obj.State, 'open')
                obj.keepalive();
            elseif obj.elapsed() - obj.ClosingSince > obj.CloseTimeout
                obj.closeTransport();
                obj.State = 'closed';
            end
        end

        function tf = isOpen(obj)
            %ISOPEN True while the connection is open for sending.
            tf = strcmp(obj.State, 'open');
        end

        function tf = isClosed(obj)
            %ISCLOSED True once the connection is fully closed.
            tf = strcmp(obj.State, 'closed');
        end

        function close(obj, code, reason)
            %CLOSE Start the closing handshake.
            %   client.close() sends a close frame (status 1000) and moves to
            %   the 'closing' state; poll() completes the handshake when the
            %   server answers, or after CloseTimeout seconds. A client that
            %   never opened is closed at once.
            if nargin < 2 || isempty(code)
                code = 1000;
            end
            if nargin < 3
                reason = '';
            end
            switch obj.State
                case 'open'
                    payload = [uint8(floor(code / 256)), uint8(mod(code, 256)), ...
                        unicode2native(char(reason), 'UTF-8')];
                    try
                        obj.sendFrame(8, payload);
                        obj.State = 'closing';
                        obj.ClosingSince = obj.elapsed();
                    catch
                        % sendFrame already marked the client closed.
                    end
                case {'new', 'connecting'}
                    obj.closeTransport();
                    obj.State = 'closed';
            end
        end

        function abort(obj)
            %ABORT Close the TCP connection immediately, without a close frame.
            obj.closeTransport();
            obj.State = 'closed';
        end

        function delete(obj)
            %DELETE Release the socket.
            obj.closeTransport();
        end
    end

    methods (Static, Hidden)
        function digest = sha1(bytes)
            %SHA1 SHA-1 digest of a uint8 vector, returned as 1x20 uint8.
            %   Uses java.security.MessageDigest when the JVM is available,
            %   otherwise the MATLAB implementation in sha1Matlab.
            bytes = uint8(bytes(:).');
            if usejava('jvm')
                md = java.security.MessageDigest.getInstance('SHA-1');
                d = md.digest(typecast(bytes, 'int8'));
                digest = typecast(int8(d(:).'), 'uint8');
            else
                digest = openalgo.internal.WebSocketClient.sha1Matlab(bytes);
            end
        end

        function digest = sha1Matlab(bytes)
            %SHA1MATLAB SHA-1 digest computed in MATLAB code (FIPS 180-4).
            bytes = uint8(bytes(:).');
            ml = numel(bytes) * 8;
            padLen = mod(55 - numel(bytes), 64);
            msg = [bytes, uint8(128), zeros(1, padLen, 'uint8'), ...
                fliplr(typecast(uint64(ml), 'uint8'))];
            H = uint32([1732584193, 4023233417, 2562383102, 271733878, 3285377520]);
            K = uint32([1518500249, 1859775393, 2400959708, 3395469782]);
            rotl = @(x, n) bitor(bitshift(x, n), bitshift(x, n - 32));
            add32 = @(varargin) uint32(mod(sum(cellfun(@double, varargin)), 4294967296));
            nBlocks = numel(msg) / 64;
            for blk = 1:nBlocks
                chunk = double(msg((blk - 1) * 64 + (1:64)));
                w = zeros(1, 80, 'uint32');
                for t = 1:16
                    w(t) = uint32(chunk(4 * t - 3) * 16777216 + chunk(4 * t - 2) * 65536 + ...
                        chunk(4 * t - 1) * 256 + chunk(4 * t));
                end
                for t = 17:80
                    w(t) = rotl(bitxor(bitxor(w(t - 3), w(t - 8)), bitxor(w(t - 14), w(t - 16))), 1);
                end
                a = H(1); b = H(2); c = H(3); d = H(4); e = H(5);
                for t = 1:80
                    if t <= 20
                        f = bitor(bitand(b, c), bitand(bitcmp(b), d));
                        k = K(1);
                    elseif t <= 40
                        f = bitxor(bitxor(b, c), d);
                        k = K(2);
                    elseif t <= 60
                        f = bitor(bitor(bitand(b, c), bitand(b, d)), bitand(c, d));
                        k = K(3);
                    else
                        f = bitxor(bitxor(b, c), d);
                        k = K(4);
                    end
                    temp = add32(rotl(a, 5), f, e, k, w(t));
                    e = d;
                    d = c;
                    c = rotl(b, 30);
                    b = a;
                    a = temp;
                end
                H(1) = add32(H(1), a);
                H(2) = add32(H(2), b);
                H(3) = add32(H(3), c);
                H(4) = add32(H(4), d);
                H(5) = add32(H(5), e);
            end
            digest = zeros(1, 20, 'uint8');
            for i = 1:5
                digest(4 * i - 3:4 * i) = fliplr(typecast(H(i), 'uint8'));
            end
        end

        function accept = acceptKey(key)
            %ACCEPTKEY Expected Sec-WebSocket-Accept value for a request key.
            raw = uint8([char(key), openalgo.internal.WebSocketClient.GUID]);
            accept = matlab.net.base64encode(openalgo.internal.WebSocketClient.sha1(raw));
        end
    end

    methods (Access = private)
        function t = elapsed(obj)
            t = toc(obj.Clock);
        end

        function connectTransport(obj, timeout)
            if strcmp(obj.Scheme, 'wss')
                transport = openalgo.internal.WebSocketClient.makeTlsTransport( ...
                    obj.TlsTransport, obj.VerifyCertificate, obj.CaFile);
            else
                transport = openalgo.internal.TcpTransport();
            end
            obj.Transport = transport;
            obj.TransportName = transport.Name;
            transport.open(obj.Host, obj.Port, timeout);
        end

        function handshake(obj, timeout)
            key = matlab.net.base64encode(uint8(randi([0 255], 1, 16)));
            if (strcmp(obj.Scheme, 'ws') && obj.Port == 80) || (strcmp(obj.Scheme, 'wss') && obj.Port == 443)
                hostHeader = obj.Host;
            else
                hostHeader = sprintf('%s:%d', obj.Host, obj.Port);
            end
            if strcmp(obj.Scheme, 'wss')
                origin = ['https://' hostHeader];
            else
                origin = ['http://' hostHeader];
            end
            crlf = char([13 10]);
            request = ['GET ' obj.Resource ' HTTP/1.1' crlf, ...
                'Upgrade: websocket' crlf, ...
                'Connection: Upgrade' crlf, ...
                'Host: ' hostHeader crlf, ...
                'Origin: ' origin crlf, ...
                'Sec-WebSocket-Key: ' key crlf, ...
                'Sec-WebSocket-Version: 13' crlf, crlf];
            obj.writeRaw(unicode2native(request, 'UTF-8'));

            started = tic;
            buf = zeros(1, 0, 'uint8');
            headerEnd = [];
            while isempty(headerEnd)
                data = obj.readRaw();
                if ~isempty(data)
                    buf = [buf, data]; %#ok<AGROW>
                    headerEnd = strfind(char(buf), [crlf crlf]);
                    if ~isempty(headerEnd)
                        break
                    end
                end
                if ~isempty(obj.PeerError)
                    error('openalgo:WebSocketClient:handshake', '%s', obj.PeerError);
                end
                if toc(started) > timeout
                    error('openalgo:WebSocketClient:handshake', 'Handshake timed out');
                end
                if isempty(data)
                    pause(0.005);
                end
            end
            headerEnd = headerEnd(1);
            header = char(buf(1:headerEnd - 1));
            obj.RxBuf = buf(headerEnd + 4:end);

            lines = strsplit(header, crlf, 'CollapseDelimiters', false);
            status = regexp(lines{1}, '^HTTP/\d(?:\.\d)?\s+(\d{3})\s*(.*)$', 'tokens', 'once');
            if isempty(status)
                error('openalgo:WebSocketClient:handshake', 'Invalid handshake response: %s', lines{1});
            end
            if ~strcmp(status{1}, '101')
                error('openalgo:WebSocketClient:handshake', 'Handshake status %s %s', status{1}, status{2});
            end
            names = {};
            values = {};
            for i = 2:numel(lines)
                idx = find(lines{i} == ':', 1);
                if isempty(idx)
                    continue
                end
                names{end + 1} = lower(strtrim(lines{i}(1:idx - 1))); %#ok<AGROW>
                values{end + 1} = strtrim(lines{i}(idx + 1:end)); %#ok<AGROW>
            end
            upgrade = values(strcmp(names, 'upgrade'));
            if isempty(upgrade) || ~strcmpi(upgrade{1}, 'websocket')
                error('openalgo:WebSocketClient:handshake', 'Invalid WebSocket Header');
            end
            accept = values(strcmp(names, 'sec-websocket-accept'));
            expected = openalgo.internal.WebSocketClient.acceptKey(key);
            if isempty(accept) || ~strcmp(accept{1}, expected)
                error('openalgo:WebSocketClient:handshake', 'Invalid challenge response');
            end
        end

        function msgs = parseFrames(obj)
            msgs = {};
            buf = obj.RxBuf;
            n = numel(buf);
            pos = 1;
            while true
                avail = n - pos + 1;
                if avail < 2
                    break
                end
                b1 = double(buf(pos));
                b2 = double(buf(pos + 1));
                fin = b1 >= 128;
                opcode = mod(b1, 16);
                masked = b2 >= 128;
                len = mod(b2, 128);
                hdr = 2;
                if len == 126
                    if avail < 4
                        break
                    end
                    len = double(buf(pos + 2)) * 256 + double(buf(pos + 3));
                    hdr = 4;
                elseif len == 127
                    if avail < 10
                        break
                    end
                    len = sum(double(buf(pos + 2:pos + 9)) .* 256 .^ (7:-1:0));
                    hdr = 10;
                end
                mask = zeros(1, 0, 'uint8');
                if masked
                    if avail < hdr + 4
                        break
                    end
                    mask = buf(pos + hdr:pos + hdr + 3);
                    hdr = hdr + 4;
                end
                if avail < hdr + len
                    break
                end
                payload = buf(pos + hdr:pos + hdr + len - 1);
                if masked && len > 0
                    payload = bitxor(payload, mask(mod(0:len - 1, 4) + 1));
                end
                pos = pos + hdr + len;
                [hasMsg, text] = obj.handleFrame(fin, opcode, payload);
                if hasMsg
                    msgs{end + 1} = text; %#ok<AGROW>
                end
                if strcmp(obj.State, 'closed')
                    break
                end
            end
            if strcmp(obj.State, 'closed')
                obj.RxBuf = zeros(1, 0, 'uint8');
            else
                obj.RxBuf = buf(pos:end);
            end
        end

        function [hasMsg, text] = handleFrame(obj, fin, opcode, payload)
            hasMsg = false;
            text = '';
            switch opcode
                case {1, 2}
                    if fin
                        hasMsg = true;
                        text = openalgo.internal.WebSocketClient.decodeText(payload);
                    else
                        obj.FragOpcode = opcode;
                        obj.FragData = payload;
                    end
                case 0
                    if obj.FragOpcode == 0
                        obj.fail('Illegal frame');
                        return
                    end
                    obj.FragData = [obj.FragData, payload];
                    if fin
                        hasMsg = true;
                        text = openalgo.internal.WebSocketClient.decodeText(obj.FragData);
                        obj.FragOpcode = 0;
                        obj.FragData = zeros(1, 0, 'uint8');
                    end
                case 8
                    if numel(payload) >= 2
                        obj.CloseCode = double(payload(1)) * 256 + double(payload(2));
                        obj.CloseReason = openalgo.internal.WebSocketClient.decodeText(payload(3:end));
                    end
                    if strcmp(obj.State, 'open')
                        try
                            obj.sendFrame(8, payload(1:min(2, numel(payload))));
                        catch
                        end
                    end
                    obj.closeTransport();
                    obj.State = 'closed';
                case 9
                    if strcmp(obj.State, 'open')
                        try
                            obj.sendFrame(10, payload);
                        catch
                        end
                    end
                case 10
                    obj.LastPongAt = obj.elapsed();
                otherwise
                    obj.fail(sprintf('Invalid opcode %d', opcode));
            end
        end

        function keepalive(obj)
            t = obj.elapsed();
            if obj.PingInterval > 0 && t >= obj.NextPingAt
                try
                    obj.sendFrame(9, zeros(1, 0, 'uint8'));
                catch
                    return
                end
                obj.LastPingAt = t;
                obj.NextPingAt = t + obj.PingInterval;
            end
            % A pong is required after each ping. Data is read before this
            % check, so a pong delayed only by a busy MATLAB session still
            % counts.
            if obj.PingTimeout > 0 && obj.LastPingAt > -Inf && ...
                    obj.LastPongAt < obj.LastPingAt && t - obj.LastPingAt > obj.PingTimeout
                obj.fail('ping/pong timed out');
            end
        end

        function sendFrame(obj, opcode, payload)
            payload = uint8(payload(:).');
            n = numel(payload);
            b1 = uint8(128 + opcode);
            if n < 126
                header = [b1, uint8(128 + n)];
            elseif n < 65536
                header = [b1, uint8(254), uint8(floor(n / 256)), uint8(mod(n, 256))];
            else
                header = [b1, uint8(255), fliplr(typecast(uint64(n), 'uint8'))];
            end
            mask = uint8(randi([0 255], 1, 4));
            if n > 0
                payload = bitxor(payload, mask(mod(0:n - 1, 4) + 1));
            end
            obj.writeRaw([header, mask, payload]);
        end

        function writeRaw(obj, bytes)
            try
                if isempty(obj.Transport)
                    error('openalgo:WebSocketClient:closed', 'Connection is already closed.');
                end
                obj.Transport.write(uint8(bytes));
            catch err
                if any(strcmp(obj.State, {'open', 'closing'}))
                    obj.fail(err.message);
                end
                error('openalgo:WebSocketClient:sendFailed', '%s', err.message);
            end
        end

        function data = readRaw(obj)
            data = zeros(1, 0, 'uint8');
            if isempty(obj.Transport)
                return
            end
            try
                data = obj.Transport.read();
                if ~isempty(obj.Transport.Error)
                    obj.PeerError = obj.Transport.Error;
                end
            catch err
                obj.PeerError = err.message;
            end
        end

        function fail(obj, message)
            obj.LastError = char(message);
            obj.closeTransport();
            obj.State = 'closed';
        end

        function closeTransport(obj)
            transport = obj.Transport;
            obj.Transport = [];
            if ~isempty(transport)
                try
                    transport.close();
                catch
                end
            end
        end
    end

    methods (Static, Access = private)
        function transport = makeTlsTransport(choice, verify, caFile)
            % Pick the TLS byte transport: forced by choice, or the first
            % available of .NET, Python and Java.
            caFile = char(caFile);
            if ~isempty(caFile) && ~isfile(caFile)
                error('openalgo:WebSocketClient:badOption', 'CA file not found: %s', caFile);
            end
            choice = lower(char(choice));
            switch choice
                case 'dotnet'
                    names = {'dotnet'};
                case 'python'
                    names = {'python'};
                case 'java'
                    names = {'java'};
                case 'auto'
                    names = {'dotnet', 'python', 'java'};
                otherwise
                    error('openalgo:WebSocketClient:badOption', ...
                        'TlsTransport must be ''auto'', ''dotnet'', ''python'' or ''java'', not ''%s''.', choice);
            end
            forced = ~strcmp(choice, 'auto');
            for i = 1:numel(names)
                switch names{i}
                    case 'dotnet'
                        if openalgo.internal.DotNetTlsTransport.isAvailable()
                            transport = openalgo.internal.DotNetTlsTransport(verify, caFile);
                            return
                        end
                    case 'python'
                        if openalgo.internal.PythonTlsTransport.isAvailable(forced)
                            transport = openalgo.internal.PythonTlsTransport(verify, caFile);
                            return
                        end
                    case 'java'
                        if openalgo.internal.JavaTlsTransport.isAvailable()
                            transport = openalgo.internal.JavaTlsTransport(verify, caFile);
                            return
                        end
                end
            end
            if forced
                error('openalgo:WebSocketClient:transportUnavailable', ...
                    'The ''%s'' TLS transport for wss:// is not available in this MATLAB session.', choice);
            end
            error('openalgo:WebSocketClient:noTls', ['wss:// needs a TLS transport and none is ' ...
                'available. Options: (1) .NET on Windows (NET.isNETSupported must be true); ' ...
                '(2) the MATLAB Python interface with a supported Python version (configure it ' ...
                'with pyenv); (3) the Java Virtual Machine (start MATLAB with Java enabled). ' ...
                'A ws:// URL, as used by a local OpenAlgo server, needs none of these.']);
        end

        function text = decodeText(bytes)
            if isempty(bytes)
                text = '';
            else
                text = native2unicode(uint8(bytes(:).'), 'UTF-8');
                text = reshape(text, 1, []);
            end
        end
    end
end
