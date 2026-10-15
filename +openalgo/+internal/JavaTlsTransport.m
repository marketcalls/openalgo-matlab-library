classdef JavaTlsTransport < handle
    %JAVATLSTRANSPORT TLS byte transport (wss://) using the Java TLS socket factory.
    %   Needs MATLAB running with the JVM. The socket is layered over a plain
    %   socket with createSocket(plain, host, port, true), so the host name
    %   is sent (SNI) and the certificate is verified by the default trust
    %   manager. Certificate verification cannot be turned off here.
    %
    %   See openalgo.internal.TcpTransport for the transport interface.
    %   This class is internal to the openalgo package.

    properties (SetAccess = private)
        Name = 'java'
        Error = ''
        Verify = true
    end

    properties (Access = private)
        Sock = []
        In = []
        Out = []
        Chan = []
    end

    methods (Static)
        function tf = isAvailable()
            %ISAVAILABLE True when MATLAB runs with the JVM.
            tf = usejava('jvm');
        end
    end

    methods
        function obj = JavaTlsTransport(verify)
            if nargin >= 1
                obj.Verify = logical(verify);
            end
        end

        function open(obj, host, port, timeout)
            if ~obj.Verify
                error('openalgo:WebSocketClient:tls', ...
                    'Certificate verification cannot be disabled on the Java transport.');
            end
            ms = int32(max(1, round(timeout * 1000)));
            plain = java.net.Socket();
            plain.connect(java.net.InetSocketAddress(host, int32(port)), ms);
            plain.setTcpNoDelay(true);
            factory = javax.net.ssl.SSLSocketFactory.getDefault();
            sock = factory.createSocket(plain, host, int32(port), true);
            sock.setSoTimeout(ms);
            sock.startHandshake();
            obj.Sock = sock;
            obj.In = sock.getInputStream();
            obj.Out = sock.getOutputStream();
            obj.Chan = java.nio.channels.Channels.newChannel(obj.In);
        end

        function data = read(obj)
            data = zeros(1, 0, 'uint8');
            if isempty(obj.Sock) || ~isempty(obj.Error)
                return
            end
            try
                n = obj.In.available();
                if n <= 0
                    % available() only counts decrypted bytes, so probe with a
                    % one byte read under a 1 ms socket timeout.
                    obj.Sock.setSoTimeout(int32(1));
                    try
                        b = obj.In.read();
                    catch err
                        if contains(err.message, 'SocketTimeoutException') || contains(err.message, 'timed out')
                            return
                        end
                        rethrow(err);
                    end
                    if b < 0
                        obj.Error = 'Connection to remote host was lost.';
                        return
                    end
                    data = uint8(b);
                    n = obj.In.available();
                end
                if n > 0
                    jb = java.nio.ByteBuffer.allocate(int32(n));
                    k = obj.Chan.read(jb);
                    if k > 0
                        arr = jb.array();
                        bytes = typecast(int8(arr(1:k)), 'uint8');
                        data = [data, bytes(:).'];
                    elseif k < 0
                        obj.Error = 'Connection to remote host was lost.';
                    end
                end
            catch err
                obj.Error = err.message;
            end
        end

        function write(obj, bytes)
            if isempty(obj.Out)
                error('openalgo:WebSocketClient:closed', 'Connection is already closed.');
            end
            obj.Out.write(typecast(uint8(bytes), 'int8'));
            obj.Out.flush();
        end

        function close(obj)
            sock = obj.Sock;
            obj.Sock = [];
            obj.In = [];
            obj.Out = [];
            obj.Chan = [];
            if ~isempty(sock)
                try
                    sock.close();
                catch
                end
            end
        end

        function delete(obj)
            obj.close();
        end
    end
end
