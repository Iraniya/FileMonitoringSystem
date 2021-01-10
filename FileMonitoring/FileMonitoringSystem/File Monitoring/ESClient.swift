//
//  ESClient.swift
//  FileMonitoringSystem
//
//  Created by Iraniya Naynesh on 27/12/20.
//

import Foundation
import EndpointSecurity

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
