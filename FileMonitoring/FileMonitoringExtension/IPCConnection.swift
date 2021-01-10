//
//  IPCConnection.swift
//  FileMonitoringSystem
//
//  Created by Iraniya Naynesh on 08/01/21.
//

import Foundation
import EndpointSecurity

@objc protocol ProviderCommunication {
    func register(_ completionHandler: @escaping (Bool) -> Void)
}

@objc protocol AppCommunication {
    func sendEventToApp(newEvent event: String)
}

class IPCConnection: NSObject {
    var listener: NSXPCListener?
    var currentConnection: NSXPCConnection?
    weak var delegate: AppCommunication?
    static let shared = IPCConnection()
    
    var client: ESClient?

    func startListener(esclient: ESClient) {
        let machServiceName = extensionMachServiceName(from: Bundle.main)
        NSLog("Starting XPC listener for mach service.")

        let newListener = NSXPCListener(machServiceName: machServiceName)
        newListener.delegate = self
        newListener.resume()
        listener = newListener
        client = esclient
    }

    
    private func extensionMachServiceName(from bundle: Bundle) -> String {
        guard let networkExtensionKeys = bundle.object(forInfoDictionaryKey: "EndpointExtension") as? [String: Any],
            let machServiceName = networkExtensionKeys["MachServiceName"] as? String else {
            NSLog("Mach service name is missing from the Info.plist")
            return ""
        }
        return machServiceName
    }

    func register(withExtension bundle: Bundle,
                  delegate: AppCommunication,
                  completionHandler: @escaping (Bool) -> Void) {
        self.delegate = delegate
        guard currentConnection == nil else {
            NSLog("Already registered with the provider")
            completionHandler(true)
            return
        }

        let machServiceName = extensionMachServiceName(from: bundle)
        NSLog("Trying to connect to service: %@", machServiceName)

        let newConnection = NSXPCConnection(machServiceName: machServiceName, options: [])
        newConnection.exportedInterface = NSXPCInterface(with: AppCommunication.self)
        newConnection.exportedObject = delegate
        newConnection.remoteObjectInterface = NSXPCInterface(with: ProviderCommunication.self)
        currentConnection = newConnection
        newConnection.resume()

        guard let providerProxy = newConnection.remoteObjectProxyWithErrorHandler({ registerError in
            NSLog("Failed to register with the provider: %@", registerError.localizedDescription)
            self.currentConnection?.invalidate()
            self.currentConnection = nil
            completionHandler(false)
        }) as? ProviderCommunication else {
            NSLog("Failed to create a remote object proxy for the provider")
            return
        }

        providerProxy.register(completionHandler)
    }


    func terminateESClient() {
        if client != nil {
            let ret = disableFileMonitoring(esclient: client!)
            if ret != FileMonitorError.success {
                NSLog("Failed to disable File Monitoring listener")
            }
        }
        client = nil
    }

    func sendEventToApp(newEvent event: String) {
        guard let connection = currentConnection else {
            // no app client connected, do not attempt to send event.
            return
        }

        guard let appProxy = connection.remoteObjectProxyWithErrorHandler({ sendError in
            NSLog("Failed to sent event to app %@", sendError.localizedDescription)
            self.currentConnection = nil
        }) as? AppCommunication else {
            NSLog("Failed to create a remote object proxy for the app")
            return
        }

        appProxy.sendEventToApp(newEvent: event)
    }
}

extension IPCConnection: NSXPCListenerDelegate {
    func listener(_: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: ProviderCommunication.self)
        newConnection.exportedObject = self
        newConnection.remoteObjectInterface = NSXPCInterface(with: AppCommunication.self)
        newConnection.invalidationHandler = {
            self.currentConnection = nil
            NSLog("App disconnected.")
            self.terminateESClient()
        }

        newConnection.interruptionHandler = {
            self.currentConnection = nil
            NSLog("App connection interrupt.")
        }

        currentConnection = newConnection
        newConnection.resume()
        return true
    }
}

func sender(event: FileMonitoringEvent) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    guard let data = try? encoder.encode(event)
    else {
        NSLog("Failed to seralize event")
        return
    }
    guard let json = String(data: data, encoding: .utf8) else {
        NSLog("Invalid json encode.")
        return
    }

    IPCConnection.shared.sendEventToApp(newEvent: json)
}

func startFileMonitoringClient() -> ESClient {
    let esclient = enableFileMonitoring(completion: sender)
    if esclient.error != FileMonitorError.success {
        NSLog("Failed to create FileMonitoring listener.")
    }

    return esclient.client
}

extension IPCConnection: ProviderCommunication {
   
    func register(_ completionHandler: @escaping (Bool) -> Void) {
        NSLog("App client connected.")

        if client == nil {
            client = startFileMonitoringClient()
            NSLog("File Monitoring esclient.")
        }
        completionHandler(true)
    }
}


//TODO: -  Insteed of adding all the File Monitoring class below need to create framework and link that framework to main app and extension


public enum ESClientError: Error {
    case success
    case missingEntitlements
    case alreadyEnabled
    case newClientError
    case failedSubscription
}


public struct FileMonitoringEvent: Codable {
    public var eventtype: String
    public var processpath: String
    public var pid: Int32
    public var ppid: Int32
    public var isplatform: Bool
    public var timestamp: Int
    public var username: String
    public var signingid: String
    public var props: [String: String]
    
    public var description: String {
        let pretty = """
        Event Type: \(eventtype)
        Process: \(processpath)
        Pid: \(pid) (Parent) -> \(ppid)
        User: \(username)
        Timestamp: \(timestamp)
        Platform Binary: \(isplatform)
        Signing ID: \(signingid)
        Props:
        \(props as AnyObject)
        """
        return pretty
    }
    
    init() {
        eventtype = ""
        processpath = ""
        pid = -1
        ppid = -1
        timestamp = 0
        isplatform = false
        signingid = ""
        username = ""
        props = [String: String]()
    }
}


public class ESClient {
    var client: OpaquePointer?
    var connected: Bool
    var callback: (FileMonitoringEvent) -> Void
    let subEvents = [ES_EVENT_TYPE_NOTIFY_OPEN,
                     ES_EVENT_TYPE_NOTIFY_CLOSE,
                     ES_EVENT_TYPE_NOTIFY_CREATE,
                     ES_EVENT_TYPE_NOTIFY_CLONE,
                     ES_EVENT_TYPE_NOTIFY_FILE_PROVIDER_UPDATE,
                     ES_EVENT_TYPE_NOTIFY_RENAME,
                     ES_EVENT_TYPE_NOTIFY_UNLINK]
    
    init(completion: @escaping (FileMonitoringEvent) -> Void) {
        connected = false
        client = nil
        callback = completion
    }
    
    func startEventProducer() -> ESClientError {
        var client: OpaquePointer?
        var err = ESClientError.success
        
        if connected {
            NSLog("ESClient already connected.")
            return err
        }
        
        let dispatchQueue = DispatchQueue(label: "esclient", qos: .default)
        
        dispatchQueue.sync {
            let res  = es_new_client(&client) { _, event in
                self.eventDispatcher(msg: event)
            }
            
            if res != ES_NEW_CLIENT_RESULT_SUCCESS {
                if res == ES_NEW_CLIENT_RESULT_ERR_NOT_ENTITLED {
                    NSLog("Endpoint Security entitlement not found.")
                    err = ESClientError.missingEntitlements
                    return
                }
                NSLog("Failed to initialize ES client: \(res)")
                return
            }
            
            let ret = es_subscribe(client!, self.subEvents, UInt32(self.subEvents.count))
            if ret != ES_RETURN_SUCCESS {
                err = ESClientError.failedSubscription
                NSLog("Failed to subscribe to event source: \(ret)")
                return
            }

            self.client = client
            self.connected = true
        }
        
        return err
    }
    
    
    func stopEventProducer() {
        if connected, client != nil {
            connected = false
            if ES_RETURN_ERROR == es_unsubscribe(client!, subEvents, UInt32(subEvents.count)) {
                NSLog("Failed to unsubscibe to ESF")
            }
            if ES_RETURN_ERROR == es_delete_client(client!) {
                NSLog("Unable to delete resources - ESF resource leak")
            }
            client = nil
        }
    }
    
    func eventDispatcher(msg: UnsafePointer<es_message_t>) {
        let proc: es_process_t = msg.pointee.process.pointee
        var cEvent = FileMonitoringEvent()

        let path = proc.executable.pointee.path

        cEvent.processpath = getString(tok: path)
        cEvent.pid = audit_token_to_pid(proc.audit_token)
        cEvent.ppid = proc.ppid
        cEvent.timestamp = Int(msg.pointee.time.tv_sec * 1000) + Int(msg.pointee.time.tv_nsec / (1000 * 1000))
        cEvent.username = getUsername(id: audit_token_to_euid(proc.audit_token))
        cEvent.isplatform = proc.is_platform_binary
        cEvent.signingid = getString(tok: proc.signing_id)
        
        switch msg.pointee.event_type {
        case ES_EVENT_TYPE_NOTIFY_OPEN:
            cEvent.eventtype = "file::open"
            parseFileEvent(msg: msg, cEvent: &cEvent)
            
        case ES_EVENT_TYPE_NOTIFY_CLOSE:
            cEvent.eventtype = "file::close"
            parseFileEvent(msg: msg, cEvent: &cEvent)
        
        case ES_EVENT_TYPE_NOTIFY_CREATE:
            cEvent.eventtype = "file::create"
            parseFileEvent(msg: msg, cEvent: &cEvent)
        
        case ES_EVENT_TYPE_NOTIFY_CLONE:
            cEvent.eventtype = "file::clone"
            parseFileEvent(msg: msg, cEvent: &cEvent)
        
        case ES_EVENT_TYPE_NOTIFY_FILE_PROVIDER_UPDATE:
            cEvent.eventtype = "file::update"
            parseFileEvent(msg: msg, cEvent: &cEvent)
            
        case ES_EVENT_TYPE_NOTIFY_RENAME:
            cEvent.eventtype = "file::rename"
            parseRenameEvent(msg: msg, cEvent: &cEvent)
            
        case ES_EVENT_TYPE_NOTIFY_UNLINK:
            cEvent.eventtype = "file::unlink"
            parseUnlinkEvent(msg: msg, cEvent: &cEvent)
        default:
            break
        }
    }
}

extension ESClient {
   
    func parseFileEvent(msg: UnsafePointer<es_message_t>, cEvent: inout FileMonitoringEvent) {
        var fileEvent: Dictionary = [String: String]()

        let file: es_file_t = msg.pointee.event.create.destination.new_path.dir.pointee
        fileEvent["path"] = getString(tok: file.path)
        fileEvent["size"] = String(file.stat.st_size)

        cEvent.props = fileEvent

        callback(cEvent)
    }
    
    func parseRenameEvent(msg: UnsafePointer<es_message_t>, cEvent: inout FileMonitoringEvent) {
        var fileEvent: Dictionary = [String: String]()

        let file: es_file_t = msg.pointee.event.rename.source.pointee
        fileEvent["srcpath"] = getString(tok: file.path)
        fileEvent["srcsize"] = String(file.stat.st_size)

        fileEvent["desttype"] = String(msg.pointee.event.rename.destination_type.rawValue)
        fileEvent["destfile"] = getString(tok: msg.pointee.event.rename.destination.new_path.filename)

        let dstfile: es_file_t = msg.pointee.event.rename.destination.existing_file.pointee
        fileEvent["destdir"] = getString(tok: dstfile.path)

        cEvent.props = fileEvent

        callback(cEvent)
    }
    
    func parseUnlinkEvent(msg: UnsafePointer<es_message_t>, cEvent: inout FileMonitoringEvent) {
        var deleteEvent: Dictionary = [String: String]()

        let dir = msg.pointee.event.unlink.parent_dir.pointee.path
        deleteEvent["dir"] = getString(tok: dir)

        let path = msg.pointee.event.unlink.target.pointee.path
        deleteEvent["path"] = getString(tok: path)

        cEvent.props = deleteEvent

        callback(cEvent)
    }
}

//getting username from uid
public func getUsername(id: uid_t) -> String {
    guard let passwd = getpwuid(id)?.pointee.pw_name else { return "" }
    return String(cString: passwd)
}

// Converts a es_string_token_t to swift string
func getString(tok: es_string_token_t) -> String {
    if tok.length > 0 {
        return String(cString: tok.data)
    }

    return ""
}

extension String {
    init<T>(tupleOfCChars: T, length: Int = Int.max) {
        self = withUnsafePointer(to: tupleOfCChars) {
            let lengthOfTuple = MemoryLayout<T>.size / MemoryLayout<CChar>.size
            return $0.withMemoryRebound(to: UInt8.self, capacity: lengthOfTuple) {
                String(bytes: UnsafeBufferPointer(start: $0, count: Swift.min(length, lengthOfTuple)), encoding: .utf8)!
            }
        }
    }
}


public enum FileMonitorError: Error {
    case success
    case failedEnable
    case alreadyEnabled
    case newClientError
    case failedSubcription
}

public func enableFileMonitoring(completion: @escaping (_: FileMonitoringEvent) -> Void) -> (client: ESClient, error: FileMonitorError) {
    let client = ESClient(completion: completion)
    let ret = client.startEventProducer()
    if ret != ESClientError.success {
        return (client, FileMonitorError.failedSubcription)
    }
    NSLog("Enable File Acess Monitoring")
    return (client, FileMonitorError.success)
}

public func disableFileMonitoring(esclient: ESClient) -> FileMonitorError {
    esclient.stopEventProducer()
    NSLog("File Access Monitoring disabled.")
    return FileMonitorError.success
}


