/* Optional test host for the exact Ruby DLL bundled with SketchUp 2019.
 * Not shipped in the extension. Usage: runner.exe <SketchUp directory> ruby-args...
 * RUBYLIB must include Tools/RubyStdLib and its platform_specific directory.
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>

typedef void (__cdecl *sysinit_fn)(int *, char ***);
typedef void (__cdecl *stack_fn)(void *);
typedef void (__cdecl *init_fn)(void);
typedef void * (__cdecl *options_fn)(int, char **);
typedef int (__cdecl *run_fn)(void *);

int wmain(int argc, wchar_t **wide)
{
    HMODULE dll;
    wchar_t path[32768];
    char **args;
    int count, i, stack_anchor;
    sysinit_fn sysinit;
    stack_fn init_stack;
    init_fn init;
    options_fn options;
    run_fn run;
    if (argc < 3) return 2;
    SetDllDirectoryW(wide[1]);
    if (swprintf_s(path, 32768, L"%s\\x64-msvcrt-ruby250.dll", wide[1]) < 0) return 2;
    dll = LoadLibraryW(path);
    if (!dll) { fprintf(stderr, "Cannot load Ruby DLL: %lu\n", GetLastError()); return 2; }
    sysinit = (sysinit_fn)GetProcAddress(dll, "ruby_sysinit");
    init_stack = (stack_fn)GetProcAddress(dll, "ruby_init_stack");
    init = (init_fn)GetProcAddress(dll, "ruby_init");
    options = (options_fn)GetProcAddress(dll, "ruby_options");
    run = (run_fn)GetProcAddress(dll, "ruby_run_node");
    if (!sysinit || !init_stack || !init || !options || !run) return 2;
    count = argc - 1;
    args = (char **)calloc((size_t)count + 1, sizeof(char *));
    if (!args) return 2;
    for (i = 0; i < count; ++i) {
        const wchar_t *arg = wide[i == 0 ? 0 : i + 1];
        int length = WideCharToMultiByte(CP_UTF8, 0, arg, -1, NULL, 0, NULL, NULL);
        args[i] = (char *)malloc((size_t)length);
        if (!args[i]) return 2;
        WideCharToMultiByte(CP_UTF8, 0, arg, -1, args[i], length, NULL, NULL);
    }
    sysinit(&count, &args);
    /* On Windows sysinit rebuilds argv from GetCommandLineW. Remove our host argument. */
    for (i = 1; i < count; ++i) args[i] = args[i + 1];
    --count;
    init_stack(&stack_anchor);
    init();
    return run(options(count, args));
}
