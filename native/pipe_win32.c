/*
 * Plain C ABI, no Ruby ABI and no CRT dependency.
 * Ruby 2.5 Fiddle stores errno in win32_last_error (Ruby issue #11579).
 * Capture GetLastError inside the SAME native call, before Fiddle/Ruby/GVL
 * transitions can overwrite it. Each call owns its DWORD output buffer.
 */
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0600
#endif
#include <windows.h>
#ifndef _WIN64
#error Build this helper for Windows x64 only.
#endif

#define EXPORT __declspec(dllexport)

EXPORT DWORD sp_AbiVersion(void) { return 1; }

EXPORT HANDLE sp_CreateFileW(LPCWSTR name, DWORD access, DWORD share,
    LPSECURITY_ATTRIBUTES security, DWORD disposition, DWORD flags,
    HANDLE template_file, DWORD *error)
{
    HANDLE result = CreateFileW(name, access, share, security, disposition, flags, template_file);
    *error = result == INVALID_HANDLE_VALUE ? GetLastError() : ERROR_SUCCESS;
    return result;
}

EXPORT HANDLE sp_CreateEventW(LPSECURITY_ATTRIBUTES security, BOOL manual,
    BOOL initial, LPCWSTR name, DWORD *error)
{
    HANDLE result = CreateEventW(security, manual, initial, name);
    *error = result == NULL ? GetLastError() : ERROR_SUCCESS;
    return result;
}

EXPORT BOOL sp_ReadFile(HANDLE pipe, LPVOID buffer, DWORD size,
    LPDWORD count, LPOVERLAPPED operation, DWORD *error)
{
    BOOL result = ReadFile(pipe, buffer, size, count, operation);
    *error = result ? ERROR_SUCCESS : GetLastError();
    return result;
}

EXPORT BOOL sp_WriteFile(HANDLE pipe, LPCVOID buffer, DWORD size,
    LPDWORD count, LPOVERLAPPED operation, DWORD *error)
{
    BOOL result = WriteFile(pipe, buffer, size, count, operation);
    *error = result ? ERROR_SUCCESS : GetLastError();
    return result;
}

EXPORT BOOL sp_GetOverlappedResult(HANDLE pipe, LPOVERLAPPED operation,
    LPDWORD count, BOOL wait, DWORD *error)
{
    BOOL result = GetOverlappedResult(pipe, operation, count, wait);
    *error = result ? ERROR_SUCCESS : GetLastError();
    return result;
}

EXPORT BOOL sp_CancelIoEx(HANDLE pipe, LPOVERLAPPED operation, DWORD *error)
{
    BOOL result = CancelIoEx(pipe, operation);
    *error = result ? ERROR_SUCCESS : GetLastError();
    return result;
}

EXPORT BOOL sp_CloseHandle(HANDLE handle, DWORD *error)
{
    BOOL result = CloseHandle(handle);
    *error = result ? ERROR_SUCCESS : GetLastError();
    return result;
}
