//
//  Events.swift
//  FileMonitoringSystem
//
//  Created by Iraniya Naynesh on 27/12/20.
//

import Foundation
import EndpointSecurity

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
