
#require "GoogleIoTCore.agent.lib.nut:1.0.0"

// GOOGLE IOT CORE CONSTANTS
// ---------------------------------------------------------------------------------
local deviceStatus = device.isconnected();
local deviceID = imp.configparams.deviceid;
local status = {
"deviceid" : deviceID, 
"deviceType" : "MEMSV4.2",
"deviceStatus" : deviceStatus,
"firmwareVersion" : "VERSION_2",
"settingsVersion" : -1

} ;

// Number of seconds to wait before the next publishing
const PUBLISH_DELAY = 8;
// Used to signal that the iot was ready for telematics and also state change events.
local firstTime = 0;

// This URL can also be dynamic. Or you can get a private key using some other approach and without this URL at all.

const PRIVATE_KEY_URL = "https://raw.githubusercontent.com/Microenergymonitor/MEMS_Device/master/priv_key.pem";


// Values for these constants can be obtained from outside instead of hardcoding
const GOOGLE_IOT_CORE_PROJECT_ID    = "mems-247519";
const GOOGLE_IOT_CORE_CLOUD_REGION  = "us-central1";
const GOOGLE_IOT_CORE_REGISTRY_ID   = "example-registry";
const GOOGLE_IOT_CORE_DEVICE_ID     = "example-device";


// ---------------------------------------------------------------------------------

// An error code to send to the imp-device when we can't connect
const ERROR_CANNOT_CONNECT = 1;
// An error code to send to the imp-device when we can't download a private key
const ERROR_CANNOT_INIT_SETTINGS = 1;
// Delay (in seconds) betweent reconnect attempts
const DELAY_RECONNECT = 5;

// You can add more log levels, like DEBUG, WARNING
enum LOG_LEVEL {
    INFO,
    ERROR
}

CfgStateExample <- {

    // Here you can make a multi-level logger
    log = function(text, level = LOG_LEVEL.INFO) {
        if (level == LOG_LEVEL.INFO) {
            server.log("[CfgStateExample] " + text);
        } else if (level == LOG_LEVEL.ERROR) {
            server.error("[CfgStateExample] " + text);
        }
        // Logs can be sent to some server/cloud/etc.
    }

    // This class is responsible for getting of application settings including credentials
    AppSettings = class {
        _log = null;

        projectId   = null;
        cloudRegion = null;
        registryId  = null;
        deviceId    = null;
        privateKey  = null;

        _privateKeyUrl = null;

        function constructor() {
            _log = CfgStateExample.log;
        }

        function init(callback) {
            projectId = GOOGLE_IOT_CORE_PROJECT_ID;
            cloudRegion = GOOGLE_IOT_CORE_CLOUD_REGION;
            registryId = GOOGLE_IOT_CORE_REGISTRY_ID;
            deviceId = GOOGLE_IOT_CORE_DEVICE_ID;
            _privateKeyUrl = PRIVATE_KEY_URL;
            _getPrivateKey(callback);
        }

        function _getPrivateKey(callback) {
            // You can store (with server.save(), for example) the key after it is downloaded
            // and then it can be loaded from the persistent storage
            // But here we download the key every time

            _log("Downloading the private key..");
            local downloaded = function(err, data) {
                if (err != 0) {
                    _log("Private key downloading is failed: " + err, LOG_LEVEL.ERROR);
                } else {
                    _log("Private key is loaded");
                    privateKey = data;
                }
                callback(err);
            }.bindenv(this);
            _downloadFile(_privateKeyUrl, downloaded);
        }

        // This code is just for example. Here you can place your code which will make a call to your server.
        // Or the server can push a key to the agent
        function _downloadFile(url, callback) {
            local req = http.get(url);
            local sent = null;

            sent = function(resp) {
                if (resp.statuscode / 100 == 3) {
                    if (!("location" in resp.headers)) {
                        _log("Downloading is failed: redirective response does not contain \"location\" header", LOG_LEVEL.ERROR);
                        callback(resp.statuscode, null);
                        return;
                    }
                    req = http.get(resp.headers.location);
                    req.sendasync(sent);
                } else if (resp.statuscode / 100 == 2) {
                    callback(0, resp.body);
                } else {
                    callback(resp.statuscode, null);
                }
            }.bindenv(this);

            req.sendasync(sent);
        }
    }

    // This class is responsible for communication with the imp-device
    DeviceCommunicator = class {
        _stateHandler = null;

        function init() {
            // device.on("state", _onStateReceived);
        }

        function sendError(error) {
            // You can send a signal to the imp-device about occured errors
            // According to this signal the imp-device can report to a customer about an error

            // device.send("error", error);
        }

        function sendConfiguration(config) {
            // Here you can prepare and send configuration updates to the imp-device
            // The imp-device can react on that by sending some singals to its hardware

            // device.send("config", config);

            // Here we imitate sending of a configuration update to the imp-device
            // and then we imitate receiving of a state from the imp-device. This state is actually that configuration
            _onStateReceived(config);
        }

        function setStateHandler(handler) {
            _stateHandler = handler;
        }

        function _onStateReceived(state) {
            // Here you can make some preprocessing of the received state and pass it in to the App's handler

            _stateHandler && _stateHandler(state);
        }
    }

    // This class implements the business-logic of the application
    App = class {
        _log = null;

        _googleIoTCoreClient = null;
        _appSettings         = null;
        _deviceCommunicator  = null;

        _reconnectTimer      = null;

        function constructor() {
            _log = CfgStateExample.log;
            _appSettings = CfgStateExample.AppSettings();
            _deviceCommunicator = CfgStateExample.DeviceCommunicator();
        }

        function start() {
            local settingsLoaded = function(err) {
                if (err != 0) {
                    // You can report to the imp-device about an important error
                    _deviceCommunicator.sendError(ERROR_CANNOT_INIT_SETTINGS);
                    return;
                }
                _initApp();
            }.bindenv(this);

            _appSettings.init(settingsLoaded);
        }

        function _initApp() {
            _googleIoTCoreClient = GoogleIoTCore.Client(_appSettings.projectId,
                                                        _appSettings.cloudRegion,
                                                        _appSettings.registryId,
                                                        _appSettings.deviceId,
                                                        _appSettings.privateKey,
                                                        _onConnected.bindenv(this),
                                                        _onDisconnected.bindenv(this));

            _googleIoTCoreClient.connect();

            // We want to report all state updates to the Google IoT Core cloud
            _deviceCommunicator.setStateHandler(_reportState.bindenv(this));

            // Here you can initialize your application specific objects
        }

        function _onConfigReceived(config) {
            _log("Configuration received: " + config.tostring());
            // Here you can do some actions according to the configuration received
            // We will simply send the configuration to the imp-device
            _deviceCommunicator.sendConfiguration(config);
        }
        function sendStatusOLOLUpdate() {
            _log("Reporting change state..");
            if(firstTime == 1)
            {
            local jsonBody = http.jsonencode(status);
            _googleIoTCoreClient.reportState(jsonBody, _onStateReported.bindenv(this));
            }
        }

        function _reportState(data) {
            _log("Reporting new state..");
            
            local jsonBody = http.jsonencode(status);
            _googleIoTCoreClient.reportState(jsonBody, _onStateReported.bindenv(this));
            // Enable the device to send updates after reboot.
            firstTime = 1;
        }

        function _onStateReported(data, error) {
            if (error != 0) {
                // Here you can handle received error code
                _log("Report state error: code = " + error, LOG_LEVEL.ERROR);
                return;
            }
            _log("State has been reported!");
        }
        
        function publishTelemetry()
        {
        _googleIoTCoreClient.publish(time().tostring(), null, onPublished.bindenv(this));
         }
    
        function onPublished(data, error) {
            if (error != 0) {
                server.error("Publish telemetry error: code = " + error);
                return;
            }
            server.log("Telemetry has been published. Data = " + data);
            imp.wakeup(PUBLISH_DELAY, publishTelemetry.bindenv(this));
        }

        function _onConnected(error) {
            if (error != 0) {
                _log("Can't connect: " + error, LOG_LEVEL.ERROR);
                // You can report to the imp-device about an important error
                _deviceCommunicator.sendError(ERROR_CANNOT_CONNECT);
                // Wait and try to connect again
                _log("Trying to connect again..");
                _reconnect();
            } else {
                _log("Connected successfully!");
                _log("Enabling configuration updates receiving..");
                _googleIoTCoreClient.enableCfgReceiving(_onConfigReceived.bindenv(this), _onCfgEnabled.bindenv(this));
            }
        }

        function _reconnect() {
            if (_reconnectTimer != null) {
                return;
            }
            local connect = function() {
                _reconnectTimer = null;
                _googleIoTCoreClient.connect();
            }.bindenv(this);
            _reconnectTimer = imp.wakeup(DELAY_RECONNECT, connect);
        }

        function _onCfgEnabled(error) {
            if (error != 0) {
                // Here you can handle received error code
                // For example, if it is an MQTT-specific error, you can just try again or reconnect and then try again
                _log("Can't enable configuration receiving: " + error, LOG_LEVEL.ERROR);
                return;
            }
            _log("Successfully enabled!");
        }

        function _onDisconnected(error) {
            _log("Disconnected: " + error);
            if (error != 0) {
                // Wait and reconnect if it was an unexpected disconnection
                _log("Trying to reconnect..");
                imp.wakeup(DELAY_RECONNECT, _googleIoTCoreClient.connect.bindenv(_googleIoTCoreClient));
            }
        }
    }
}

local count = 0;
// RUNTIME
// ---------------------------------------------------------------------------------
function loop(){
    //imp.sleep(1);
    count ++;
    server.log(count);
    if (count > 1)
    {
    cfgStateExample.publishTelemetry();
    }
    imp.wakeup(60, loop);
}
// Start Application
cfgStateExample <- CfgStateExample.App();
cfgStateExample.start();
loop();
// Start the readings loop



device.onconnect(function() {
    status.deviceStatus = true;
    cfgStateExample.sendStatusOLOLUpdate();
    server.log("Device connected to agent");
});

device.ondisconnect(function() { 
    status.deviceStatus = false;
    cfgStateExample.sendStatusOLOLUpdate();
    server.log("Device disconnected from agent");
});

//cfgStateExample.REPORTME("GOOGLE ROCKS");
