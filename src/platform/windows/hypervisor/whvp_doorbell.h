#pragma once

#include "platform/windows/hypervisor/whvp_platform.h"

#include <atomic>
#include <functional>
#include <memory>
#include <mutex>
#include <thread>
#include <vector>

namespace whvp {

// Registers WHPX partition doorbells for virtio-mmio QueueNotify (same
// semantics as Linux KVM_IOEVENTFD + datamatch). One dispatcher thread
// waits on all per-queue auto-reset events and invokes callbacks directly.
//
// Thread-safety: Register() may be called from the VM setup thread while the
// dispatcher is running. Shutdown() must be called before the partition is
// deleted (typically from Vm teardown after vCPU threads have joined).
class WhvpDoorbellRegistrar {
public:
    explicit WhvpDoorbellRegistrar(WHV_PARTITION_HANDLE partition);
    ~WhvpDoorbellRegistrar();

    WhvpDoorbellRegistrar(const WhvpDoorbellRegistrar&) = delete;
    WhvpDoorbellRegistrar& operator=(const WhvpDoorbellRegistrar&) = delete;

    bool Available() const { return available_; }

    bool Register(uint64_t mmio_addr, uint32_t len, uint32_t datamatch,
                   std::function<void()> cb);

    // Stops the dispatcher and unregisters every doorbell with the
    // hypervisor. Safe to call multiple times.
    void Shutdown();

private:
    enum class ApiKind { None, LegacyDoorbell, NotificationPort };

    struct Slot {
        uint64_t mmio_addr = 0;
        uint32_t len = 0;
        uint32_t datamatch = 0;
        HANDLE event = nullptr;
        std::function<void()> cb;
        ApiKind api = ApiKind::None;
        WHV_NOTIFICATION_PORT_HANDLE port_handle = nullptr;
        WHV_DOORBELL_MATCH_DATA legacy_match{};
    };

    void DispatcherLoop();

    WHV_PARTITION_HANDLE partition_ = nullptr;
    bool available_ = false;
    bool use_notification_port_api_ = false;

    HANDLE wakeup_event_ = nullptr;
    std::atomic<bool> stop_{false};
    std::thread dispatcher_thread_;

    std::mutex mu_;
    std::vector<std::unique_ptr<Slot>> slots_;
    std::atomic<bool> shutdown_done_{false};
};

} // namespace whvp
