//
//  ping.swift
//  V2rayU
//
//  Created by Erick on 2019/10/30.
//  Copyright © 2019 yanue. All rights reserved.
//

import SwiftyJSON

// ping and choose fastest v2ray
var inPing = false
var fastV2rayName = ""
var fastV2raySpeed = 5
let pingJsonFileName = "ping.json"
let pingJsonFilePath = AppResourcesPath + "/" + pingJsonFileName

struct pingItem: Codable {
    var name: String = ""
    var host: String = ""
    var ping: String = ""
}

class PingSpeed: NSObject {

    var pingServers: [pingItem] = []

    func pingAll() {
        print("ping start")
        if inPing {
            print("ping inPing")
            return
        }
        // in ping
        inPing = true
        fastV2rayName = ""
        self.pingServers = []

        let normalTitle = menuController.statusMenu.item(withTag: 1)?.title ?? "Ping Speed..."
        let langStr = Locale.current.languageCode
        var pingTip: String = ""
        if UserDefaults.getBool(forKey: .autoSelectFastestServer) {
            if langStr == "en" {
                pingTip = "Ping Speed - In Testing(Choose fastest server)"
            } else {
                pingTip = "Ping Speed - 测试中(选择最快服务器)"
            }
        } else {
            if langStr == "en" {
                pingTip = "Ping Speed - In Testing "
            } else {
                pingTip = "Ping Speed - 测试中"
            }
        }
        menuController.statusMenu.item(withTag: 1)?.title = pingTip


        let queue = DispatchQueue.global()
        queue.async {

            self.writeServerToFile()
            self.pingInCmd()
            self.parsePingResult()

            DispatchQueue.main.async {
                menuController.statusMenu.item(withTag: 1)?.title = "\(normalTitle)"

                // refresh servers
                // reload
                V2rayServer.loadConfig()

                // if auto select fastest server
                if UserDefaults.getBool(forKey: .autoSelectFastestServer) && fastV2rayName.count > 0 {
                    if V2rayServer.getIndex(name: fastV2rayName) > -1 {
                        // set current
                        UserDefaults.set(forKey: .v2rayCurrentServerName, value: fastV2rayName)
                        // stop first
                        V2rayLaunch.Stop()
                        // start
                        menuController.startV2rayCore()
                    }
                }

                // refresh server
                menuController.showServers()
                // reload config
                if menuController.configWindow != nil {
                    menuController.configWindow.serversTableView.reloadData()
                }
                inPing = false
            }
        }
    }

    func writeServerToFile() {
        let itemList = V2rayServer.list()
        if itemList.count == 0 {
            return
        }

        for item in itemList {
            if !item.isValid {
                continue
            }

            let host = self.parseHost(item: item)
            guard let _ = NSURL(string: host) else {
                continue
            }

            let tmp = pingItem(name: item.name, host: host, ping: item.speed)

            self.pingServers.append(tmp)
        }

        // 1. encode to json text
        let encoder = JSONEncoder()
        let data = try! encoder.encode(self.pingServers)
        let jsonStr = String(data: data, encoding: .utf8)!

        try! jsonStr.data(using: String.Encoding.utf8)?.write(to: URL(fileURLWithPath: pingJsonFilePath), options: .atomic)
    }

    func pingInCmd() {
        let cmd = "cd " + AppResourcesPath + " && chmod +x ./V2rayUHelper && ./V2rayUHelper -cmd ping -t 5s -f ./" + pingJsonFileName
//        print("cmd", cmd)
        let res = shell(launchPath: "/bin/bash", arguments: ["-c", cmd])
        if res?.contains("ok") ?? false {
            // res is: ok config.xxxx
            fastV2rayName = res!.replacingOccurrences(of: "ok ", with: "")
            return
        }
    }

    func parsePingResult() {
        let jsonText = try? String(contentsOfFile: pingJsonFilePath, encoding: String.Encoding.utf8)
        guard let json = try? JSON(data: (jsonText ?? "").data(using: String.Encoding.utf8, allowLossyConversion: false)!) else {
            return
        }

        var pingResHash: Dictionary<String, String> = [:]
        if json.arrayValue.count > 0 {
            for val in json.arrayValue {
                let name = val["name"].stringValue
                let ping = val["ping"].stringValue
                pingResHash[name] = ping
            }
        }

        let itemList = V2rayServer.list()
        if itemList.count == 0 {
            return
        }

        for item in itemList {
            if !item.isValid {
                continue
            }
            let x = pingResHash[item.name]
            if x != nil && x!.count > 0 {
                item.speed = x!
                item.store()
            }
        }
    }

    func parseHost(item: V2rayItem) -> (String) {
        let cfg = V2rayConfig()
        cfg.parseJson(jsonText: item.json)

        var host: String = ""
        var port: Int
        if cfg.serverProtocol == V2rayProtocolOutbound.vmess.rawValue {
            host = cfg.serverVmess.address
            port = cfg.serverVmess.port
        } else if cfg.serverProtocol == V2rayProtocolOutbound.shadowsocks.rawValue {
            host = cfg.serverShadowsocks.address
            port = cfg.serverShadowsocks.port
        } else if cfg.serverProtocol == V2rayProtocolOutbound.socks.rawValue {
            if cfg.serverSocks5.servers.count == 0 {
                return ""
            }
            host = cfg.serverSocks5.servers[0].address
            port = Int(cfg.serverSocks5.servers[0].port)
        }

        return host
    }
}
