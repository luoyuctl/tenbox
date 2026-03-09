#include "ipc/shared_framebuffer.h"

#include <windows.h>

namespace ipc {

SharedFramebuffer::~SharedFramebuffer() {
    Close();
}

bool SharedFramebuffer::Create(const std::string& name, uint32_t width, uint32_t height) {
    Close();

    size_t bytes = static_cast<size_t>(width) * height * 4;
    if (bytes == 0) return false;

    HANDLE h = CreateFileMappingA(
        INVALID_HANDLE_VALUE, nullptr, PAGE_READWRITE,
        static_cast<DWORD>(bytes >> 32), static_cast<DWORD>(bytes & 0xFFFFFFFF),
        name.c_str());
    if (!h) return false;

    void* ptr = MapViewOfFile(h, FILE_MAP_ALL_ACCESS, 0, 0, bytes);
    if (!ptr) {
        CloseHandle(h);
        return false;
    }

    data_ = static_cast<uint8_t*>(ptr);
    size_ = bytes;
    width_ = width;
    height_ = height;
    name_ = name;
    map_handle_ = h;
    is_owner_ = true;
    return true;
}

bool SharedFramebuffer::Open(const std::string& name, uint32_t width, uint32_t height) {
    Close();

    size_t bytes = static_cast<size_t>(width) * height * 4;
    if (bytes == 0) return false;

    HANDLE h = OpenFileMappingA(FILE_MAP_READ, FALSE, name.c_str());
    if (!h) return false;

    void* ptr = MapViewOfFile(h, FILE_MAP_READ, 0, 0, bytes);
    if (!ptr) {
        CloseHandle(h);
        return false;
    }

    data_ = static_cast<uint8_t*>(ptr);
    size_ = bytes;
    width_ = width;
    height_ = height;
    name_ = name;
    map_handle_ = h;
    is_owner_ = false;
    return true;
}

void SharedFramebuffer::Close() {
    if (data_) {
        UnmapViewOfFile(data_);
        data_ = nullptr;
    }
    if (map_handle_) {
        CloseHandle(map_handle_);
        map_handle_ = nullptr;
    }
    size_ = 0;
    width_ = 0;
    height_ = 0;
    name_.clear();
    is_owner_ = false;
}

std::string GetSharedFramebufferName(const std::string& vm_id) {
    // Keep consistent with POSIX naming (strip hyphens, truncate).
    // Caller appends "_<generation>" so leave room for that suffix.
    std::string compact;
    compact.reserve(32);
    for (char c : vm_id) {
        if (c != '-') compact += c;
    }
    return "tb_" + compact.substr(0, 22);
}

}  // namespace ipc
