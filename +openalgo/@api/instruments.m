function result = instruments(obj, varargin)
%INSTRUMENTS Download all trading symbols and instruments as a table.
%   T = CLIENT.INSTRUMENTS() downloads every exchange.
%   T = CLIENT.INSTRUMENTS(exchange=EXCHANGE) downloads one exchange.
%
%   Parameters:
%     exchange - Exchange to download. Optional. Supported exchanges: NSE,
%                BSE, NFO, BFO, BCD, CDS, MCX, NSE_INDEX, BSE_INDEX.
%                When omitted, all of them are downloaded one after the
%                other and concatenated; an exchange that fails is
%                skipped.
%
%   The request is a GET to instruments with apikey and exchange as query
%   parameters.
%
%   Returns a table on success (the MATLAB counterpart of the pandas
%   DataFrame of the Python SDK) with the columns symbol, brsymbol, name,
%   exchange, token, expiry, strike, lotsize, instrumenttype and tick_size.
%
%   On failure returns the error struct of the request, or:
%     error_type 'no_data'  'No instruments available for the specified exchange'
%                           'Failed to fetch instruments from any exchange'
%     error_type 'processing_error'  'Failed to process instruments data: ...'
%
%   Notes:
%   - Rate limit: 50 requests per second.
%   - The data updates when the master contracts are downloaded.
%
%   Examples:
%     all = client.instruments();
%     nse = client.instruments(exchange="NSE");
%     equities = nse(nse.instrumenttype == "EQ", :);
%     writetable(nse, "nse_instruments.csv");
%
%   See also openalgo.api/search, openalgo.api/symbol.

a = openalgo.internal.parseArgs('instruments', varargin, {'exchange', []}, {}, 0, false);

if openalgo.internal.isNone(a.exchange)
    allExchanges = {'NSE', 'BSE', 'NFO', 'BFO', 'MCX', 'CDS', 'BCD', 'NSE_INDEX', 'BSE_INDEX'};
    parts = {};
    for i = 1:numel(allExchanges)
        params = struct('apikey', obj.api_key, 'exchange', allExchanges{i});
        try
            r = obj.getRequest('instruments', params);
            if isSuccessWithData(r)
                T = openalgo.internal.recordsToTable(r.data);
                if height(T) > 0
                    parts{end+1} = T; %#ok<AGROW>
                end
            end
        catch
            % Skip exchanges that fail
        end
    end
    if ~isempty(parts)
        result = openalgo.internal.concatTables(parts);
    else
        result = openalgo.internal.errorResult('Failed to fetch instruments from any exchange', ...
            'no_data');
    end
    return
end

params = struct();
params.apikey = obj.api_key;
params.exchange = a.exchange;
result = obj.getRequest('instruments', params);

if isSuccessWithData(result)
    data = result.data;
    try
        T = openalgo.internal.recordsToTable(data);
    catch ME
        result = openalgo.internal.errorResult( ...
            ['Failed to process instruments data: ' ME.message], 'processing_error', ...
            'raw_data', data);
        return
    end
    if height(T) == 0
        result = openalgo.internal.errorResult( ...
            'No instruments available for the specified exchange', 'no_data');
        return
    end
    result = T;
end
end

function tf = isSuccessWithData(r)
tf = isstruct(r) && isscalar(r) && isfield(r, 'status') && ...
    openalgo.internal.textEquals(r.status, 'success') && isfield(r, 'data');
end
