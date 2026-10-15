classdef PythonTlsTransport < handle
    %PYTHONTLSTRANSPORT TLS byte transport (wss://) using the MATLAB Python interface.
    %   Cross-platform fallback when .NET is not available (macOS, Linux).
    %   Uses ssl.create_default_context().wrap_socket(socket.create_connection(...),
    %   server_hostname=host), so the host name is sent (SNI) and the
    %   certificate is verified against the default trust store.
    %
    %   Reads are non-blocking: the socket timeout is 0 while reading and
    %   ssl.SSLWantReadError (an incomplete TLS record) means no data yet.
    %   Writes use a short blocking timeout.
    %
    %   The Python interface must be usable (see pyenv). Automatic
    %   selection only uses Python when it is already loaded or when pyenv
    %   names a version listed in SupportedVersions, because loading an
    %   unsupported interpreter can fail badly.
    %
    %   See openalgo.internal.TcpTransport for the transport interface.
    %   This class is internal to the openalgo package.

    properties (SetAccess = private)
        Name = 'python'
        Error = ''
        Verify = true
    end

    properties (Access = private)
        Sock = []
        WriteTimeout = 10
    end

    properties (Constant)
        SupportedVersions = {'3.9', '3.10', '3.11', '3.12', '3.13'}
    end

    methods (Static)
        function tf = isAvailable(allowLoad)
            %ISAVAILABLE True when the Python interface can provide ssl sockets.
            %   isAvailable(true) may load the interpreter configured in
            %   pyenv even when its version is not in SupportedVersions.
            if nargin < 1
                allowLoad = false;
            end
            tf = false;
            try
                pe = pyenv;
                if strlength(pe.Version) == 0
                    return
                end
                loaded = strcmp(string(pe.Status), "Loaded");
                if ~loaded && ~allowLoad && ...
                        ~any(strcmp(char(pe.Version), openalgo.internal.PythonTlsTransport.SupportedVersions))
                    return
                end
                py.importlib.import_module('ssl');
                py.importlib.import_module('select');
                tf = true;
            catch
                tf = false;
            end
        end
    end

    methods
        function obj = PythonTlsTransport(verify)
            if nargin >= 1
                obj.Verify = logical(verify);
            end
        end

        function open(obj, host, port, timeout)
            try
                raw = py.socket.create_connection(py.tuple({char(host), int32(port)}), double(timeout));
                ctx = py.ssl.create_default_context();
                if ~obj.Verify
                    py.setattr(ctx, 'check_hostname', false);
                    py.setattr(ctx, 'verify_mode', py.ssl.CERT_NONE);
                end
                sock = ctx.wrap_socket(raw, pyargs('server_hostname', char(host)));
            catch err
                error('openalgo:WebSocketClient:tls', '%s', openalgo.internal.PythonTlsTransport.pyMessage(err));
            end
            sock.settimeout(0.0);
            obj.Sock = sock;
            obj.WriteTimeout = max(1, double(timeout));
        end

        function data = read(obj)
            data = zeros(1, 0, 'uint8');
            if isempty(obj.Sock) || ~isempty(obj.Error)
                return
            end
            sock = obj.Sock;
            for k = 1:64
                try
                    if double(sock.pending()) <= 0
                        ready = py.select.select(py.list({sock}), py.list(), py.list(), 0);
                        if double(py.len(ready{1})) == 0
                            break
                        end
                    end
                    chunk = sock.recv(int32(65536));
                catch err
                    msg = err.message;
                    if contains(msg, 'SSLWantReadError') || contains(msg, 'SSLWantWriteError') || ...
                            contains(msg, 'BlockingIOError')
                        break
                    end
                    obj.Error = openalgo.internal.PythonTlsTransport.pyMessage(err);
                    break
                end
                bytes = uint8(chunk);
                if isempty(bytes)
                    obj.Error = 'Connection to remote host was lost.';
                    break
                end
                data = [data, reshape(bytes, 1, [])]; %#ok<AGROW>
            end
        end

        function write(obj, bytes)
            if isempty(obj.Sock)
                error('openalgo:WebSocketClient:closed', 'Connection is already closed.');
            end
            sock = obj.Sock;
            try
                sock.settimeout(obj.WriteTimeout);
                sock.sendall(py.bytes(uint8(bytes)));
                sock.settimeout(0.0);
            catch err
                try
                    sock.settimeout(0.0);
                catch
                end
                error('openalgo:WebSocketClient:sendFailed', '%s', openalgo.internal.PythonTlsTransport.pyMessage(err));
            end
        end

        function close(obj)
            sock = obj.Sock;
            obj.Sock = [];
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
        function msg = pyMessage(err)
            msg = err.message;
            msg = regexprep(msg, '^Python Error:\s*', '');
        end
    end
end
