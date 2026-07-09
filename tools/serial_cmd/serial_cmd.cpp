#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif

#include <windows.h>

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

namespace {

constexpr DWORD kCommandTimeoutMs = 30000;

std::string narrow_ascii(const wchar_t* value) {
    std::string out;
    if (!value) return out;
    while (*value) {
        wchar_t ch = *value++;
        out.push_back(ch >= 0 && ch < 128 ? static_cast<char>(ch) : '?');
    }
    return out;
}

void write_all(HANDLE h, const char* data, DWORD len) {
    while (len > 0) {
        DWORD written = 0;
        if (!WriteFile(h, data, len, &written, nullptr) || written == 0) {
            std::printf("SERIAL_WRITE_FAILED err=%lu\n", GetLastError());
            std::fflush(stdout);
            return;
        }
        data += written;
        len -= written;
    }
}

void write_text(HANDLE h, const std::string& text) {
    write_all(h, text.data(), static_cast<DWORD>(text.size()));
}

void write_line(HANDLE h, const std::string& text) {
    write_text(h, text);
    write_text(h, "\r\n");
}

std::string trim(std::string s) {
    auto is_space = [](unsigned char c) { return std::isspace(c) != 0; };
    s.erase(s.begin(), std::find_if_not(s.begin(), s.end(), is_space));
    s.erase(std::find_if_not(s.rbegin(), s.rend(), is_space).base(), s.end());
    return s;
}

std::string lower(std::string s) {
    for (char& ch : s) {
        ch = static_cast<char>(std::tolower(static_cast<unsigned char>(ch)));
    }
    return s;
}

std::wstring widen(const std::string& s) {
    if (s.empty()) return std::wstring();
    int needed = MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), nullptr, 0);
    if (needed <= 0) {
        needed = MultiByteToWideChar(CP_ACP, 0, s.data(), static_cast<int>(s.size()), nullptr, 0);
        std::wstring out(static_cast<size_t>(needed), L'\0');
        MultiByteToWideChar(CP_ACP, 0, s.data(), static_cast<int>(s.size()), out.data(), needed);
        return out;
    }
    std::wstring out(static_cast<size_t>(needed), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), out.data(), needed);
    return out;
}

std::string base64_encode(const std::vector<unsigned char>& data) {
    static constexpr char table[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    std::string out;
    out.reserve(((data.size() + 2) / 3) * 4);
    for (size_t i = 0; i < data.size(); i += 3) {
        unsigned int v = data[i] << 16;
        if (i + 1 < data.size()) v |= data[i + 1] << 8;
        if (i + 2 < data.size()) v |= data[i + 2];
        out.push_back(table[(v >> 18) & 0x3f]);
        out.push_back(table[(v >> 12) & 0x3f]);
        out.push_back(i + 1 < data.size() ? table[(v >> 6) & 0x3f] : '=');
        out.push_back(i + 2 < data.size() ? table[v & 0x3f] : '=');
    }
    return out;
}

int base64_value(char ch) {
    if (ch >= 'A' && ch <= 'Z') return ch - 'A';
    if (ch >= 'a' && ch <= 'z') return ch - 'a' + 26;
    if (ch >= '0' && ch <= '9') return ch - '0' + 52;
    if (ch == '+') return 62;
    if (ch == '/') return 63;
    return -1;
}

bool base64_decode(const std::string& input, std::vector<unsigned char>& out) {
    out.clear();
    int val = 0;
    int valb = -8;
    for (unsigned char ch : input) {
        if (std::isspace(ch)) continue;
        if (ch == '=') break;
        int d = base64_value(static_cast<char>(ch));
        if (d < 0) return false;
        val = (val << 6) + d;
        valb += 6;
        if (valb >= 0) {
            out.push_back(static_cast<unsigned char>((val >> valb) & 0xff));
            valb -= 8;
        }
    }
    return true;
}

bool read_file_bytes(const std::string& path, std::vector<unsigned char>& data) {
    std::ifstream in(path, std::ios::binary);
    if (!in) return false;
    data.assign(std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>());
    return true;
}

bool write_file_bytes(const std::string& path, const std::vector<unsigned char>& data) {
    std::ofstream out(path, std::ios::binary | std::ios::trunc);
    if (!out) return false;
    out.write(reinterpret_cast<const char*>(data.data()), static_cast<std::streamsize>(data.size()));
    return static_cast<bool>(out);
}

void handle_get(HANDLE serial, const std::string& path) {
    std::vector<unsigned char> data;
    if (!read_file_bytes(path, data)) {
        write_line(serial, "<<<FILE_ERROR get failed>>>");
        return;
    }
    write_line(serial, "<<<FILE_INFO " + path + " size=" + std::to_string(data.size()) + ">>>");
}

void handle_get_b64(HANDLE serial, const std::string& path) {
    std::vector<unsigned char> data;
    if (!read_file_bytes(path, data)) {
        write_line(serial, "<<<FILE_ERROR get failed>>>");
        return;
    }
    write_line(serial, "<<<FILE_BEGIN " + path + " size=" + std::to_string(data.size()) + " b64>>>");
    std::string encoded = base64_encode(data);
    constexpr size_t chunk = 120;
    for (size_t i = 0; i < encoded.size(); i += chunk) {
        write_line(serial, encoded.substr(i, chunk));
    }
    write_line(serial, "<<<FILE_END>>>");
}

void handle_put(HANDLE serial, const std::string& path, const std::string& encoded) {
    std::vector<unsigned char> data;
    if (!base64_decode(encoded, data)) {
        write_line(serial, "<<<PUT_ERROR invalid_base64>>>");
        return;
    }
    if (!write_file_bytes(path, data)) {
        write_line(serial, "<<<PUT_ERROR write_failed>>>");
        return;
    }
    write_line(serial, "<<<PUT_OK " + path + " size=" + std::to_string(data.size()) + ">>>");
}

HANDLE open_serial() {
    const wchar_t* names[] = {L"COM1", L"COM1:", L"\\\\.\\COM1"};
    DWORD start = GetTickCount();
    DWORD deadline = start + 60000;
    while (true) {
        for (const wchar_t* name : names) {
            DWORD elapsed_ms = GetTickCount() - start;
            std::string device = narrow_ascii(name);
            std::printf("SERIAL_OPEN_TRY t=%lums name=%s\n", elapsed_ms, device.c_str());
            std::fflush(stdout);
            HANDLE h = CreateFileW(name, GENERIC_READ | GENERIC_WRITE, 0, nullptr, OPEN_EXISTING, 0, nullptr);
            if (h != INVALID_HANDLE_VALUE) {
                std::printf("SERIAL_OPEN_OK t=%lums name=%s\n", GetTickCount() - start, device.c_str());
                std::fflush(stdout);
                DCB dcb{};
                dcb.DCBlength = sizeof(dcb);
                if (GetCommState(h, &dcb)) {
                    dcb.BaudRate = CBR_115200;
                    dcb.ByteSize = 8;
                    dcb.Parity = NOPARITY;
                    dcb.StopBits = ONESTOPBIT;
                    SetCommState(h, &dcb);
                }
                COMMTIMEOUTS timeouts{};
                timeouts.ReadIntervalTimeout = 50;
                timeouts.ReadTotalTimeoutConstant = 50;
                timeouts.ReadTotalTimeoutMultiplier = 10;
                timeouts.WriteTotalTimeoutConstant = 1000;
                SetCommTimeouts(h, &timeouts);
                return h;
            }
            std::printf("SERIAL_OPEN_FAIL t=%lums name=%s err=%lu\n", GetTickCount() - start, device.c_str(), GetLastError());
            std::fflush(stdout);
        }
        if (GetTickCount() >= deadline) break;
        Sleep(1000);
    }
    return INVALID_HANDLE_VALUE;
}

bool read_line(HANDLE h, std::string& line) {
    line.clear();
    while (true) {
        char ch = 0;
        DWORD read = 0;
        if (!ReadFile(h, &ch, 1, &read, nullptr)) {
            return false;
        }
        if (read == 0) {
            Sleep(10);
            continue;
        }
        if (ch == '\n') return true;
        if (ch != '\r') line.push_back(ch);
    }
}

DWORD run_command(HANDLE serial, const std::string& command) {
    SECURITY_ATTRIBUTES sa{};
    sa.nLength = sizeof(sa);
    sa.bInheritHandle = TRUE;

    HANDLE read_pipe = nullptr;
    HANDLE write_pipe = nullptr;
    if (!CreatePipe(&read_pipe, &write_pipe, &sa, 0)) {
        write_line(serial, "CreatePipe failed");
        return 1;
    }
    SetHandleInformation(read_pipe, HANDLE_FLAG_INHERIT, 0);

    std::wstring cmd = L"cmd.exe /d /c " + widen(command);
    std::vector<wchar_t> cmdline(cmd.begin(), cmd.end());
    cmdline.push_back(L'\0');

    STARTUPINFOW si{};
    si.cb = sizeof(si);
    si.dwFlags = STARTF_USESTDHANDLES | STARTF_USESHOWWINDOW;
    si.wShowWindow = SW_HIDE;
    si.hStdOutput = write_pipe;
    si.hStdError = write_pipe;
    si.hStdInput = GetStdHandle(STD_INPUT_HANDLE);

    PROCESS_INFORMATION pi{};
    BOOL ok = CreateProcessW(nullptr, cmdline.data(), nullptr, nullptr, TRUE, 0, nullptr, nullptr, &si, &pi);
    CloseHandle(write_pipe);
    if (!ok) {
        CloseHandle(read_pipe);
        write_line(serial, "CreateProcess failed");
        return 1;
    }

    DWORD start = GetTickCount();
    DWORD exit_code = STILL_ACTIVE;
    char buffer[1024];
    while (true) {
        DWORD available = 0;
        if (PeekNamedPipe(read_pipe, nullptr, 0, nullptr, &available, nullptr) && available > 0) {
            DWORD to_read = std::min<DWORD>(available, sizeof(buffer));
            DWORD read = 0;
            if (ReadFile(read_pipe, buffer, to_read, &read, nullptr) && read > 0) {
                write_all(serial, buffer, read);
            }
        }

        if (WaitForSingleObject(pi.hProcess, 0) == WAIT_OBJECT_0) {
            if (!PeekNamedPipe(read_pipe, nullptr, 0, nullptr, &available, nullptr) || available == 0) break;
        }

        if (GetTickCount() - start > kCommandTimeoutMs) {
            TerminateProcess(pi.hProcess, 124);
            write_line(serial, "[timeout]");
            break;
        }
        Sleep(10);
    }

    GetExitCodeProcess(pi.hProcess, &exit_code);
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
    CloseHandle(read_pipe);
    return exit_code;
}

std::string get_command_line_utf8() {
    LPWSTR wide_cmd = GetCommandLineW();
    if (!wide_cmd) return {};
    int needed = WideCharToMultiByte(CP_UTF8, 0, wide_cmd, -1, nullptr, 0, nullptr, nullptr);
    if (needed <= 0) return {};
    std::string out(static_cast<size_t>(needed - 1), '\0');
    WideCharToMultiByte(CP_UTF8, 0, wide_cmd, -1, out.data(), needed, nullptr, nullptr);
    return out;
}

std::string find_autorun_command() {
    std::string cmdline = get_command_line_utf8();
    std::string marker = " --autorun ";
    size_t pos = cmdline.find(marker);
    if (pos == std::string::npos) return {};
    std::string cmd = trim(cmdline.substr(pos + marker.size()));
    if (cmd.size() >= 2 && cmd.front() == '"' && cmd.back() == '"') {
        cmd = cmd.substr(1, cmd.size() - 2);
    }
    return cmd;
}

}  // namespace

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
    HANDLE serial = open_serial();
    if (serial == INVALID_HANDLE_VALUE) {
        std::printf("SERIAL_OPEN_ALL_FAILED err=%lu\n", GetLastError());
        std::fflush(stdout);
        return 2;
    }

    write_line(serial, "PECMD_COMPAT_SERIAL_CMD_READY");
    write_line(serial, "Commands: autorun <cmd>, get <path>, get-b64 <path>, put <path> <base64>, put-begin <path> <size>, put-chunk <base64>, put-end, exit, reboot, or any cmd.exe command.");

    std::string autorun = find_autorun_command();
    if (!autorun.empty()) {
        write_line(serial, "<<<AUTORUN_BEGIN " + autorun + ">>>");
        DWORD rc = run_command(serial, autorun);
        write_line(serial, "<<<AUTORUN_END rc=" + std::to_string(rc) + ">>>");
        CloseHandle(serial);
        return static_cast<int>(rc);
    }

    std::string line;
    bool receiving_file = false;
    std::string receive_path;
    size_t receive_expected = 0;
    std::vector<unsigned char> receive_data;
    while (true) {
        write_text(serial, "pecmd> ");
        if (!read_line(serial, line)) break;
        line = trim(line);
        if (line.empty()) continue;

        write_line(serial, "<<<CMD_BEGIN " + line + ">>>");
        std::string cmd = lower(line);
        if (cmd == "exit" || cmd == "quit") {
            write_line(serial, "<<<CMD_END rc=0>>>");
            break;
        }
        if (cmd == "reboot") {
            write_line(serial, "<<<CMD_END rc=0 rebooting>>>");
            run_command(serial, "wpeutil reboot");
            break;
        }

        if (line.rfind("get ", 0) == 0) {
            handle_get(serial, trim(line.substr(4)));
            write_line(serial, "<<<CMD_END rc=0>>>");
            continue;
        }

        if (line.rfind("get-b64 ", 0) == 0) {
            handle_get_b64(serial, trim(line.substr(8)));
            write_line(serial, "<<<CMD_END rc=0>>>");
            continue;
        }

        if (line.rfind("autorun ", 0) == 0) {
            std::string target = trim(line.substr(8));
            write_line(serial, "<<<AUTORUN_BEGIN " + target + ">>>");
            DWORD rc = run_command(serial, target);
            write_line(serial, "<<<AUTORUN_END rc=" + std::to_string(rc) + ">>>");
            write_line(serial, "<<<CMD_END rc=" + std::to_string(rc) + ">>>");
            continue;
        }

        if (line.rfind("put ", 0) == 0) {
            std::string rest = trim(line.substr(4));
            size_t sep = rest.find(' ');
            if (sep == std::string::npos) {
                write_line(serial, "<<<PUT_ERROR usage: put <path> <base64>>>");
            } else {
                handle_put(serial, rest.substr(0, sep), trim(rest.substr(sep + 1)));
            }
            write_line(serial, "<<<CMD_END rc=0>>>");
            continue;
        }

        if (line.rfind("put-begin ", 0) == 0) {
            std::string rest = trim(line.substr(10));
            size_t sep = rest.rfind(' ');
            if (sep == std::string::npos) {
                write_line(serial, "<<<PUT_ERROR usage: put-begin <path> <size>>>");
            } else {
                receive_path = rest.substr(0, sep);
                receive_expected = static_cast<size_t>(std::strtoull(rest.substr(sep + 1).c_str(), nullptr, 10));
                receive_data.clear();
                receiving_file = true;
                write_line(serial, "<<<PUT_BEGIN_OK " + receive_path + " size=" + std::to_string(receive_expected) + ">>>");
            }
            write_line(serial, "<<<CMD_END rc=0>>>");
            continue;
        }

        if (line.rfind("put-chunk ", 0) == 0) {
            if (!receiving_file) {
                write_line(serial, "<<<PUT_ERROR no_active_put>>>");
            } else {
                std::vector<unsigned char> chunk;
                if (!base64_decode(trim(line.substr(10)), chunk)) {
                    write_line(serial, "<<<PUT_ERROR invalid_chunk_base64>>>");
                } else {
                    receive_data.insert(receive_data.end(), chunk.begin(), chunk.end());
                    write_line(serial, "<<<PUT_CHUNK_OK received=" + std::to_string(receive_data.size()) + ">>>");
                }
            }
            write_line(serial, "<<<CMD_END rc=0>>>");
            continue;
        }

        if (line == "put-end") {
            if (!receiving_file) {
                write_line(serial, "<<<PUT_ERROR no_active_put>>>");
            } else if (receive_data.size() != receive_expected) {
                write_line(serial, "<<<PUT_ERROR size_mismatch expected=" + std::to_string(receive_expected) + " actual=" + std::to_string(receive_data.size()) + ">>>");
            } else if (!write_file_bytes(receive_path, receive_data)) {
                write_line(serial, "<<<PUT_ERROR write_failed>>>");
            } else {
                write_line(serial, "<<<PUT_OK " + receive_path + " size=" + std::to_string(receive_data.size()) + ">>>");
            }
            receiving_file = false;
            receive_path.clear();
            receive_expected = 0;
            receive_data.clear();
            write_line(serial, "<<<CMD_END rc=0>>>");
            continue;
        }

        DWORD rc = run_command(serial, line);
        write_line(serial, "<<<CMD_END rc=" + std::to_string(rc) + ">>>");
    }

    CloseHandle(serial);
    return 0;
}
