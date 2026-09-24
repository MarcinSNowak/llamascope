import Foundation
import Network

/// Jedno połączenie od klienta, opakowane tak, żeby dało się z niego czytać
/// i pisać `await`-em zamiast garścią domknięć.
actor ClientConnection {
    private let connection: NWConnection
    private var buffer = Data()
    private var closed = false

    init(_ connection: NWConnection) {
        self.connection = connection
        connection.start(queue: .global(qos: .userInitiated))
    }

    func close() {
        guard !closed else { return }
        closed = true
        connection.cancel()
    }

    /// Czyta do pustej linii — czyli do końca nagłówków. Zwraca `nil`, gdy
    /// klient rozłączył się, nie zaczynając kolejnego żądania; to jest
    /// normalne zakończenie połączenia z podtrzymaniem, a nie awaria.
    func readHead() async throws -> (head: HTTPRequestHeadBox, rest: Data)? {
        while true {
            if let range = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let headData = buffer[buffer.startIndex..<range.lowerBound]
                let rest = buffer[range.upperBound...]
                buffer = Data()
                let text = String(decoding: headData, as: UTF8.self)
                return (HTTPRequestHeadBox(text: text), Data(rest))
            }
            // Koniec strumienia. Resztka bez pustej linii to żądanie urwane
            // w pół — też kończymy, bo zgadywanie cudzego ruchu nie należy
            // do zadań pośrednika.
            guard let chunk = try await receive(), !chunk.isEmpty else { return nil }
            buffer.append(chunk)
        }
    }

    /// Dobiera ciało żądania do zadanej długości.
    func readBody(length: Int, alreadyRead: Data) async throws -> Data {
        var body = alreadyRead
        while body.count < length {
            guard let chunk = try await receive(), !chunk.isEmpty else { break }
            body.append(chunk)
        }
        // Nadmiar należy do następnego żądania w tym samym połączeniu.
        if body.count > length {
            buffer = Data(body[body.index(body.startIndex, offsetBy: length)...]) + buffer
            body = Data(body.prefix(length))
        }
        return body
    }

    func send(_ data: Data) async throws {
        guard !closed else { throw ProxyError.clientGone }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private func receive() async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
                data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: Data())
                }
            }
        }
    }
}

/// Opakowanie na surowy tekst nagłówka — rozbiór robi rdzeń, bo tam ma testy.
struct HTTPRequestHeadBox: Sendable {
    let text: String
}

enum ProxyError: Error {
    case clientGone
    case upstreamUnreachable(String)
}
