// intrusion-battery-reporter.cpp
//
// OpenBMC companion reporter for chassis-intrusion latch Q, battery-present
// comparator, and VBAT-backed SRAM token. Pairs with upstream
// phosphor-intrusion-sensor (which handles the live chassis switch) to provide
// full threat-window coverage:
//
//   - D5 (SR-latch)     : chassis opened while system was off
//   - D6 (comparator)   : battery removed while BMC is running
//   - D12 (VBAT token)  : battery removed while system was off

#include <boost/asio.hpp>
#include <gpiod.hpp>
#include <openssl/hmac.h>
#include <openssl/rand.h>
#include <sdbusplus/asio/connection.hpp>
#include <sdbusplus/asio/object_server.hpp>

#include <chrono>
#include <cstdint>
#include <cstring>
#include <fcntl.h>
#include <filesystem>
#include <fstream>
#include <sys/file.h>
#include <unistd.h>
#include <vector>
#include <zlib.h>

namespace intrusion
{

constexpr auto kNvmemPath   = "/sys/bus/nvmem/devices/rtc-aspeed/nvmem";
constexpr auto kSealPath    = "/var/lib/intrusion-battery-reporter/seal";
constexpr auto kSealTmpPath = "/var/lib/intrusion-battery-reporter/seal.tmp";
constexpr auto kBootKeyPath = "/usr/share/intrusion-battery-reporter/k_boot";
constexpr size_t kTokenLen  = 16;
constexpr size_t kCrcLen    = 4;
constexpr size_t kNvmemLen  = kTokenLen + kCrcLen;
constexpr off_t kNvmemOff   = 0;
constexpr size_t kHmacLen   = 32;
constexpr std::chrono::seconds kRotateInterval{15 * 60};
constexpr std::chrono::milliseconds kComparatorDebounce{250};

enum class DetectorSource
{
    LiveComparator,
    VbatToken,
};

static const char* sourceString(DetectorSource s)
{
    return s == DetectorSource::LiveComparator ? "live-comparator"
                                               : "vbat-token";
}

// ---------- Low-level I/O ----------

static std::vector<uint8_t> readBootKey()
{
    std::ifstream in(kBootKeyPath, std::ios::binary);
    if (!in)
    {
        throw std::runtime_error("cannot open K_boot");
    }
    return {std::istreambuf_iterator<char>(in), {}};
}

static bool readNvmem(std::array<uint8_t, kNvmemLen>& out)
{
    int fd = ::open(kNvmemPath, O_RDONLY);
    if (fd < 0)
        return false;
    ssize_t n = ::pread(fd, out.data(), out.size(), kNvmemOff);
    ::close(fd);
    return n == static_cast<ssize_t>(out.size());
}

static bool writeNvmem(const std::array<uint8_t, kNvmemLen>& buf)
{
    int fd = ::open(kNvmemPath, O_RDWR);
    if (fd < 0)
        return false;
    ssize_t n = ::pwrite(fd, buf.data(), buf.size(), kNvmemOff);
    ::close(fd);
    return n == static_cast<ssize_t>(buf.size());
}

static bool readSeal(std::array<uint8_t, kHmacLen>& out)
{
    std::ifstream in(kSealPath, std::ios::binary);
    if (!in)
        return false;
    in.read(reinterpret_cast<char*>(out.data()), out.size());
    return in.gcount() == static_cast<std::streamsize>(out.size());
}

static bool writeSealAtomic(const std::array<uint8_t, kHmacLen>& seal)
{
    {
        std::ofstream tmp(kSealTmpPath, std::ios::binary | std::ios::trunc);
        tmp.write(reinterpret_cast<const char*>(seal.data()), seal.size());
        tmp.flush();
    }
    std::error_code ec;
    std::filesystem::rename(kSealTmpPath, kSealPath, ec);
    return !ec;
}

// ---------- Crypto helpers ----------

static uint32_t crc32Of(const uint8_t* data, size_t len)
{
    return ::crc32(0L, data, static_cast<uInt>(len));
}

static std::array<uint8_t, kHmacLen> hmacToken(
    const std::vector<uint8_t>& key, const uint8_t* token, size_t len)
{
    std::array<uint8_t, kHmacLen> out{};
    unsigned int olen = 0;
    HMAC(EVP_sha256(), key.data(), static_cast<int>(key.size()), token, len,
         out.data(), &olen);
    return out;
}

static bool isWipedPattern(const uint8_t* p, size_t len)
{
    bool allZero = true, allOnes = true;
    for (size_t i = 0; i < len; ++i)
    {
        if (p[i] != 0x00)
            allZero = false;
        if (p[i] != 0xFF)
            allOnes = false;
    }
    return allZero || allOnes;
}

// ---------- Verify-and-rotate protocol ----------

struct RotateResult
{
    bool wiped;
    DetectorSource source;
};

RotateResult verifyAndRotate(const std::vector<uint8_t>& kBoot)
{
    std::array<uint8_t, kNvmemLen> buf{};
    bool haveVbat = readNvmem(buf);

    bool declareRemoved = false;
    if (!haveVbat || isWipedPattern(buf.data(), kNvmemLen))
    {
        declareRemoved = true;
    }
    else
    {
        uint32_t gotCrc = 0;
        std::memcpy(&gotCrc, buf.data() + kTokenLen, kCrcLen);
        uint32_t wantCrc = crc32Of(buf.data(), kTokenLen);
        if (gotCrc != wantCrc)
        {
            declareRemoved = true;
        }
        else
        {
            std::array<uint8_t, kHmacLen> seal{};
            if (!readSeal(seal))
            {
                declareRemoved = true;
            }
            else
            {
                auto computed = hmacToken(kBoot, buf.data(), kTokenLen);
                if (computed != seal)
                {
                    declareRemoved = true;
                }
            }
        }
    }

    // Rotate: fresh random token + updated seal, regardless of outcome.
    std::array<uint8_t, kNvmemLen> fresh{};
    if (RAND_bytes(fresh.data(), kTokenLen) != 1)
    {
        throw std::runtime_error("RAND_bytes failed");
    }
    uint32_t crc = crc32Of(fresh.data(), kTokenLen);
    std::memcpy(fresh.data() + kTokenLen, &crc, kCrcLen);
    writeNvmem(fresh);
    writeSealAtomic(hmacToken(kBoot, fresh.data(), kTokenLen));

    return {declareRemoved, DetectorSource::VbatToken};
}

// ---------- D-Bus surface ----------

class IntrusionInterface
{
  public:
    IntrusionInterface(sdbusplus::asio::object_server& objs,
                       const std::string& path) :
        iface_(objs.add_interface(path, "xyz.openbmc_project.Chassis.Intrusion"))
    {
        iface_->register_property("Status", std::string{"Normal"});
        iface_->initialize();
    }

    void set(const std::string& v)
    {
        iface_->set_property("Status", v);
    }

  private:
    std::shared_ptr<sdbusplus::asio::dbus_interface> iface_;
};

// ---------- Latch read-and-clear ----------

void readAndClearLatch(gpiod::line& q, gpiod::line& r,
                       IntrusionInterface& latchIface)
{
    q.request({"reporter", gpiod::line_request::DIRECTION_INPUT, 0});
    r.request({"reporter", gpiod::line_request::DIRECTION_OUTPUT, 0});

    bool asserted = q.get_value() == 1;
    if (asserted)
    {
        latchIface.set("TamperingDetected");
    }

    // Reset pulse — hold >= 1 µs (usleep granularity is plenty)
    r.set_value(1);
    ::usleep(10);
    // Re-read Q before dropping R to catch intrusions during the pulse
    bool stillSet = q.get_value() == 1;
    r.set_value(0);

    if (stillSet)
    {
        latchIface.set("HardwareIntrusion");
    }
}

// ---------- Live comparator subscription ----------

void subscribeLiveComparator(boost::asio::io_context& io, gpiod::line& present,
                             IntrusionInterface& battIface)
{
    present.request(
        {"reporter",
         gpiod::line_request::EVENT_BOTH_EDGES,
         0});

    // Simple polling loop with debounce; a production version would use
    // boost::asio::posix::stream_descriptor on present.event_get_fd().
    auto timer = std::make_shared<boost::asio::steady_timer>(io);
    auto lastState = std::make_shared<int>(present.get_value());

    std::function<void(const boost::system::error_code&)> tick =
        [&present, &battIface, timer, lastState, &tick,
         &io](const boost::system::error_code& ec) {
            if (ec)
                return;
            int now = present.get_value();
            if (now != *lastState)
            {
                battIface.set(now ? "Normal" : "HardwareIntrusion");
                // Emit Redfish LogEntry / OEM SEL via phosphor-logging,
                // including DetectorSource = live-comparator.
                *lastState = now;
            }
            timer->expires_after(kComparatorDebounce);
            timer->async_wait(tick);
        };

    timer->expires_after(kComparatorDebounce);
    timer->async_wait(tick);
}

}  // namespace intrusion

// ---------- main ----------

int main(int argc, char** argv)
{
    auto io  = std::make_shared<boost::asio::io_context>();
    auto bus = std::make_shared<sdbusplus::asio::connection>(*io);
    bus->request_name("xyz.openbmc_project.IntrusionBatteryReporter");
    auto objs = sdbusplus::asio::object_server(bus);

    intrusion::IntrusionInterface latchIface(
        objs, "/xyz/openbmc_project/Intrusion/Chassis_Latch");
    intrusion::IntrusionInterface battIface(
        objs, "/xyz/openbmc_project/Intrusion/Battery_Present");

    gpiod::chip chip("gpiochip0");
    auto latchQ  = chip.find_line("intrusion-latch-q");
    auto latchR  = chip.find_line("intrusion-latch-r");
    auto present = chip.find_line("battery-present");

    intrusion::readAndClearLatch(latchQ, latchR, latchIface);

    auto kBoot = intrusion::readBootKey();
    auto rot   = intrusion::verifyAndRotate(kBoot);
    if (rot.wiped)
    {
        battIface.set("HardwareIntrusion");
        // Emit Redfish LogEntry / OEM SEL with DetectorSource = vbat-token.
    }

    if (argc > 1 && std::string(argv[1]) == "--rotate-on-shutdown")
    {
        // Stop path: rotate token one more time so the VBAT SRAM contains a
        // freshly-sealed value as the battery takes over. Do not run the event
        // loop.
        intrusion::verifyAndRotate(kBoot);
        return 0;
    }

    intrusion::subscribeLiveComparator(*io, present, battIface);

    // Periodic rotation every 15 min.
    auto periodic = std::make_shared<boost::asio::steady_timer>(*io);
    std::function<void(const boost::system::error_code&)> rotateLoop =
        [&kBoot, periodic, &rotateLoop](const boost::system::error_code& ec) {
            if (ec)
                return;
            intrusion::verifyAndRotate(kBoot);
            periodic->expires_after(intrusion::kRotateInterval);
            periodic->async_wait(rotateLoop);
        };
    periodic->expires_after(intrusion::kRotateInterval);
    periodic->async_wait(rotateLoop);

    io->run();
    return 0;
}
