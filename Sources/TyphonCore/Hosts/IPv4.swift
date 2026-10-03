#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// An IPv4 address held as a host-order integer, so subnets can be enumerated arithmetically.
public struct IPv4Address: Hashable, Comparable, Sendable, CustomStringConvertible {
  public var value: UInt32

  public init(_ value: UInt32) {
    self.value = value
  }

  /// Parses strict dotted-quad notation, e.g. `192.168.0.1`.
  public init?(_ string: String) {
    let octets = string.split(separator: ".", omittingEmptySubsequences: false)
    guard octets.count == 4 else { return nil }
    var value: UInt32 = 0
    for octet in octets {
      guard octet.allSatisfy(\.isASCIIDigit), let byte = UInt8(octet) else { return nil }
      value = value << 8 | UInt32(byte)
    }
    self.value = value
  }

  public var description: String {
    [24, 16, 8, 0].map { String(value >> $0 & 0xFF) }.joined(separator: ".")
  }

  public static func < (lhs: Self, rhs: Self) -> Bool { lhs.value < rhs.value }
}

/// Resolves a hostname to an IPv4 address. Injected so subnet expansion can be tested offline.
public protocol HostAddressResolver: Sendable {
  func ipv4Address(of hostname: String) -> IPv4Address?
}

/// Resolves names using the system resolver (`getaddrinfo`).
public struct SystemHostAddressResolver: HostAddressResolver {
  public init() {}

  public func ipv4Address(of hostname: String) -> IPv4Address? {
    if let literal = IPv4Address(hostname) { return literal }

    var hints = addrinfo()
    hints.ai_family = AF_INET
    hints.ai_socktype = Int32(SOCK_STREAM)
    var result: UnsafeMutablePointer<addrinfo>?
    guard getaddrinfo(hostname, nil, &hints, &result) == 0, let result else { return nil }
    defer { freeaddrinfo(result) }

    guard let address = result.pointee.ai_addr else { return nil }
    return address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
      IPv4Address(UInt32(bigEndian: $0.pointee.sin_addr.s_addr))
    }
  }
}
