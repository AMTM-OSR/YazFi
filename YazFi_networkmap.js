/**----------------------------**/
/** Last Modified: 2026-Jul-29 **/
/**----------------------------**/

/* YAZFI_NETWORKMAP_INJECT_V1 */
var yazfiClientData = [];
var yazfiClientDataTime = 0;
var yazfiClientRequestActive = false;
var yazfiClientRebuildActive = false;

function yazfiRequestClientData(force)
{
    var now = new Date().getTime();

    if (yazfiClientRequestActive)
        return;

    if (!force && (now - yazfiClientDataTime) < 5000)
        return;

    yazfiClientRequestActive = true;

    try {
        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== 4)
                return;

            yazfiClientRequestActive = false;
            yazfiClientDataTime = new Date().getTime();

            if (xhr.status === 200 || xhr.status === 0)
            {
                try {
                    var parsed = JSON.parse(xhr.responseText);
                    yazfiClientData = (parsed && typeof parsed.length !== "undefined") ? parsed : [];
                }
                catch (e) {
                    yazfiClientData = [];
                }
            }

            /* Rebuild once after fresh guest data arrives. */
            if (!yazfiClientRebuildActive && typeof genClientList === "function")
            {
                yazfiClientRebuildActive = true;
                try {
                    genClientList();
                    if (typeof show_client_status === "function")
                        show_client_status(totalClientNum.online);
                }
                catch (e2) {}
                yazfiClientRebuildActive = false;
            }
        };
        xhr.open("GET", "/ext/YazFi/networkmap_clients.json?_=" + now, true);
        xhr.setRequestHeader("Cache-Control", "no-cache");
        xhr.send(null);
    }
    catch (e) {
        yazfiClientRequestActive = false;
    }
}

function yazfiFallbackSourceClient()
{
    return {
        from: "networkmapd",
        isOnline: "1",
        type: "0",
        defaultType: "0",
        ip: "",
        ip6: "",
        ip6_prefix: "",
        mac: "",
        name: "",
        nickName: "",
        isGateway: "0",
        isWebServer: "0",
        isPrinter: "0",
        isITunes: "0",
        dpiDevice: "",
        vendor: "",
        rssi: "-99",
        isWL: "1",
        isGN: "1",
        opMode: "0",
        isLogin: "0",
        group: "",
        callback: "",
        keeparp: "0",
        ipMethod: "DHCP",
        qosLevel: "",
        wtfast: "0",
        internetMode: "allow",
        internetState: "1",
        curTx: "",
        curRx: "",
        wlConnectTime: "00:00:00",
        ROG: "0"
    };
}

function yazfiSavedClients()
{
    var saved = {};
    var list = "";

    /* The Network Map page keeps the latest names in custom_name, updated on each Apply. */
    try {
        if (typeof parent.custom_name === "string")
            list = parent.custom_name;
        else if (typeof card_client_variable !== "undefined")
            list = card_client_variable.custom_clientlist;
    }
    catch (e) {}

    var rows = String(list || "").split("<");
    for (var i = 0; i < rows.length; i++)
    {
        var fields = rows[i].split(">");
        if (fields.length > 3 && fields[1])
            saved[fields[1].toUpperCase()] = { nickName: fields[0], type: fields[3] || "0" };
    }

    return saved;
}

function yazfiMergeIntoOriginData()
{
    try {
        if (typeof originData === "undefined" ||
            !originData.fromNetworkmapd ||
            !originData.fromNetworkmapd[0])
        {
            yazfiRequestClientData(false);
            return;
        }

        var block = originData.fromNetworkmapd[0];
        if (!block.maclist || typeof block.maclist.length === "undefined")
            block.maclist = [];

        var i, key, seed = null;
        var saved = yazfiSavedClients();

        /* Remove clients inserted during the previous rebuild. */
        for (i = block.maclist.length - 1; i >= 0; i--)
        {
            key = block.maclist[i];
            if (block[key] && block[key]._yazfiInjected === "1")
            {
                delete block[key];
                block.maclist.splice(i, 1);
            }
        }

        for (i = 0; i < block.maclist.length; i++)
        {
            key = block.maclist[i];
            if (block[key] && typeof block[key] === "object")
            {
                seed = block[key];
                break;
            }
        }

        for (i = 0; i < yazfiClientData.length; i++)
        {
            var guest = yazfiClientData[i];
            if (!guest || !guest.mac || !guest.ip)
                continue;

            var mac = String(guest.mac).toUpperCase();
            var j, obj, exists = false;

            for (j = 0; j < block.maclist.length; j++)
            {
                if (String(block.maclist[j]).toUpperCase() === mac)
                {
                    exists = true;
                    break;
                }
            }

            /* Never replace a real ASUS/networkmap entry. */
            if (exists || (block[mac] && block[mac]._yazfiInjected !== "1"))
                continue;

            try {
                obj = seed ? JSON.parse(JSON.stringify(seed)) : yazfiFallbackSourceClient();
            }
            catch (cloneError) {
                obj = yazfiFallbackSourceClient();
            }

            obj.from = "networkmapd";
            obj.mac = mac;
            obj.ip = String(guest.ip);
            obj.ip6 = "";
            obj.ip6_prefix = "";
            obj.name = guest.name ? String(guest.name) : mac;
            obj.nickName = saved[mac] ? saved[mac].nickName : "";
            obj.isOnline = "1";
            obj.isWL = String(guest.isWL || "1");
            obj.isGN = String(guest.isGN || "1");
            obj.rssi = String(guest.rssi || "-99");
            obj.type = saved[mac] ? saved[mac].type : "0";
            obj.defaultType = "0";
            obj.isGateway = "0";
            obj.isWebServer = "0";
            obj.isPrinter = "0";
            obj.isITunes = "0";
            obj.dpiDevice = "";
            obj.vendor = "";
            obj.opMode = "0";
            obj.isLogin = "0";
            obj.group = "";
            obj.callback = "";
            obj.keeparp = "0";
            obj.ipMethod = "DHCP";
            obj.qosLevel = "";
            obj.wtfast = "0";
            obj.internetMode = "allow";
            obj.internetState = "1";
            obj.ROG = "0";

            obj.curTx = (guest.curTx !== undefined && guest.curTx !== null)
                ? String(guest.curTx)
                : "";

            obj.curRx = (guest.curRx !== undefined && guest.curRx !== null)
                ? String(guest.curRx)
                : "";

            obj.wlConnectTime = guest.wlConnectTime
                ? String(guest.wlConnectTime)
                : "00:00:00";

            obj.amesh_isRe = "0";
            obj.amesh_isReClient = "0";
            obj.amesh_papMac = "";
            obj.amesh_bind_mac = "";
            obj.amesh_bind_band = "0";
            obj._yazfiInjected = "1";

            block.maclist.push(mac);
            block[mac] = obj;
        }

        yazfiRequestClientData(false);
    }
    catch (e) {
        yazfiRequestClientData(false);
    }
}
