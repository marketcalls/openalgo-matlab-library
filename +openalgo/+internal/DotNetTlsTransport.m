classdef DotNetTlsTransport < handle
    %DOTNETTLSTRANSPORT TLS byte transport (wss://) using .NET on Windows.
    %   Uses System.Net.Sockets.TcpClient and System.Net.Security.SslStream.
    %   AuthenticateAsClient(host) sends the host name (SNI) and validates
    %   the server certificate chain and name with the Windows trust store.
    %
    %   Reads never block: one ReadAsync task is kept pending and read() only
    %   collects it once IsCompleted is true, then starts the next one. Read
    %   timeouts are not used because a timed out SslStream read leaves the
    %   stream unusable, and TcpClient.Available does not see records that
    %   SslStream has already buffered.
    %
    %   See openalgo.internal.TcpTransport for the transport interface.
    %   This class is internal to the openalgo package.

    properties (SetAccess = private)
        Name = 'dotnet'
        Error = ''
        Verify = true
    end

    properties (Access = private)
        Client = []
        Stream = []
        Buffer = []
        Pending = []
    end

    properties (Constant, Access = private)
        BufferSize = 65536
    end

    methods (Static)
        function tf = isAvailable()
            %ISAVAILABLE True when .NET can be used from MATLAB.
            tf = false;
            try
                tf = ispc && NET.isNETSupported;
            catch
            end
        end

        function ok = acceptAnyCertificate(varargin)
            %ACCEPTANYCERTIFICATE Validation callback used only when Verify is false.
            ok = true;
        end
    end

    methods
        function obj = DotNetTlsTransport(verify)
            if nargin >= 1
                obj.Verify = logical(verify);
            end
        end

        function open(obj, host, port, timeout)
            ms = int32(max(1, round(timeout * 1000)));
            obj.Client = System.Net.Sockets.TcpClient();
            try
                connected = obj.Client.ConnectAsync(host, int32(port)).Wait(ms);
            catch err
                error('openalgo:WebSocketClient:connect', '%s', ...
                    openalgo.internal.DotNetTlsTransport.netMessage(err));
            end
            if ~connected
                error('openalgo:WebSocketClient:connect', 'Connection to %s:%d timed out', host, port);
            end
            obj.Client.NoDelay = true;
            network = obj.Client.GetStream();
            if obj.Verify
                obj.Stream = System.Net.Security.SslStream(network, false);
            else
                callback = System.Net.Security.RemoteCertificateValidationCallback( ...
                    @openalgo.internal.DotNetTlsTransport.acceptAnyCertificate);
                obj.Stream = System.Net.Security.SslStream(network, false, callback);
            end
            % The handshake runs synchronously on the MATLAB thread: an async
            % handshake would call the MATLAB validation callback from a
            % thread pool thread while MATLAB waits, which deadlocks. The
            % timeouts bound the handshake only and are cleared afterwards;
            % data reads use ReadAsync, which ignores them.
            network.ReadTimeout = ms;
            network.WriteTimeout = ms;
            try
                obj.Stream.AuthenticateAsClient(host);
            catch err
                error('openalgo:WebSocketClient:tls', 'TLS handshake failed: %s', ...
                    openalgo.internal.DotNetTlsTransport.netMessage(err));
            end
            network.ReadTimeout = int32(-1);
            network.WriteTimeout = int32(-1);
            obj.Buffer = NET.createArray('System.Byte', obj.BufferSize);
        end

        function data = read(obj)
            data = zeros(1, 0, 'uint8');
            if isempty(obj.Stream) || ~isempty(obj.Error)
                return
            end
            try
                for k = 1:64
                    if isempty(obj.Pending)
                        obj.Pending = obj.Stream.ReadAsync(obj.Buffer, int32(0), int32(obj.BufferSize));
                    end
                    task = obj.Pending;
                    if ~task.IsCompleted
                        break
                    end
                    obj.Pending = [];
                    if task.IsFaulted || task.IsCanceled
                        msg = 'Connection to remote host was lost.';
                        try
                            msg = char(task.Exception.GetBaseException().Message);
                        catch
                        end
                        obj.Error = msg;
                        break
                    end
                    n = double(task.Result);
                    if n <= 0
                        obj.Error = 'Connection to remote host was lost.';
                        break
                    end
                    bytes = uint8(obj.Buffer);
                    data = [data, reshape(bytes(1:n), 1, [])]; %#ok<AGROW>
                end
            catch err
                obj.Error = openalgo.internal.DotNetTlsTransport.netMessage(err);
            end
        end

        function write(obj, bytes)
            if isempty(obj.Stream)
                error('openalgo:WebSocketClient:closed', 'Connection is already closed.');
            end
            bytes = uint8(bytes);
            try
                obj.Stream.Write(bytes, int32(0), int32(numel(bytes)));
                obj.Stream.Flush();
            catch err
                error('openalgo:WebSocketClient:sendFailed', '%s', ...
                    openalgo.internal.DotNetTlsTransport.netMessage(err));
            end
        end

        function close(obj)
            stream = obj.Stream;
            client = obj.Client;
            obj.Stream = [];
            obj.Client = [];
            obj.Pending = [];
            try
                if ~isempty(stream)
                    stream.Close();
                end
            catch
            end
            try
                if ~isempty(client)
                    client.Close();
                end
            catch
            end
        end

        function delete(obj)
            obj.close();
        end
    end

    methods (Static, Access = private)
        function msg = netMessage(err)
            % Innermost .NET exception message, or the MATLAB message.
            msg = err.message;
            try
                ex = err.ExceptionObject;
                ex = ex.GetBaseException();
                msg = char(ex.Message);
            catch
            end
        end
    end
end
