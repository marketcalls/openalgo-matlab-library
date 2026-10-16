function results = runAllTests(outputFolder, include)
%RUNALLTESTS Run the OpenAlgo MATLAB test suite.
%   RESULTS = runAllTests() runs every test class in this folder (REST
%   tests against a local mock server, the WebSocket feed tests and the
%   live sandbox tests, which skip themselves unless OPENALGO_API_KEY is
%   set) and prints a summary.
%
%   RESULTS = runAllTests(OUTPUTFOLDER) also writes JUnit XML to
%   OUTPUTFOLDER/junit.xml (the folder is created when needed).
%
%   RESULTS = runAllTests(OUTPUTFOLDER, INCLUDE) runs only the test
%   classes named in INCLUDE (a string array or cell array of class names
%   such as "OrdersTest"). Pass "" or [] as OUTPUTFOLDER to skip the XML.
%
%   When a test fails the function raises runAllTests:failed after the
%   summary, so "matlab -batch runAllTests('out')" exits with a nonzero
%   status. Skipped (incomplete) tests do not count as failures.
%
%   The mock servers need Python 3 on the PATH as "python" (or named by
%   OPENALGO_TEST_PYTHON); the feed tests also need its websockets
%   package. Temporary files go to OPENALGO_TEST_TMP when set, else
%   tempdir.
%
%   Example:
%     cd openalgo-matlab-library
%     addpath("tests");
%     results = runAllTests("test-results");
%
%   From a shell:
%     matlab -batch "addpath('tests'); runAllTests('test-results')"
%
%   See also matlab.unittest.TestSuite.

import matlab.unittest.TestRunner
import matlab.unittest.TestSuite
import matlab.unittest.plugins.XMLPlugin

if nargin < 1
    outputFolder = '';
end
if nargin < 2
    include = [];
end

here = fileparts(mfilename('fullpath'));
root = fileparts(here);
addpath(root, fullfile(here, 'support'));

if isempty(include)
    suite = TestSuite.fromFolder(here);
else
    include = cellstr(include);
    parts = cell(1, numel(include));
    for i = 1:numel(include)
        parts{i} = TestSuite.fromFile(fullfile(here, [char(include{i}) '.m']));
    end
    suite = [parts{:}];
end

runner = TestRunner.withTextOutput();
if ~isempty(outputFolder) && strlength(string(outputFolder)) > 0
    outputFolder = char(outputFolder);
    if ~isfolder(outputFolder)
        mkdir(outputFolder);
    end
    runner.addPlugin(XMLPlugin.producingJUnitFormat(fullfile(outputFolder, 'junit.xml')));
end

results = runner.run(suite);

% Per class summary: passed, failed, incomplete (skipped).
names = arrayfun(@(r) extractBefore(string(r.Name) + "/", "/"), results);
classes = unique(names, 'stable');
fprintf('\n%-26s %6s %6s %6s %6s\n', 'Test class', 'Total', 'Passed', 'Failed', 'Skipped');
for i = 1:numel(classes)
    sel = results(names == classes(i));
    fprintf('%-26s %6d %6d %6d %6d\n', classes(i), numel(sel), nnz([sel.Passed]), ...
        nnz([sel.Failed]), nnz([sel.Incomplete]));
end
fprintf('%-26s %6d %6d %6d %6d\n\n', 'All', numel(results), nnz([results.Passed]), ...
    nnz([results.Failed]), nnz([results.Incomplete]));

if any([results.Failed])
    failed = string({results([results.Failed]).Name});
    error('runAllTests:failed', '%d test(s) failed:\n  %s', numel(failed), strjoin(failed, '\n  '));
end
end
