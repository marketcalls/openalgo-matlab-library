classdef TcpTransport < handle
    %TCPTRANSPORT Plain TCP byte transport (ws://) based on tcpclient.
    %   Byte transports used by openalgo.internal.WebSocketClient share one
    %   interface:
    %       open(host, port, timeout)  connect, throws on failure
    %       data = read()              non-blocking, uint8 row (may be empty)
    %       write(bytes)               send all bytes, throws on failure
    %       close()                    release the connection
    %       Error                      set when the peer is gone
    %
    %   This class is internal to the openalgo package.

    properties (SetAccess = private)
        Name = 'tcp'
        Error = ''
    end

    properties (Access = private)
        Sock = []
    end

    methods
        function open(obj, host, port, timeout)
            args = {'ConnectTimeout', max(1, timeout), 'Timeout', max(1, timeout)};
            try
                sock = tcpclient(host, port, args{:}, 'EnableTransferDelay', false);
            catch err
                if contains(err.message, 'EnableTransferDelay')
                    sock = tcpclient(host, port, args{:});
                else
                    rethrow(err);
                end
            end
            obj.Sock = sock;
            try
                sock.ErrorOccurredFcn = @(~, evt) obj.onError(evt);
            catch
                % Errors then surface on read or write.
            end
        end

        function data = read(obj)
            data = zeros(1, 0, 'uint8');
            if isempty(obj.Sock) || ~isempty(obj.Error)
                return
            end
            try
                n = obj.Sock.NumBytesAvailable;
                if n > 0
                    data = uint8(read(obj.Sock, n, 'uint8'));
                    data = data(:).';
                end
            catch err
                obj.Error = err.message;
            end
        end

        function write(obj, bytes)
            if isempty(obj.Sock)
                error('openalgo:WebSocketClient:closed', 'Connection is already closed.');
            end
            write(obj.Sock, uint8(bytes));
        end

        function close(obj)
            sock = obj.Sock;
            obj.Sock = [];
            if isempty(sock)
                return
            end
            try
                sock.ErrorOccurredFcn = [];
            catch
            end
            try
                delete(sock);
            catch
            end
        end

        function delete(obj)
            obj.close();
        end
    end

    methods (Access = private)
        function onError(obj, evt)
            if ~isvalid(obj)
                return
            end
            msg = 'Connection to remote host was lost.';
            try
                msg = char(evt.Message);
            catch
            end
            obj.Error = msg;
        end
    end
end
