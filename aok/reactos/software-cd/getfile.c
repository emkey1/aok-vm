/*
 * getfile URL FILE SHA1 -- for AOK VM's "Get Programs" (GET.CMD) on ReactOS: FILE from URL, unless FILE is there
 * already with that SHA-1. Downloaded over WinInet under a user agent of its own, into FILE.part, checked, then
 * renamed; three tries. Exit 0 when FILE has the SHA-1, 1 when it could not be had. ReactOS's own dwnl goes through
 * urlmon, whose user agent is Internet Explorer 8's, which SourceForge answers with "403 No"; a plain agent gets the
 * file. Win32 alone, no C library (ReactOS has no UCRT), built by put-on-disk.sh with zig cc.
 */
#include <windows.h>
#include <wininet.h>
#include <wincrypt.h>

static BYTE buf[65536];

static void say(const WCHAR *fmt, ...)
{
    WCHAR b[1024];
    char a[2048];
    va_list ap;
    DWORD n, w;

    va_start(ap, fmt);
    n = wvsprintfW(b, fmt, ap);
    va_end(ap);
    if (!WriteConsoleW(GetStdHandle(STD_OUTPUT_HANDLE), b, n, &w, NULL)) {
        n = WideCharToMultiByte(CP_ACP, 0, b, n, a, sizeof(a), NULL, NULL);
        WriteFile(GetStdHandle(STD_OUTPUT_HANDLE), a, n, &w, NULL);
    }
}

/* the file's SHA-1 in lower-case hex, or FALSE if it cannot be read */
static BOOL sha1_file(const WCHAR *path, WCHAR hex[41])
{
    HANDLE f;
    HCRYPTPROV prov;
    HCRYPTHASH h;
    BYTE d[20];
    DWORD n, dl = sizeof(d), i;
    BOOL ok = FALSE;

    f = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, FILE_FLAG_SEQUENTIAL_SCAN, NULL);
    if (f == INVALID_HANDLE_VALUE)
        return FALSE;
    if (CryptAcquireContextW(&prov, NULL, NULL, PROV_RSA_FULL, CRYPT_VERIFYCONTEXT)) {
        if (CryptCreateHash(prov, CALG_SHA1, 0, 0, &h)) {
            while (ReadFile(f, buf, sizeof(buf), &n, NULL) && n)
                CryptHashData(h, buf, n, 0);
            if (CryptGetHashParam(h, HP_HASHVAL, d, &dl, 0) && dl == sizeof(d)) {
                for (i = 0; i < sizeof(d); i++) {
                    hex[2 * i] = L"0123456789abcdef"[d[i] >> 4];
                    hex[2 * i + 1] = L"0123456789abcdef"[d[i] & 15];
                }
                hex[40] = 0;
                ok = TRUE;
            }
            CryptDestroyHash(h);
        }
        CryptReleaseContext(prov, 0);
    }
    CloseHandle(f);
    return ok;
}

static BOOL has_sha1(const WCHAR *path, const WCHAR *want)
{
    WCHAR hex[41];

    return sha1_file(path, hex) && lstrcmpiW(hex, want) == 0;
}

/* URL into PATH; FALSE, having said why, if the server or the network says no */
static BOOL download(HINTERNET net, const WCHAR *url, const WCHAR *path)
{
    HINTERNET u;
    HANDLE f;
    DWORD code = 0, total = 0, got = 0, n, w, len, shown = (DWORD)-1;
    BOOL ok = FALSE;

    u = InternetOpenUrlW(net, url, NULL, 0, INTERNET_FLAG_RELOAD | INTERNET_FLAG_NO_CACHE_WRITE |
                         INTERNET_FLAG_NO_UI | INTERNET_FLAG_IGNORE_REDIRECT_TO_HTTP |
                         INTERNET_FLAG_IGNORE_REDIRECT_TO_HTTPS, 0);
    if (!u) {
        say(L"  the network said no (error %lu)\r\n", GetLastError());
        return FALSE;
    }
    len = sizeof(code);
    if (HttpQueryInfoW(u, HTTP_QUERY_STATUS_CODE | HTTP_QUERY_FLAG_NUMBER, &code, &len, NULL) && code != 200) {
        say(L"  the server said %lu\r\n", code);
        InternetCloseHandle(u);
        return FALSE;
    }
    len = sizeof(total);
    if (!HttpQueryInfoW(u, HTTP_QUERY_CONTENT_LENGTH | HTTP_QUERY_FLAG_NUMBER, &total, &len, NULL))
        total = 0;
    f = CreateFileW(path, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (f == INVALID_HANDLE_VALUE) {
        say(L"  cannot write %s (error %lu)\r\n", path, GetLastError());
        InternetCloseHandle(u);
        return FALSE;
    }
    for (;;) {
        if (!InternetReadFile(u, buf, sizeof(buf), &n)) {
            say(L"\r\n  the download stopped (error %lu)\r\n", GetLastError());
            break;
        }
        if (n == 0) {
            ok = TRUE;
            break;
        }
        if (!WriteFile(f, buf, n, &w, NULL) || w != n) {
            say(L"\r\n  cannot write %s (error %lu)\r\n", path, GetLastError());
            break;
        }
        got += n;
        if (total && (DWORD)MulDiv(got, 100, total) != shown) {
            shown = MulDiv(got, 100, total);
            say(L"\r  %lu%% of %lu KB", shown, total / 1024);
        } else if (!total && got / 1048576 != shown) {
            shown = got / 1048576;
            say(L"\r  %lu MB", shown);
        }
    }
    say(L"\r\n");
    CloseHandle(f);
    InternetCloseHandle(u);
    return ok;
}

static int getfile(int argc, WCHAR **argv)
{
    const WCHAR *url, *file, *sha;
    WCHAR part[MAX_PATH + 8];
    HINTERNET net;
    int t;

    if (argc != 4) {
        say(L"usage: getfile URL FILE SHA1\r\n");
        return 2;
    }
    url = argv[1];
    file = argv[2];
    sha = argv[3];
    if (has_sha1(file, sha))
        return 0;
    if (lstrlenW(file) > MAX_PATH)
        return 1;
    lstrcpyW(part, file);
    lstrcatW(part, L".part");
    net = InternetOpenW(L"AOK-VM-GetPrograms/1.0", INTERNET_OPEN_TYPE_PRECONFIG, NULL, NULL, 0);
    if (!net) {
        say(L"  no network (error %lu)\r\n", GetLastError());
        return 1;
    }
    for (t = 1; t <= 3; t++) {
        say(L"  %s\r\n", url);
        if (download(net, url, part)) {
            if (has_sha1(part, sha)) {
                DeleteFileW(file);
                if (MoveFileW(part, file)) {
                    InternetCloseHandle(net);
                    return 0;
                }
                say(L"  cannot rename %s (error %lu)\r\n", part, GetLastError());
            } else {
                say(L"  not the file it should be (its SHA-1 is not %s)\r\n", sha);
            }
        }
        DeleteFileW(part);
        if (t < 3) {
            say(L"  trying again\r\n");
            Sleep(3000);
        }
    }
    InternetCloseHandle(net);
    return 1;
}

void start(void)
{
    int argc;
    WCHAR **argv = CommandLineToArgvW(GetCommandLineW(), &argc);

    ExitProcess(argv ? getfile(argc, argv) : 2);
}
