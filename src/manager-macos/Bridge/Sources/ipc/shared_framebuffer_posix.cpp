#include "ipc/shared_framebuffer.h"

#include <cerrno>
#include <cstring>
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>

namespace ipc {

SharedFramebuffer::~SharedFramebuffer() {
    Close();
}

bool SharedFramebuffer::Create(const std::string& name, uint32_t width, uint32_t height) {
    Close();

    size_t bytes = static_cast<size_t>(width) * height * 4;
    if (bytes == 0) return false;

    // First unlink any stale segment with the same name (ignore errors).
    shm_unlink(name.c_str());

    int fd = shm_open(name.c_str(), O_CREAT | O_EXCL | O_RDWR, 0600);
    if (fd < 0) return false;

    if (ftruncate(fd, static_cast<off_t>(bytes)) < 0) {
        close(fd);
        shm_unlink(name.c_str());
        return false;
    }

    void* ptr = mmap(nullptr, bytes, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (ptr == MAP_FAILED) {
        close(fd);
        shm_unlink(name.c_str());
        return false;
    }

    data_ = static_cast<uint8_t*>(ptr);
    size_ = bytes;
    width_ = width;
    height_ = height;
    name_ = name;
    shm_fd_ = fd;
    is_owner_ = true;
    return true;
}

bool SharedFramebuffer::Open(const std::string& name, uint32_t width, uint32_t height) {
    Close();

    size_t bytes = static_cast<size_t>(width) * height * 4;
    if (bytes == 0) return false;

    int fd = shm_open(name.c_str(), O_RDONLY, 0);
    if (fd < 0) return false;

    void* ptr = mmap(nullptr, bytes, PROT_READ, MAP_SHARED, fd, 0);
    if (ptr == MAP_FAILED) {
        close(fd);
        return false;
    }

    data_ = static_cast<uint8_t*>(ptr);
    size_ = bytes;
    width_ = width;
    height_ = height;
    name_ = name;
    shm_fd_ = fd;
    is_owner_ = false;
    return true;
}

void SharedFramebuffer::Close() {
    if (data_) {
        munmap(data_, size_);
        data_ = nullptr;
    }
    if (shm_fd_ >= 0) {
        close(shm_fd_);
        shm_fd_ = -1;
    }
    if (is_owner_ && !name_.empty()) {
        shm_unlink(name_.c_str());
    }
    size_ = 0;
    width_ = 0;
    height_ = 0;
    name_.clear();
    is_owner_ = false;
}

std::string GetSharedFramebufferName(const std::string& vm_id) {
    // macOS shm_open has PSHMNAMLEN=31 (30 usable chars after leading '/').
    // The caller appends "_<generation>" (up to 4 chars), so the base name
    // must be at most 26 chars: "/" (1) + "tb_" (3) + 22 hex = 26.
    std::string compact;
    compact.reserve(32);
    for (char c : vm_id) {
        if (c != '-') compact += c;
    }
    return "/tb_" + compact.substr(0, 22);
}

}  // namespace ipc
