#pragma once

#include "platform/windows/hypervisor/whvp_platform.h"
#include "core/vmm/types.h"
#include "core/vmm/hypervisor_vm.h"
#include <memory>

class AddressSpace;

namespace whvp {

class WhvpDoorbellRegistrar;

class WhvpVm : public HypervisorVm {
public:
    ~WhvpVm() override;

    static std::unique_ptr<WhvpVm> Create(uint32_t cpu_count);

    WHV_PARTITION_HANDLE Handle() const { return partition_; }

    bool MapMemory(GPA gpa, void* hva, uint64_t size, bool writable) override;
    bool UnmapMemory(GPA gpa, uint64_t size) override;
    std::unique_ptr<HypervisorVCpu> CreateVCpu(
        uint32_t index, AddressSpace* addr_space) override;
    void RequestInterrupt(const InterruptRequest& req) override;

    bool RegisterQueueDoorbell(uint64_t mmio_addr, uint32_t len, uint32_t datamatch,
                               std::function<void()> cb) override;
    void UnregisterAllQueueDoorbells() override;

    WhvpVm(const WhvpVm&) = delete;
    WhvpVm& operator=(const WhvpVm&) = delete;

private:
    WhvpVm() = default;
    WHV_PARTITION_HANDLE partition_ = nullptr;
    std::unique_ptr<WhvpDoorbellRegistrar> doorbell_;
};

} // namespace whvp
