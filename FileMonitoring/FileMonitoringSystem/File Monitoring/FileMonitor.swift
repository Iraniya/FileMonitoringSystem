//
//  FileMonitor.swift
//  FileMonitoringSystem
//
//  Created by Iraniya Naynesh on 27/12/20.
//


import Foundation
import EndpointSecurity

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


