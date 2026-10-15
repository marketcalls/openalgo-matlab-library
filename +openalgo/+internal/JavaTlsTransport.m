classdef JavaTlsTransport < handle
    %JAVATLSTRANSPORT TLS byte transport (wss://) using the Java TLS socket factory.
    %   Needs MATLAB running with the JVM. The socket is layered over a plain
    %   socket with createSocket(plain, host, port, true), so the host name
    %   is sent (SNI). The certificate chain is verified by the default
    %   trust manager and the host name by the HTTPS endpoint
    %   identification algorithm.
    %
    %   With CaFile the trust store is the default one (the JVM's cacerts,
    %   or javax.net.ssl.trustStore when set) plus the certificates of the
    %   PEM file. Certificate verification cannot be turned off here: that
    %   would need a Java interface implementation.
    %
    %   See openalgo.internal.TcpTransport for the transport interface.
    %   This class is internal to the openalgo package.

    properties (SetAccess = private)
        Name = 'java'
        Error = ''
        Verify = true
        CaFile = ''
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
        function obj = JavaTlsTransport(verify, caFile)
            if nargin >= 1
                obj.Verify = logical(verify);
            end
            if nargin >= 2
                obj.CaFile = char(caFile);
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
            try
                if isempty(obj.CaFile)
                    factory = javax.net.ssl.SSLSocketFactory.getDefault();
                else
                    factory = openalgo.internal.JavaTlsTransport.socketFactory(obj.CaFile);
                end
                sock = factory.createSocket(plain, host, int32(port), true);
                params = sock.getSSLParameters();
                params.setEndpointIdentificationAlgorithm('HTTPS');
                sock.setSSLParameters(params);
                sock.setSoTimeout(ms);
                sock.startHandshake();
            catch err
                try
                    plain.close();
                catch
                end
                error('openalgo:WebSocketClient:tls', 'TLS handshake failed: %s', ...
                    openalgo.internal.JavaTlsTransport.javaMessage(err));
            end
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

    methods (Static, Access = private)
        function factory = socketFactory(caFile)
            % SSL socket factory trusting the default trust store plus the
            % certificates in caFile.
            store = openalgo.internal.JavaTlsTransport.defaultTrustStore();
            certFactory = java.security.cert.CertificateFactory.getInstance('X.509');
            in = java.io.FileInputStream(caFile);
            try
                certs = certFactory.generateCertificates(in).toArray();
            catch err
                in.close();
                rethrow(err);
            end
            in.close();
            if numel(certs) == 0
                error('openalgo:WebSocketClient:badOption', 'No certificate found in CA file: %s', caFile);
            end
            for i = 1:numel(certs)
                store.setCertificateEntry(sprintf('openalgo-ca-file-%d', i), certs(i));
            end
            tmf = javax.net.ssl.TrustManagerFactory.getInstance( ...
                javax.net.ssl.TrustManagerFactory.getDefaultAlgorithm());
            tmf.init(store);
            context = javax.net.ssl.SSLContext.getInstance('TLS');
            context.init([], tmf.getTrustManagers(), []);
            factory = context.getSocketFactory();
        end

        function store = defaultTrustStore()
            % The trust store the default SSL context uses, loaded into a
            % writable KeyStore: javax.net.ssl.trustStore when set, else
            % jssecacerts or cacerts of the running JVM. Empty when none
            % can be read.
            file = char(java.lang.System.getProperty('javax.net.ssl.trustStore', ''));
            type = char(java.lang.System.getProperty('javax.net.ssl.trustStoreType', ''));
            password = char(java.lang.System.getProperty('javax.net.ssl.trustStorePassword', ''));
            if isempty(type)
                type = char(java.security.KeyStore.getDefaultType());
            end
            if isempty(file) || strcmpi(file, 'NONE')
                security = fullfile(char(java.lang.System.getProperty('java.home')), 'lib', 'security');
                file = fullfile(security, 'jssecacerts');
                if ~isfile(file)
                    file = fullfile(security, 'cacerts');
                end
            end
            % Without a configured password try none, then the JDK default.
            if isempty(password)
                passwords = {'', 'changeit'};
            else
                passwords = {password};
            end
            loaded = false;
            for k = 1:numel(passwords)
                if loaded || ~isfile(file)
                    break
                end
                try
                    store = java.security.KeyStore.getInstance(type);
                    in = java.io.FileInputStream(file);
                    try
                        if isempty(passwords{k})
                            store.load(in, []);
                        else
                            store.load(in, java.lang.String(passwords{k}).toCharArray());
                        end
                        loaded = store.size() > 0;
                    catch
                    end
                    in.close();
                catch
                end
            end
            if ~loaded
                store = java.security.KeyStore.getInstance(java.security.KeyStore.getDefaultType());
                store.load([], []);
            end
        end

        function msg = javaMessage(err)
            msg = err.message;
            msg = regexprep(msg, '^Java exception occurred:\s*', '');
            msg = strtrim(regexprep(msg, '\n\s*at .*', ''));
        end
    end
end
