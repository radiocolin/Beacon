//
//  BeaconHTTPServer.swift
//  Beacon
//
//  Lightweight HTTP API server for external control of the Busylight.
//  Uses the Network framework (NWListener) on TCP port 29100.
//

import Foundation
import Network

final class BeaconHTTPServer {

    private var listener: NWListener?
    private let port: UInt16 = 29100
    private let queue = DispatchQueue(label: "com.beacon.httpserver", qos: .userInitiated)

    private(set) var isRunning = false

    // MARK: - Start / Stop

    func start() {
        guard !isRunning else { return }
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        } catch {
            NSLog("Beacon HTTP: failed to create listener: \(error)")
            return
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                NSLog("Beacon HTTP: listening on port %d", self.port)
            case .failed(let error):
                NSLog("Beacon HTTP: listener failed: \(error)")
            default:
                break
            }
        }

        listener?.start(queue: queue)
        isRunning = true
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        NSLog("Beacon HTTP: stopped")
    }

    // MARK: - Connection handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        // Read up to 8KB for the HTTP request
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, error in
            if let data = data, !data.isEmpty {
                self?.processRequest(data: data, connection: connection)
            } else {
                connection.cancel()
            }
        }
    }

    // MARK: - HTTP parsing

    private func processRequest(data: Data, connection: NWConnection) {
        guard let raw = String(data: data, encoding: .utf8) else {
            sendResponse(connection: connection, status: 400, body: ["error": "Invalid request"])
            return
        }

        // Split headers from body
        let parts = raw.components(separatedBy: "\r\n\r\n")
        let headerSection = parts[0]
        let bodyString = parts.count > 1 ? parts[1] : ""

        // Parse request line
        let lines = headerSection.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendResponse(connection: connection, status: 400, body: ["error": "No request line"])
            return
        }

        let tokens = requestLine.split(separator: " ")
        guard tokens.count >= 2 else {
            sendResponse(connection: connection, status: 400, body: ["error": "Malformed request line"])
            return
        }

        let method = String(tokens[0]).uppercased()
        let path = String(tokens[1])

        // Parse JSON body if present
        var json: [String: Any] = [:]
        if !bodyString.isEmpty, let bodyData = bodyString.data(using: .utf8) {
            json = (try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any]) ?? [:]
        }

        // Route
        route(method: method, path: path, json: json, connection: connection)
    }

    // MARK: - Routing

    private func route(method: String, path: String, json: [String: Any], connection: NWConnection) {
        // Dispatch to main thread for BusylightController access
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let ctrl = BusylightController.shared

            switch (method, path) {

            case ("GET", "/status"):
                let status: [String: Any] = [
                    "connected": ctrl.isConnected,
                    "red": ctrl.red,
                    "green": ctrl.green,
                    "blue": ctrl.blue,
                    "effect": ctrl.effect.rawValue,
                    "volume": ctrl.volumeLevel,
                ]
                self.sendResponse(connection: connection, status: 200, body: status)

            case ("POST", "/on"):
                ctrl.turnOn()
                self.sendOK(connection: connection)

            case ("POST", "/off"):
                ctrl.turnOff()
                self.sendOK(connection: connection)

            case ("POST", "/color"):
                let r = UInt8(clamping: json["red"] as? Int ?? 0)
                let g = UInt8(clamping: json["green"] as? Int ?? 0)
                let b = UInt8(clamping: json["blue"] as? Int ?? 0)
                ctrl.setColor(red: r, green: g, blue: b)
                self.sendOK(connection: connection)

            case ("POST", "/effect"):
                let name = json["effect"] as? String ?? "solid"
                let bpm = json["bpm"] as? Int ?? 120
                switch name.lowercased() {
                case "blink":
                    let step = Self.bpmToStep(bpm)
                    ctrl.setBlink(on: step, off: step)
                case "pulse":
                    let step = Self.bpmToStep(bpm)
                    ctrl.setPulse(stepTime: step)
                default:
                    ctrl.setEffect(.solid)
                }
                self.sendOK(connection: connection)

            case ("POST", "/sound/start"):
                if let tone = self.parseTone(json) {
                    ctrl.startSound(tone)
                    self.sendOK(connection: connection)
                } else {
                    self.sendResponse(connection: connection, status: 400, body: ["error": "Unknown tone. Use one of: \(BusylightTone.allCases.map(\.rawValue).joined(separator: ", "))"])
                }

            case ("POST", "/sound/play"):
                if let tone = self.parseTone(json) {
                    let seconds = json["seconds"] as? Int ?? 5
                    ctrl.playSound(tone, duration: TimeInterval(seconds))
                    self.sendOK(connection: connection)
                } else {
                    self.sendResponse(connection: connection, status: 400, body: ["error": "Unknown tone. Use one of: \(BusylightTone.allCases.map(\.rawValue).joined(separator: ", "))"])
                }

            case ("POST", "/sound/stop"):
                ctrl.stopSound()
                self.sendOK(connection: connection)

            case ("POST", "/volume"):
                let level = UInt8(clamping: json["level"] as? Int ?? 4)
                ctrl.setVolume(level)
                self.sendOK(connection: connection)

            default:
                self.sendResponse(connection: connection, status: 404, body: ["error": "Not found"])
            }
        }
    }

    // MARK: - Helpers

    private func parseTone(_ json: [String: Any]) -> BusylightTone? {
        guard let name = json["tone"] as? String else { return nil }
        return BusylightTone.allCases.first { $0.rawValue.caseInsensitiveCompare(name) == .orderedSame }
    }

    private static func bpmToStep(_ bpm: Int) -> UInt8 {
        guard bpm > 0 else { return 255 }
        return UInt8(clamping: Int((300.0 / Double(bpm)).rounded()))
    }

    // MARK: - Response

    private func sendOK(connection: NWConnection) {
        sendResponse(connection: connection, status: 200, body: ["ok": true])
    }

    private func sendResponse(connection: NWConnection, status: Int, body: [String: Any]) {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        default: statusText = "Error"
        }

        let jsonData = (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? Data()
        var response = "HTTP/1.1 \(status) \(statusText)\r\n"
        response += "Content-Type: application/json\r\n"
        response += "Content-Length: \(jsonData.count)\r\n"
        response += "Connection: close\r\n"
        response += "Access-Control-Allow-Origin: *\r\n"
        response += "\r\n"

        var responseData = Data(response.utf8)
        responseData.append(jsonData)

        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
