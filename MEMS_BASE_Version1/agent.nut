// IMPORTS
#require "JSONParser.class.nut:1.0.0"
#require "JSONEncoder.class.nut:2.0.0"
//------------------------------- GLOBAL VARIABLES -------------------------------------
// Used to track and send the device data to the agent.
local deviceReading = {};
deviceReading.relayOneSensor <-0;
deviceReading.relayTwoSensor <-0;
deviceReading.relayThreeSensor <-0;
deviceReading.pulseCount <-0;
deviceReading.UnknownDevices <-0;
// Used to Store the MEMs Data for URL and also device id
local MEMSData = {};
MEMSData.deviceURL <- "Unknown";
MEMSData.deviceid <- "Unknown";
// This is the responce object to send to.
local ToRespondTo = null;
//------------------------------- FUNCTIONS ---------------------------------------------
/*
This function allows the readings to be passed to the database
The data is JSON and gotten from the device.
*/
function ReadingFromDevice (reading) 
{
    // Format and save the data
    deviceReading = reading;
    GetDeviceInfo();
    sendDataToDataBase();
}
/*
This function allows the device info to be read.
*/
function GetDeviceInfo()
{
    MEMSData.deviceURL = http.agenturl();
    MEMSData.deviceid  = imp.configparams.deviceid;
}
/*
This function allows the device to send the data to the server and also get the responce for comparsion.
Register the function to handle data messages from the device
*/
function sendDataToDataBase()
{
    const url = "http://microenergymonitoring.appspot.com/deviceAccess";
    local headers = { "Content-Type" : "application/json"} ;
    local body = {
    "deviceURL" : MEMSData.deviceURL ,
    "deviceid" : MEMSData.deviceid , 
    "relayOneSensor" : deviceReading.relayOneSensor ,
    "relayTwoSensor" : deviceReading.relayTwoSensor ,
    "relayThreeSensor" : deviceReading.relayThreeSensor ,
    "pulseCount" : deviceReading.pulseCount ,
    "UnknownDevices" : deviceReading.UnknownDevices
    } ;

    // Convert to body
    local jsonBody = http.jsonencode(body) ;
    //  POST the values
    local request = http.post(url, headers, jsonBody);
    local response = request.sendsync();
    server.log(response.statuscode + ": " + response.body);
}
/*
This function allows the user to read the database and update
*/
function UpdateDeviceData()
{
    GetDeviceInfo();
    const url = "http://microenergymonitoring.appspot.com/UpdateSettings";
    local headers = { "Content-Type" : "application/json"} ;
    local body = {
    "deviceURL" : MEMSData.deviceURL ,
    "deviceid" : MEMSData.deviceid 
    } ;
   
    server.log("Trying to update!");
    // Convert to body
    local jsonBody = http.jsonencode(body) ;
    //  POST the values
    local request = http.post(url, headers, jsonBody);
    local response = request.sendsync();
    server.log(response.body);
    if (response.statuscode == 200)
    {
        server.log("Update responce gotten!");
        local responceBodyText = response.body;
        // First we find "deviceControlStatus"
        local locationOfDeviceControlStatus = responceBodyText.find("deviceControlStatus");
        // Next we split the substring out
        local responceData = responceBodyText.slice((locationOfDeviceControlStatus-2),responceBodyText.len());
        //DEBUG server.log("The device code was located @ "+ responceData);
        // Parse the JSON
        local result = JSONParser.parse(responceData);
        // Convert to Sting to send to device
        jsonString <- JSONEncoder.encode(result);
        // Send the data to the device
        device.send("updateFromDataBase", jsonString);
        // After all that send the responce all OK.
        ToRespondTo.send(200, "OK Update Completed Rebooting device afterwards");
        
    }
    else
    {
        server.log("Update failed!");
        ToRespondTo.send(500, "NOTOK Check the Script");
    }
}

/*
This function is a Callback on device responding to the GetSettings
*/
function deviceSettings(deviceSettings)
{
    // Respond with the 200 and settings
    ToRespondTo.send(200, deviceSettings);
}
/*
This function is the HTTP called Function.
*/
function updateUnit(request, response) 
{
  // Used for signalling the responder. 
  ToRespondTo = response;
  try 
  {
    server.log("Command Received Started" + request.query);
    if ("UpdateDevice" in request.query) 
    {
        server.log("Update Device Command Received Update Started");
        // Call the function that calls the database.
        UpdateDeviceData();
    }
    else if ("RestartDevice" in request.query)
    {
        device.send("restart",0);
        // send a response back saying everything was OK.
        response.send(200, "OK Update Completed restart");
    }
    else if ("GetDeviceSettings" in request.query)
    {
        device.send("GetDeviceSettings",0);
    }
    else if ("GetStatus" in request.query)
    {
        local connectedString = (device.isconnected() ? "on" : "off") + "line";
        // send a response back saying device status
        response.send(200, connectedString);
    }
  } 
  catch (ex) 
  {
    response.send(500, "Internal Server Error: " + ex);
  }
}
//------------------------------- HTTP REQUESTS ---------------------------------------------
// register the HTTP handler only one is a command to update
http.onrequest(updateUnit);
//------------------------------- DEVICE CALLBACKS ---------------------------------------------
device.on("deviceReading", ReadingFromDevice)
device.on("deviceSettings", deviceSettings)
