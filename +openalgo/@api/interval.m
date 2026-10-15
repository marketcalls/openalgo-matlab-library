function result = interval(obj, varargin)
%INTERVAL Legacy method. Use intervals instead.
%   RESULT = CLIENT.INTERVAL() returns the supported time intervals for
%   historical data, exactly as CLIENT.INTERVALS(). It takes no arguments.
%
%   See also openalgo.api/intervals.

openalgo.internal.parseArgs('interval', varargin, {}, {}, 0, false);
result = obj.intervals();
end
