#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <cstdlib>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>

namespace {

bool write_file(const std::wstring& path, const char* data, DWORD size) {
    HANDLE file = CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS,
                              FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) return false;
    DWORD written = 0;
    const bool ok = WriteFile(file, data, size, &written, nullptr) && written == size;
    CloseHandle(file);
    return ok;
}

bool run_probe(const char* image_path) {
    const char* font_dir = std::getenv("GCN_FONT_DIR");
    if (!font_dir) return false;
    std::ifstream image(image_path, std::ios::binary);
    const std::string font_path = std::string(font_dir) + "\\font.bin";
    std::ifstream font(font_path, std::ios::binary);
    HANDLE file = CreateFileA(image_path, GENERIC_READ, FILE_SHARE_READ, nullptr,
                              OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file != INVALID_HANDLE_VALUE) CloseHandle(file);
    return image.good() && font.good() && file != INVALID_HANDLE_VALUE;
}

}  // namespace

int main(int argc, char** argv) {
    if (argc == 3 && std::string(argv[1]) == "--probe") {
        return run_probe(argv[2]) ? 0 : 1;
    }

    wchar_t temp[MAX_PATH]{};
    const DWORD temp_size = GetTempPathW(MAX_PATH, temp);
    if (!temp_size || temp_size >= MAX_PATH) return 2;
    const std::wstring root = std::wstring(temp) + L"gcn-utf8-path-" + std::to_wstring(GetCurrentProcessId()) + L"-Ω";
    const std::wstring image_path = root + L"\\assault.iso";
    const std::wstring font_dir = root + L"\\fonts Ω";
    const std::wstring font_path = font_dir + L"\\font.bin";
    if (!CreateDirectoryW(root.c_str(), nullptr) || !CreateDirectoryW(font_dir.c_str(), nullptr)) {
        std::wcerr << L"could not create Unicode test folders\n";
        return 2;
    }
    const char image_byte = 'I';
    const char font_byte = 'F';
    bool ok = write_file(image_path, &image_byte, 1) && write_file(font_path, &font_byte, 1) &&
              SetEnvironmentVariableW(L"GCN_FONT_DIR", font_dir.c_str());
    if (!ok) {
        std::wcerr << L"could not create Unicode test files\n";
        return 2;
    }

    wchar_t executable[MAX_PATH]{};
    const DWORD exe_size = GetModuleFileNameW(nullptr, executable, MAX_PATH);
    if (!exe_size || exe_size >= MAX_PATH) return 2;
    std::wstring command = L"\"" + std::wstring(executable) + L"\" --probe \"" + image_path + L"\"";
    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    PROCESS_INFORMATION process{};
    if (!CreateProcessW(nullptr, command.data(), nullptr, nullptr, FALSE, 0, nullptr, nullptr,
                        &startup, &process)) {
        std::wcerr << L"could not launch UTF-8 path probe\n";
        return 2;
    }
    WaitForSingleObject(process.hProcess, INFINITE);
    DWORD exit_code = 1;
    GetExitCodeProcess(process.hProcess, &exit_code);
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);

    SetEnvironmentVariableW(L"GCN_FONT_DIR", nullptr);
    DeleteFileW(font_path.c_str());
    DeleteFileW(image_path.c_str());
    RemoveDirectoryW(font_dir.c_str());
    RemoveDirectoryW(root.c_str());
    if (exit_code != 0) {
        std::cerr << "UTF-8 argv, environment, CRT file I/O, or Win32 A file I/O failed\n";
        return 1;
    }
    std::cout << "UTF-8 argv, environment, CRT file I/O, and Win32 A file I/O passed\n";
    return 0;
}
