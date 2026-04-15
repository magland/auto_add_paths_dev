function auto_add_paths(pkg_dir, out_file)
% AUTO_ADD_PATHS  Heuristically determine the relative paths to addpath()
% for a MATLAB package located at PKG_DIR. Write the list (one path per
% line, relative to PKG_DIR) to OUT_FILE.
%
%   auto_add_paths(pkg_dir, out_file)

    if nargin < 2
        out_file = 'paths.txt';
    end
    pkg_dir = char(pkg_dir);
    pkg_dir = regexprep(pkg_dir, '[/\\]+$', '');

    % Directory names that should never be added to the path.
    skip_names = { ...
        'test', 'tests', 'testing', 'unittest', 'unittests', ...
        'demo', 'demos', ...
        'example', 'examples', 'tutorial', 'tutorials', ...
        'benchmark', 'benchmarks', ...
        'doc', 'docs', 'documentation', 'man', ...
        'html', 'website', ...
        'build', 'buildutils', 'bin', 'obj', 'dist', 'target', ...
        'node_modules', '__pycache__', ...
        'paper', ...
        'dev', 'sandbox', 'scratch', ...
        '.git', '.github', '.svn', '.hg', '.circleci', '.vscode', '.idea'};

    paths = {};
    paths = walk(pkg_dir, pkg_dir, skip_names, paths);

    % De-duplicate while preserving order.
    [~, idx] = unique(paths, 'stable');
    paths = paths(idx);

    fid = fopen(out_file, 'w');
    cleaner = onCleanup(@() fclose(fid));
    for k = 1:numel(paths)
        fprintf(fid, '%s\n', paths{k});
    end
end

function paths = walk(root, dir_path, skip_names, paths)
    entries = dir(dir_path);

    m_files = {};
    has_special = false;  % @class / +namespace / private subfolder
    for k = 1:numel(entries)
        e = entries(k);
        if e.isdir
            if is_namespace_or_class(e.name)
                has_special = true;
            elseif strcmpi(e.name, 'private')
                has_special = true;
            end
        else
            [~, ~, ext] = fileparts(e.name);
            if strcmpi(ext, '.m')
                m_files{end+1} = e.name; %#ok<AGROW>
            elseif ~isempty(regexpi(ext, '^\.mex[^.]*$', 'once'))
                m_files{end+1} = e.name; %#ok<AGROW>
            end
        end
    end

    include = has_special || ~isempty(m_files);

    % Filter out directories whose only .m files are development / build
    % scripts (buildfile.m, createMLTBX.m, *_dev.m, install.m, setup.m).
    % If that filter empties the .m list and there's no special folder, skip.
    if include && ~has_special
        keep = false;
        for k = 1:numel(m_files)
            if ~is_build_only_script(m_files{k})
                keep = true;
                break;
            end
        end
        include = keep;
    end

    if include
        paths{end+1} = relpath(root, dir_path); %#ok<AGROW>
    end

    for k = 1:numel(entries)
        e = entries(k);
        if ~e.isdir, continue; end
        if strcmp(e.name, '.') || strcmp(e.name, '..'), continue; end
        if is_namespace_or_class(e.name), continue; end
        if strcmpi(e.name, 'private'), continue; end
        if any(strcmpi(e.name, skip_names)), continue; end
        if is_skip_prefix(e.name), continue; end
        if is_platform_dir(e.name), continue; end
        paths = walk(root, fullfile(dir_path, e.name), skip_names, paths);
    end
end

function tf = is_build_only_script(name)
    % Return true if the filename looks like a build / install / dev
    % script rather than a runtime library function.
    [~, base, ~] = fileparts(name);
    base_l = lower(base);
    exact = {'buildfile', 'build', 'make', 'makefile', ...
             'install', 'setup', 'uninstall', ...
             'createmltbx', 'packagetoolbox', 'contents'};
    if any(strcmp(base_l, exact))
        tf = true; return;
    end
    % Suffix / prefix patterns.
    patterns = {'_dev$', '_install$', '_setup$', '_build$', ...
                '^install_', '^setup_', '^build_', ...
                '^compile', '^mex_compile', '^make_'};
    for k = 1:numel(patterns)
        if ~isempty(regexp(base_l, patterns{k}, 'once'))
            tf = true; return;
        end
    end
    tf = false;
end

function tf = is_namespace_or_class(name)
    % A directory name qualifies as a MATLAB namespace (+foo) or class
    % folder (@foo) only if the part after the sigil is a legal MATLAB
    % identifier. "+acquisition.type.File" is NOT a namespace — it's a
    % MATLAB Project metadata directory that happens to start with '+'.
    if ~startsWith(name, '+') && ~startsWith(name, '@')
        tf = false; return;
    end
    inner = name(2:end);
    tf = ~isempty(regexp(inner, '^[A-Za-z][A-Za-z0-9_]*$', 'once'));
end

function tf = is_skip_prefix(name)
    % Directory names that always denote examples / demos / tests /
    % benchmarks regardless of suffix.
    prefixes = {'example', 'demo', 'tutorial', 'benchmark', 'sandbox'};
    nlow = lower(name);
    for k = 1:numel(prefixes)
        if startsWith(nlow, prefixes{k})
            tf = true; return;
        end
    end
    tf = false;
end

function tf = is_platform_dir(name)
    % Directories named after a build target / OS-arch that hold prebuilt
    % binaries (e.g. octave/gnu-linux-x86_64). Users pick one via a loader
    % or copy its contents into `private/`; they do NOT addpath it.
    nlow = lower(name);
    % Exact MATLAB/Octave architecture identifiers.
    exact = {'glnxa64', 'glnx86', 'maci', 'maci64', 'maca64', ...
             'pcwin', 'pcwin32', 'pcwin64', 'win32', 'win64', ...
             'sol2', 'mingw32', 'mingw64'};
    if any(strcmp(nlow, exact))
        tf = true; return;
    end
    % Composite <os>-<arch> / <os>_<arch> form (must include a separator).
    patterns = {'^darwin[-_]', '^linux[-_]', '^gnu-linux[-_]?', ...
                '^mac[-_]', '^macos[-_]', '^mingw[0-9]*[-_]', ...
                '^win[-_]', '^win32[-_]', '^win64[-_]', ...
                '^freebsd[-_]', '^cygwin[-_]'};
    for k = 1:numel(patterns)
        if ~isempty(regexp(nlow, patterns{k}, 'once'))
            tf = true; return;
        end
    end
    tf = false;
end

function r = relpath(root, p)
    if strcmp(root, p)
        r = '.';
        return;
    end
    r = p(numel(root)+1:end);
    r = regexprep(r, '^[/\\]+', '');
    r = strrep(r, '\', '/');
end
