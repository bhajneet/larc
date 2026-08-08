import Foundation
import dnssd

/// Continuously browses `_linkplay._tcp` over mDNS and reports devices with a
/// resolved IPv4 address. WiiM devices advertise this service with the friendly
/// name as the instance name and a stable `uuid` in the TXT record (verified
/// against a real WiiM Amp and WiiM Ultra).
final class LinkplayDiscoverer {
    static let shared = LinkplayDiscoverer()
    static let serviceType = "_linkplay._tcp"

    private let queue = DispatchQueue(label: "com.studioaiyo.larc.discovery")
    private var browseRef: DNSServiceRef?
    private var tokens: [ResolveToken] = []
    private var devices: [String: AudioDevice] = [:]
    private var onUpdate: (([AudioDevice]) -> Void)?

    /// Per-instance resolution state, passed through the C callbacks as an
    /// unretained context pointer; retained by `tokens` until finished.
    final class ResolveToken {
        unowned let owner: LinkplayDiscoverer
        let key: String
        let instanceName: String
        var uuid: String?
        var refs: [DNSServiceRef] = []

        init(owner: LinkplayDiscoverer, key: String, instanceName: String) {
            self.owner = owner
            self.key = key
            self.instanceName = instanceName
        }
    }

    func start(onUpdate: @escaping ([AudioDevice]) -> Void) {
        queue.async {
            self.onUpdate = onUpdate
            self.startBrowseLocked()
        }
    }

    func restart() {
        queue.async {
            self.stopLocked()
            self.devices = [:]
            self.pushUpdateLocked()
            self.startBrowseLocked()
        }
    }

    // MARK: - Queue-confined internals

    private func startBrowseLocked() {
        guard browseRef == nil else { return }
        var ref: DNSServiceRef?
        let context = Unmanaged.passUnretained(self).toOpaque()
        let err = DNSServiceBrowse(&ref, 0, 0, Self.serviceType, nil, browseReply, context)
        guard err == kDNSServiceErr_NoError, let ref else { return }
        DNSServiceSetDispatchQueue(ref, queue)
        browseRef = ref
    }

    private func stopLocked() {
        if let ref = browseRef {
            DNSServiceRefDeallocate(ref)
            browseRef = nil
        }
        for token in tokens {
            token.refs.forEach { DNSServiceRefDeallocate($0) }
            token.refs = []
        }
        tokens = []
    }

    fileprivate func instanceAppeared(name: String, regtype: String, domain: String) {
        let key = name + "|" + regtype + "|" + domain
        guard !tokens.contains(where: { $0.key == key }) else { return }
        let token = ResolveToken(owner: self, key: key, instanceName: name)
        var ref: DNSServiceRef?
        let context = Unmanaged.passUnretained(token).toOpaque()
        let err = DNSServiceResolve(&ref, 0, 0, name, regtype, domain, resolveReply, context)
        guard err == kDNSServiceErr_NoError, let ref else { return }
        DNSServiceSetDispatchQueue(ref, queue)
        token.refs.append(ref)
        tokens.append(token)
        scheduleTokenTimeout(token)
    }

    fileprivate func instanceDisappeared(name: String, regtype: String, domain: String) {
        let key = name + "|" + regtype + "|" + domain
        finishToken(key: key)
        if devices.removeValue(forKey: key) != nil {
            pushUpdateLocked()
        }
    }

    fileprivate func resolved(token: ResolveToken, hostTarget: String, txt: [String: String]) {
        token.uuid = txt["uuid"]
        var ref: DNSServiceRef?
        let context = Unmanaged.passUnretained(token).toOpaque()
        let err = DNSServiceGetAddrInfo(
            &ref, 0, 0,
            DNSServiceProtocol(kDNSServiceProtocol_IPv4),
            hostTarget, addrReply, context
        )
        guard err == kDNSServiceErr_NoError, let ref else {
            finishToken(key: token.key)
            return
        }
        DNSServiceSetDispatchQueue(ref, queue)
        token.refs.append(ref)
    }

    fileprivate func addressResolved(token: ResolveToken, ip: String) {
        devices[token.key] = AudioDevice(
            id: token.uuid ?? token.key,
            name: token.instanceName,
            host: ip,
            source: .discovered
        )
        finishToken(key: token.key)
        pushUpdateLocked()
    }

    /// Deallocates a token's service refs. Deferred to the next queue cycle:
    /// deallocating a ref from inside its own callback is not allowed.
    private func finishToken(key: String) {
        guard let index = tokens.firstIndex(where: { $0.key == key }) else { return }
        let token = tokens.remove(at: index)
        let refs = token.refs
        token.refs = []
        queue.async { refs.forEach { DNSServiceRefDeallocate($0) } }
    }

    private func scheduleTokenTimeout(_ token: ResolveToken) {
        let key = token.key
        queue.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.finishToken(key: key)
        }
    }

    private func pushUpdateLocked() {
        let list = Array(devices.values).sorted { $0.name < $1.name }
        let handler = onUpdate
        DispatchQueue.main.async { handler?(list) }
    }
}

// MARK: - C callbacks

private let browseReply: DNSServiceBrowseReply = { _, flags, _, err, name, regtype, domain, context in
    guard err == kDNSServiceErr_NoError, let context,
          let name, let regtype, let domain else { return }
    let owner = Unmanaged<LinkplayDiscoverer>.fromOpaque(context).takeUnretainedValue()
    let n = String(cString: name)
    let t = String(cString: regtype)
    let d = String(cString: domain)
    if flags & DNSServiceFlags(kDNSServiceFlagsAdd) != 0 {
        owner.instanceAppeared(name: n, regtype: t, domain: d)
    } else {
        owner.instanceDisappeared(name: n, regtype: t, domain: d)
    }
}

private let resolveReply: DNSServiceResolveReply = { _, _, _, err, _, hostTarget, _, txtLen, txtRecord, context in
    guard err == kDNSServiceErr_NoError, let context, let hostTarget else { return }
    let token = Unmanaged<LinkplayDiscoverer.ResolveToken>.fromOpaque(context).takeUnretainedValue()
    var txt: [String: String] = [:]
    if let txtRecord, txtLen > 0 {
        let bytes = UnsafeBufferPointer(start: txtRecord, count: Int(txtLen))
        var i = 0
        while i < bytes.count {
            let length = Int(bytes[i])
            i += 1
            guard length > 0, i + length <= bytes.count else { break }
            let entry = String(decoding: bytes[i ..< i + length], as: UTF8.self)
            i += length
            if let eq = entry.firstIndex(of: "=") {
                txt[String(entry[..<eq])] = String(entry[entry.index(after: eq)...])
            } else {
                txt[entry] = ""
            }
        }
    }
    token.owner.resolved(token: token, hostTarget: String(cString: hostTarget), txt: txt)
}

private let addrReply: DNSServiceGetAddrInfoReply = { _, flags, _, err, _, address, _, context in
    guard err == kDNSServiceErr_NoError, let context,
          flags & DNSServiceFlags(kDNSServiceFlagsAdd) != 0,
          let address, address.pointee.sa_family == sa_family_t(AF_INET) else { return }
    let token = Unmanaged<LinkplayDiscoverer.ResolveToken>.fromOpaque(context).takeUnretainedValue()
    var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
    guard getnameinfo(address, socklen_t(address.pointee.sa_len),
                      &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 else { return }
    token.owner.addressResolved(token: token, ip: String(cString: buffer))
}
