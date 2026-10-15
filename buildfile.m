function plan = buildfile
%BUILDFILE Build plan of the OpenAlgo MATLAB library (run with buildtool).
%   buildtool check     static code checks of +openalgo and tests
%   buildtool test      run the test suite, JUnit XML in test-results/
%   buildtool package   build release/openalgo-matlab-<version>.mltbx
%   buildtool           check, then test
%
%   The live sandbox tests skip themselves unless OPENALGO_API_KEY is set.

plan = buildplan(localfunctions);
plan("test").Dependencies = "check";
plan("package").Dependencies = "test";
plan.DefaultTasks = ["check", "test"];
end

function checkTask(~)
% Static code checks of the library and the tests (fails on errors only).
root = fileparts(mfilename('fullpath'));
issues = codeIssues(string({fullfile(root, '+openalgo'), fullfile(root, 'tests')}));
errors = issues.Issues(issues.Issues.Severity == "error", :);
disp(issues);
assert(isempty(errors), 'Code issues with severity error were found.');
end

function testTask(~)
% Run the whole suite and write JUnit XML to test-results/junit.xml.
root = fileparts(mfilename('fullpath'));
addpath(fullfile(root, 'tests'));
runAllTests(fullfile(root, 'test-results'));
end

function packageTask(~)
% Package +openalgo, the license and the changelog as a MATLAB toolbox.
root = fileparts(mfilename('fullpath'));
addpath(root);
version = openalgo.version();
opts = matlab.addons.toolbox.ToolboxOptions(root, '92510f26-aee6-4878-b3b7-770fdef06db0');
opts.ToolboxName = 'OpenAlgo';
opts.ToolboxVersion = version;
opts.AuthorName = 'Rajandran R';
opts.Summary = 'MATLAB client for the OpenAlgo REST API and WebSocket market data feed.';
opts.Description = ['A MATLAB port of the OpenAlgo Python SDK 2.0.5 (indicators excluded): ' ...
    'orders, GTT orders, market data, account, options, strategy module, notifications, ' ...
    'market calendar, the strategy webhook and the WebSocket feed, plus methods for the ' ...
    'server endpoints the Python SDK lacks.'];
opts.ToolboxFiles = string({fullfile(root, '+openalgo'), fullfile(root, 'LICENSE'), fullfile(root, 'CHANGELOG.md')});
opts.ToolboxMatlabPath = root;
opts.MinimumMatlabRelease = 'R2022b';
opts.SupportedPlatforms.Win64 = true;
opts.SupportedPlatforms.Maci64 = true;
opts.SupportedPlatforms.Glnxa64 = true;
outDir = fullfile(root, 'release');
if ~isfolder(outDir)
    mkdir(outDir);
end
opts.OutputFile = fullfile(outDir, ['openalgo-matlab-' version '.mltbx']);
matlab.addons.toolbox.packageToolbox(opts);
fprintf('Toolbox written to %s\n', opts.OutputFile);
end
