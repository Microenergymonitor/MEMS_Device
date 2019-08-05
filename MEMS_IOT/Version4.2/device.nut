// IMPORTS
#require "JSONParser.class.nut:1.0.0"
#require "JSONEncoder.class.nut:2.0.0"
//**************************** Connection standard ************************
// Needed to be First as to tell IMP Policy on disconnect we want to run all the time
server.setsendtimeoutpolicy(RETURN_ON_ERROR, WAIT_TIL_SENT, 10);
// Used for the Pulse IO
Pulseio <- hardware.pin1;
// Alias the One Wire
ow <- hardware.uart57;
// Assign pinA to a Relay Output 1
Relay_1 <- hardware.pinA;
// Assign pinA to a Relay Output 2
Relay_2 <- hardware.pinB;
// Assign pinA to a Relay Output 3
Relay_3 <- hardware.pinC;
//**************************** globals Definitions ************************
// the alarms active
local alarms = [];
local sensorOneFaulty = false;
local sensorTwoFaulty = false;
local sensorThreeFaulty = false;
local tempSensor1OverTempStart = null;
local tempSensor2OverTempStart = null;
local tempSensor3OverTempStart = null;
local tempSensor1OverTempActive = false;
local tempSensor2OverTempActive = false;
local tempSensor3OverTempActive = false;

// Assign a global variable to track both T1 T2 AND T3
Tem_T1 <-0;
Tem_T2 <-0;
Tem_T3 <-0;

// Used to trigger Sensor Update
SensorUpdate <- false;

// Assign a global variable to SetSwitch Points
Tem_HIGH <--18;
Tem_SAFE <--20.5;

// This allows the device to wait on till its safe
Tem_ONTILLSAFE_1 <- false;
Tem_ONTILLSAFE_2 <- false;
Tem_ONTILLSAFE_3 <- false;

// Assign a global variable to state of the pulses
pulse_count <- 0; 

// Used to stop race condition
pulse_state <- 1; 

// Assign a global variable to track current state of Relay pin
relayState_1 <- 0;

// Assign a global variable to track current state of Relay pin
relayState_2 <- 0;

// Assign a global variable to track current state of Relay pin
relayState_3 <- 0;

// Assign a global variable to track slaves list for one wire
slaves <- [];

// global for all the unknown sensors
Unknown_Sensor_IDs <-"";

// #TODO Needs to add error code for units to let harry know if the temp sensor or relay are faulty..
// Used to ensure we find all 3 if one is missing we set the relay to always off i.e. power to fridge as could be a faulty sensor.
TemSensor1Found <- false;
TemSensor2Found <- false;
TemSensor3Found <- false;

// Sensor Guard theses Globals are used to compare the values 
local gTemCount1 = 3;
local gTemCount2 = 3;
local gTemCount3 = 3;

// Assign a global variable to track state of connection.
local disconnectedFlag = false;
local disconnectedCount = 0;

// The deviceSettings for use in sensor use and logging
local deviceSettings = {};
deviceSettings.deviceControlStatus <-0;
deviceSettings.loggingEnabled <- 0;
deviceSettings.deviceLoggingInterval <- 30;
deviceSettings.relayOneSensorId <- "NULL";
deviceSettings.relayOneOnSetpoint <- -18;
deviceSettings.relayOneOffSetpoint <- -21;
deviceSettings.relayTwoSensorId <- "NULL";
deviceSettings.relayTwoOnSetpoint <- -18;
deviceSettings.relayTwoOffSetpoint <- -21;
deviceSettings.relayThreeSensorId <- "NULL";
deviceSettings.relayThreeOnSetpoint <- -18;
deviceSettings.relayThreeOffSetpoint <- -21;
deviceSettings.settingsVersion <- -1;
deviceSettings.thermalAlarmAfter <- 3600;
deviceSettings.relayThreeFreezerLocation<-"unknown";
deviceSettings.relayTwoFreezerLocation<-"unknown";
deviceSettings.relayOneFreezerLocation<-"unknown";
deviceSettings.relayOneFreezerName<-"unknown";
deviceSettings.relayTwoFreezerName<-"unknown";
deviceSettings.relayThreeFreezerName<-"unknown";
server.log(deviceSettings.relayThreeFreezerLocation);
// Used to track and send the device data to the agent.
local deviceReading = {};
deviceReading.relayOneSensor <-100;
deviceReading.relayTwoSensor <-100;
deviceReading.relayThreeSensor <-100;
deviceReading.pulseCount <-0;
deviceReading.UnknownDevices <-"NONE";
deviceReading.numberOfAciveAlarms <-0;
deviceReading.alarms <-[];

// Last Update Time
local LastUpdateTime = 0;
// ********************* Alarms *********************
function setAlarm (type,description,sensor,location)
{
    local alarm = {};
    local found = false;
    alarm.type <- type;
    alarm.description <- description;
    alarm.sensor <- sensor;
    alarm.location <- location;
    foreach(activeAlarm in alarms)
    {
        if (activeAlarm.type == type && activeAlarm.sensor == sensor  )
        {
            found = true;
            server.log("Found the alarm ");
        }
    }
    if (found == false)
    {
        server.log("inserted the alarm");
        getData(true) ;
        alarms.insert(0,alarm);
    }

}
function unsetAlarm (type,sensor)
{
    local count = 0;
    foreach(activeAlarm in alarms)
    {
        if (activeAlarm.type == type && activeAlarm.sensor == sensor )
        {
            found = true;
            server.log("Found the alarm Removing");
            alarms.remove(count);
        }
        count++;
    }


}

// ********************* Functions for Webserver *********************
function getData(forceUpdate) 
{
    //server.log(deviceReading.relayOneSensor);
    //server.log(deviceReading.relayTwoSensor);
   // server.log("thermal alarm after !" + deviceSettings.thermalAlarmAfter);
   server.log(alarms.len());
	foreach(alarm in alarms)
	{
	    server.log(alarm.sensor);
	}
    // Calcaulte the trigger is active.
    local trigger = (hardware.millis() - LastUpdateTime) > deviceSettings.deviceLoggingInterval.tointeger();
    // Send the readings
    if ((trigger || forceUpdate) && (disconnectedFlag == false) )
    {
    // set the pluse count as pulse count
    deviceReading.pulseCount = pulse_count;
    deviceReading.numberOfAciveAlarms = alarms.len(); 
    deviceReading.alarms = alarms;
    // Reset the pulse count
    pulse_count = 0;
    agent.send("deviceReading", deviceReading);
    LastUpdateTime = hardware.millis();
    local Temp1 = 0;
    local Temp2 = 0;
    local Temp3 = 0;
    }
    else if (trigger)
    {
        // Rewait but DO NOT RESET COUNT of pulses
        LastUpdateTime = hardware.millis();
    }
}
//*********************Functions for returnFromAgent *********************
function GetDeviceSettings(updateMessage) 
{
  local jsonStringFromFlash = imp.getuserconfiguration();
  agent.send("deviceSettings",jsonStringFromFlash);
}
// When we get a 'pong' message from the agent, call returnFromAgent()
agent.on("GetDeviceSettings", GetDeviceSettings);
//****************************  Functions for returnFromAgent *********************
function returnFromAgent(updateMessage) 
{
  server.log(updateMessage.relay + " " + updateMessage.sensor);
  updateFlash(updateMessage.relay,updateMessage.sensor);
}
// When we get a 'pong' message from the agent, call returnFromAgent()
agent.on("returnFromAgent", returnFromAgent);
//**************************** Update Device from Flash *********************
// Read the JSON from the Flash and pass to local Variables
function readFlashAndUpdate()
{
    // Get the default value by turing the table at the top into the default table
    local jsonStringdefault = JSONEncoder.encode(deviceSettings);
    // Load the data from the Flash
    local jsonStringFromFlash = imp.getuserconfiguration();
    // Try Parse the data
    try 
    {
        result <- JSONParser.parse(jsonStringFromFlash.tostring());
        deviceSettings.deviceControlStatus = result.deviceControlStatus;
        deviceSettings.loggingEnabled = result.loggingEnabled;
        deviceSettings.deviceLoggingInterval= result.deviceLoggingInterval;
        deviceSettings.relayOneSensorId = result.relayOneSensorId;
        deviceSettings.relayOneOnSetpoint = result.relayOneOnSetpoint;
        deviceSettings.relayOneOffSetpoint = result.relayOneOffSetpoint;
        deviceSettings.relayTwoSensorId = result.relayTwoSensorId;
        deviceSettings.relayTwoOnSetpoint = result.relayTwoOnSetpoint;
        deviceSettings.relayTwoOffSetpoint = result.relayTwoOffSetpoint;
        deviceSettings.relayThreeSensorId = result.relayThreeSensorId;
        deviceSettings.relayThreeOnSetpoint = result.relayThreeOnSetpoint;
        deviceSettings.relayThreeOffSetpoint = result.relayThreeOffSetpoint;
        deviceSettings.settingsVersion = result.settingsVersion;
        deviceSettings.thermalAlarmAfter = result.thermalAlarmAfter;
        deviceSettings.relayThreeFreezerLocation=result.relayThreeFreezerLocation;
        deviceSettings.relayTwoFreezerLocation=result.relayTwoFreezerLocation;
        deviceSettings.relayOneFreezerLocation=result.relayOneFreezerLocation;
        deviceSettings.relayOneFreezerName=result.relayOneFreezerName; 
        deviceSettings.relayTwoFreezerName=result.relayTwoFreezerName; 
        deviceSettings.relayThreeFreezerName=result.relayThreeFreezerName; 
        server.log("Updated from Flash :"+jsonStringFromFlash);
    }
    catch (err)
    {
        // Warn user that there maybe a issue
        server.log("No Settings loaded to the memory loading default");
        // Load the default user data i.e. the vars at the top
        server.log("Default Settings :"+jsonStringdefault);
        // Load the default into memory
        imp.setuserconfiguration(jsonStringdefault);
    }
}
//------------------ Functions for updateFromDataBase ---------------------
function updateFromDataBase(dataToSendToDevice) 
{
  // Store the data as a converted String JSON
  server.log("Update received : " + dataToSendToDevice);
  settingFromiot <- JSONParser.parse(dataToSendToDevice.tostring());
  if(settingFromiot.settingsVersion !=  deviceSettings.settingsVersion)
  {
      imp.setuserconfiguration(dataToSendToDevice);
      server.log("Updating as version updated from "+ deviceSettings.settingsVersion +" to " + settingFromiot.settingsVersion);
      imp.reset();
  }
}
// When we get a 'pong' message from the agent, call returnFromAgent()
agent.on("updateFromDataBase", updateFromDataBase);

//------------------------ Functions for OneWire --------------------------
function onewireReset() {
    // Configure UART for 1-Wire RESET timing
    ow.configure(9600, 8, PARITY_NONE, 1, NO_CTSRTS);
    ow.write(0xF0);
    ow.flush();
    local read = ow.read();
    if (read == -1) {
        // No UART data at all
        server.log("No circuit connected to UART.");
        return false;
    } else if (read == 0xF0) {
        // UART RX will read TX if there's no device connected
        server.log("No 1-Wire devices are present.");
        slaves.clear();
        SensorUpdate = true;
        return false;
    } else {
        if(SensorUpdate ==true)
        {
            SensorUpdate = false;
            // Enumerate the slaves on the bus
            onewireSlaves();
        }
        // Switch UART to 1-Wire data speed timing
        ow.configure(115200, 8, PARITY_NONE, 1, NO_CTSRTS);
        return true;
    }
}
 
function onewireWriteByte(byte) {
    for (local i = 0 ; i < 8 ; i++, byte = byte >> 1) {
        // Run through the bits in the byte, extracting the
        // LSB (bit 0) and sending it to the bus
        onewireBit(byte & 0x01);
    }
} 
 
function onewireReadByte() {
    local byte = 0;
    for (local i = 0 ; i < 8 ; i++) {
        // Build up byte bit by bit, LSB first
        byte = (byte >> 1) + 0x80 * onewireBit(1);
    }
    return byte;
}
 
function onewireBit(bit) {
    bit = bit ? 0xFF : 0x00;
    ow.write(bit);
    ow.flush();
    local returnVal = ow.read() == 0xFF ? 1 : 0;
    return returnVal;
}
 
function onewireSearch(nextNode) {
    local lastForkPoint = 0;
 
    // Reset the bus and exit if no device found
    if (onewireReset()) {
        // There are 1-Wire device(s) on the bus, so issue the 1-Wire SEARCH command (0xF0)
        onewireWriteByte(0xF0);

        // Work along the 64-bit ROM code, bit by bit, from LSB to MSB
        for (local i = 64 ; i > 0 ; i--) {
            local byte = (i - 1) / 8;

            // Read bit from bus
            local bit = onewireBit(1);
            
            // Read the next bit
            if (onewireBit(1)) {
                if (bit) {
                    // Both bits are 1 which indicates that there are no further devices
                    // on the bus, so put pointer back to the start and break out of the loop
                    lastForkPoint = 0;
                    break;
                }
            } else if (!bit) {
                // First and second bits are both 0: we're at a node
                if (nextNode > i || (nextNode != i && (id[byte] & 1))) {
                    // Take the '1' direction on this point
                    bit = 1;
                    lastForkPoint = i;
                }                
            }
 
            // Write the 'direction' bit. For example, if it's 1 then all further
            // devices with a 0 at the current ID bit location will go offline
            onewireBit(bit);
            
            // Write the bit to the current ID record
            id[byte] = (id[byte] >> 1) + 0x80 * bit;
        }
    }
 
    // Return the last fork point so it can form the start of the next search
    return lastForkPoint
}
 
function onewireSlaves() {
    id <- [0,0,0,0,0,0,0,0];
    nextDevice <- 65;
    slaves.clear();
    while (nextDevice) {
        nextDevice = onewireSearch(nextDevice);
        
        // Store the device ID discovered by one_wire_search() in an array
        // Nb. We need to clone the array, id, so that we correctly save 
        // each one rather than the address of a single array
        slaves.push(clone(id));
    }
}
 
function getTemp() {
    local tempLSB = 0;
    local tempMSB = 0;
    local tempCelsius = 0;
    
    // Reset the 1-Wire bus
    local result = onewireReset();
    TemSensor1Found = false;
    TemSensor1Found = false;
    TemSensor1Found = false;
    
    if (result) {
        // Issue 1-Wire Skip ROM command (0xCC) to select all devices on the bus
        onewireWriteByte(0xCC);
  
        // Issue DS18B20 Convert command (0x44) to tell all DS18B20s to get the temperature
        // Even if other devices don't ignore this, we will not read them
        onewireWriteByte(0x44);
    
        // Wait 750ms for the temperature conversion to finish
        imp.sleep(0.75);
        local LoopIndex = 0;

        // reset the Unknown Devices
        deviceReading.UnknownDevices = "";
        Unknown_Sensor_IDs ="";
        foreach (device, slaveId in slaves) 
        {
            
            // Run through the list of discovered slave devices, getting the temperature
            // if a given device is of the correct family number: 0x28 for BS18B20
            if (slaveId[7] == 0x28) {
                onewireReset();
            
                // Issue 1-Wire MATCH ROM command (0x55) to select device by ID
                onewireWriteByte(0x55);
            
                // Write out the 64-bit ID from the array's eight bytes
                for (local i = 7 ; i >= 0 ; i--) {
                    onewireWriteByte(slaveId[i]);
                }
            
                // Issue the DS18B20's READ SCRATCHPAD command (0xBE) to get temperature
                onewireWriteByte(0xBE);
            
                // Read the temperature value from the sensor's RAM
                tempLSB = onewireReadByte();
                tempMSB = onewireReadByte();
            
                // Signal that we don't need any more data by resetting the bus
                onewireReset();
 
                // Calculate the temperature from LSB and MSB
                local raw = (tempMSB << 8) + tempLSB; 
                local temperature = ((raw << 16) >> 16)*0.0625; 
                local sensorID = format("%02x%02x%02x%02x%02x%02x",slaveId[1], slaveId[2], slaveId[3], slaveId[4], slaveId[5], slaveId[6]);
                
                if(sensorID == deviceSettings.relayOneSensorId)
                {
                    if (gTemCount1 != 0)
                    {
                        gTemCount1 --;
                    }
                    else
                    {
                    deviceReading.relayOneSensor = temperature;
                    }
                    TemSensor1Found = true;
                }
                else if(sensorID == deviceSettings.relayTwoSensorId)
                {
                    if (gTemCount2 != 0)
                    {
                        gTemCount2 --;
                    }
                    else
                    {
                    deviceReading.relayTwoSensor = temperature;
                    }
                    TemSensor2Found = true;
                }
                else if(sensorID == deviceSettings.relayThreeSensorId)
                {
                     if (gTemCount3 != 0)
                    {
                        gTemCount3 --;
                    }
                    else
                    {
                    deviceReading.relayThreeSensor = temperature;
                    }
                    TemSensor3Found = true;
                }
                else
                {
                   #TODO Add error code to server to tell harry senor falty
                   deviceReading.UnknownDevices = deviceReading.UnknownDevices + "ID:"+ sensorID +" ";
                }
            }
            LoopIndex ++;
        }
    }
    // Checks for Errors 
    CheckSensorsAreValid ();
    CheckForOverTemp();
}

function CheckForOverTemp()
{
    // 1a. exists first of all 
    if(TemSensor1Found == true)
    {
        if (sensorOneFaulty == true)
        {
            sensorOneFaulty = false;
            local comment = "Sensor faulty ! ";
            local sensor = deviceSettings.relayOneFreezerName;
            
            unsetAlarm(2,sensor);
            
        }
        server.log(deviceReading.relayOneSensor);
        // 2. if greater than the thershold 
        if(deviceReading.relayOneSensor.tofloat() > deviceSettings.relayOneOnSetpoint.tofloat())
        {
            server.log("OT");
            // 3a. if inactive the set active and update the time triggered
            if (tempSensor1OverTempActive == false)
            {
                server.log("OverTemp Detected on Sensor 1");
                tempSensor1OverTempActive = true; 
                tempSensor1OverTempStart = time();
                
            }
            // 3b. is already active
            else
            {
                // We check if the alarm is to be driven high
                if ((time() - tempSensor1OverTempStart) > deviceSettings.thermalAlarmAfter)
                {
                    // Rearm the alarm again as to allow a constant phase of alarm respoce as user may clear give a chance
                    tempSensor1OverTempStart = time();
                    
                    local sensor = deviceSettings.relayOneFreezerName;
                    local description = "A over temperture alarm has been raised as the sensor has detected that the temperture was greater than " + deviceSettings.relayOneOnSetpoint + " for greater than " + deviceSettings.thermalAlarmAfter + " seconds please check the unit.";
                    local location = deviceSettings.relayOneFreezerLocation;
                    setAlarm(1,description,sensor,location);
                }
            }
        }
        //1b. alarm is ok
        else
        {
            if (tempSensor1OverTempActive == true)
            {
            // Clear and ack the alarm
            tempSensor1OverTempActive = false;
            local sensor = deviceSettings.relayOneFreezerName;
            unsetAlarm(1,sensor);
            }
        }
    }
    else
    {
        // If the device is not detected we check that the user has assigned a sensor
        if (deviceSettings.relayOneSensorId != "NULL")
        {   
            // If reported Faulty no need to do twice.
            if ( sensorOneFaulty == false)
            {
            server.log("Sensor 1 Faulty");
            sensorOneFaulty = true;
            local description = "Sensor was not located or has failed to read correctly please address and check unit. ";
            local sensor = deviceSettings.relayOneFreezerName ;
            local location = deviceSettings.relayOneFreezerLocation;
            setAlarm(2,description,sensor,location);
            }
        }
    }
    // ------------------------ Sensor 2 --------------------------------
     // 1a. exists first of all 
    if(TemSensor2Found == true)
    {
        if (sensorTwoFaulty == true)
        {
            sensorTwoFaulty = false;
            local sensor = deviceSettings.relayTwoFreezerName ;
            unsetAlarm(2,sensor);
            
        }
        server.log(deviceReading.relayTwoSensor);
        // 2. if greater than the thershold 
        if(deviceReading.relayTwoSensor.tofloat() > deviceSettings.relayTwoOnSetpoint.tofloat())
        {
            server.log("OT");
            // 3a. if inactive the set active and update the time triggered
            if (tempSensor2OverTempActive == false)
            {
                server.log("OverTemp Detected on Sensor 2");
                tempSensor2OverTempActive = true; 
                tempSensor2OverTempStart = time();
                
            }
            // 3b. is already active
            else
            {
                // We check if the alarm is to be driven high
                if ((time() - tempSensor2OverTempStart) > deviceSettings.thermalAlarmAfter)
                {
                    // Rearm the alarm again as to allow a constant phase of alarm respoce as user may clear give a chance
                    tempSensor2OverTempStart = time();
                    local sensor = deviceSettings.relayTwoFreezerName;
                    local description = "A over temperture alarm has been raised as the sensor has detected that the temperture was greater than " + deviceSettings.relayTwoOnSetpoint + " for greater than " + deviceSettings.thermalAlarmAfter + " seconds please check the unit.";
                    local location = deviceSettings.relayTwoFreezerLocation;
                    setAlarm(1,description,sensor,location);
                }
            }
        }
        //1b. alarm is ok
        else
        {
            if (tempSensor2OverTempActive == true)
            {
            // Clear and ack the alarm
            tempSensor2OverTempActive = false;
            local sensor = deviceSettings.relayTwoFreezerName ;
            unsetAlarm(1,sensor);
            }
        }
    }
    else
    {
        // If the device is not detected we check that the user has assigned a sensor
        if (deviceSettings.relayTwoSensorId != "NULL")
        {   
            // If reported Faulty no need to do twice.
            if ( sensorTwoFaulty == false)
            {
            server.log("Sensor 2 Faulty");
            sensorTwoFaulty = true;
            local description = "Sensor was not located or has failed to read correctly please address and check unit. ";
            local sensor = deviceSettings.relayTwoFreezerName;
            local location = deviceSettings.relayTwoFreezerLocation;
            setAlarm(2,description,sensor,location);
            }
        }
    }
    //------------------------------ Sensor 3 ---------------------------------------
     // 1a. exists first of all 
    if(TemSensor3Found == true)
    {
        if (sensorThreeFaulty == true)
        {
            sensorThreeFaulty = false;
            local sensor = deviceSettings.relayThreeFreezerName;
            unsetAlarm(2,sensor);
            
        }
        server.log(deviceReading.relayThreeSensor);
        // 2. if greater than the thershold 
        if(deviceReading.relayThreeSensor.tofloat() > deviceSettings.relayThreeOnSetpoint.tofloat())
        {
            server.log("OT");
            // 3a. if inactive the set active and update the time triggered
            if (tempSensor3OverTempActive == false)
            {
                server.log("OverTemp Detected on Sensor 3");
                tempSensor3OverTempActive = true; 
                tempSensor3OverTempStart = time();
                
            }
            // 3b. is already active
            else
            {
                // We check if the alarm is to be driven high
                if ((time() - tempSensor3OverTempStart) > deviceSettings.thermalAlarmAfter)
                {
                    // Rearm the alarm again as to allow a constant phase of alarm respoce as user may clear give a chance
                    tempSensor3OverTempStart = time();
                    local sensor = deviceSettings.relayThreeFreezerName;
                    local description = "A over temperture alarm has been raised as the sensor has detected that the temperture was greater than " + deviceSettings.relayThreeOnSetpoint + " for greater than " + deviceSettings.thermalAlarmAfter + " seconds please check the unit.";
                    local location = deviceSettings.relayThreeFreezerLocation;
                    setAlarm(1,description,sensor,location);
                }
            }
        }
        //1b. alarm is ok
        else
        {
            if (tempSensor3OverTempActive == true)
            {
            // Clear and ack the alarm
            tempSensor3OverTempActive = false;
            local sensor = deviceSettings.relayThreeFreezerName ;
            unsetAlarm(1,sensor);
            }
        }
    }
    else
    {
        // If the device is not detected we check that the user has assigned a sensor
        if (deviceSettings.relayThreeSensorId != "NULL")
        {   
            // If reported Faulty no need to do twice.
            if ( sensorThreeFaulty == false)
            {
            server.log("Sensor 3 Faulty");
            sensorOneFaulty = true;
            local description = "Sensor was not located or has failed to read correctly please address and check unit. ";
            local sensor = deviceSettings.relayThreeFreezerName ;
            local location = deviceSettings.relayThreeFreezerLocation;
            setAlarm(2,description,sensor,location);
            }
        }
    }
}
// CheckSensorsAreValid :: When using the unit a sensor maybe faulty or missing if so then we set the temperature to 100 as to tell it to force a reset of the relay to off i.e. power to fridge
// Using the Var TemSensorNFound where N is the Sensor ID to catch this action...
function CheckSensorsAreValid ()
{
    #TODO: Add error Handler Here
 if (TemSensor1Found == false)
 {
     deviceReading.relayOneSensor = 100;
     gTemCount1 = 3;
 }
 if (TemSensor2Found == false)
  {
     deviceReading.relayTwoSensor = 100;
     gTemCount2 = 3;
 }
 if (TemSensor3Found == false)
 {
     deviceReading.relayThreeSensor = 100;
     gTemCount3 = 3;
 }
}
//**************************** Functions for DIGITAL IN PULES *****************************************//
// Notes :: When using the 1 as the trigger there seemed to always be a extra sample as there are two cyclse to IO.
// Using the Var pulse_state to catch this action...
function PulseIn() 
{
    local state = Pulseio.read();
    if(Pulseio.read() == 1)
    {
        pulse_count++
       //@DEBUG 
       //server.log("pulse " + pulse_count);
    }
}


function SetRelay() 
{
    local ConnectionStatus ="";
    local StatusOfUnit = "";
    if (disconnectedFlag == true)
    {
       ConnectionStatus = "OFFLINE" 
    }
    else
    {
        ConnectionStatus = "ONLINE" 
    }

    local now = date();
    local systemState_1 = 1;
    local systemState_2 = 1;
    local systemState_3 = 1;
    if (deviceSettings.deviceControlStatus.tointeger() == 1)
    {
        /******************************Sensor 1 **********************************/
        // If the Fridge is LESS THAN than the set point then close the relay cutting power to the fridge
        if (Tem_T1 > deviceSettings.relayOneOnSetpoint.tofloat())
        {
            Tem_ONTILLSAFE_1 = true;
            systemState_1 = 1;
            // Relay on as too high
            Relay_1.write(0);
        }
        // Keep on till below the safe point
        else if (Tem_ONTILLSAFE_1 == true && Tem_T1 > deviceSettings.relayOneOffSetpoint.tofloat() )
        {
           systemState_1 =1;
           Relay_1.write(0) 
        }
        // When detected that below Safe ZONE and to go below safe zone tell user
        else if (Tem_T1 < deviceSettings.relayOneOffSetpoint.tofloat() && Tem_ONTILLSAFE_1 == true)
        {
            systemState_1 =0;
            Tem_ONTILLSAFE_1 = false;
        }
        // When in safe zone Close Relay.
        else if (Tem_ONTILLSAFE_1 == false)
        {
            systemState_1 = 0;
            Relay_1.write(1);
        }
          /******************************Sensor 2 **********************************/
        // If the Fridge is LESS THAN than the set point then close the relay cutting power to the fridge
        if (Tem_T2 > deviceSettings.relayTwoOnSetpoint.tofloat())
        {
            Tem_ONTILLSAFE_2 = true;
            systemState_2 = 1;
            // Relay on as too high
            Relay_2.write(0);
        }
        // Keep on till below the safe point
        else if (Tem_ONTILLSAFE_2 == true && Tem_T2 > deviceSettings.relayTwoOffSetpoint.tofloat() )
        {
           systemState_2 =1;
           Relay_2.write(0) ;
        }
        // When detected that below Safe ZONE and to go below safe zone tell user
        else if (Tem_T2 < deviceSettings.relayTwoOffSetpoint.tofloat() && Tem_ONTILLSAFE_2 == true)
        {
            systemState_2 =0;
            Tem_ONTILLSAFE_2 = false;
        }
        // When in safe zone Close Relay.
        else if (Tem_ONTILLSAFE_2 == false)
        {
            systemState_2 = 0;
            Relay_2.write(1);
        }
        /******************************Sensor 3 **********************************/
        // If the Fridge is LESS THAN than the set point then close the relay cutting power to the fridge
        if (Tem_T3 > deviceSettings.relayThreeOnSetpoint.tofloat())
        {
            Tem_ONTILLSAFE_3 = true;
            systemState_3 = 1;
            // Relay on as too high
            Relay_3.write(0);
        }
        // Keep on till below the safe point
        else if (Tem_ONTILLSAFE_3 == true && Tem_T3 > deviceSettings.relayThreeOffSetpoint.tofloat() )
        {
           systemState_3 =1;
           Relay_3.write(0) 
        }
        // When detected that below Safe ZONE and to go below safe zone tell user
        else if (Tem_T3 < deviceSettings.relayThreeOffSetpoint.tofloat() && Tem_ONTILLSAFE_3 == true)
        {
            systemState_3 =0;
            Tem_ONTILLSAFE_3 = false;
        }
        // When in safe zone Close Relay.
        else if (Tem_ONTILLSAFE_3 == false)
        {
            systemState_3 = 0;
            Relay_3.write(1);
        }
    }
    else
    {
        // server.log("Control Status Off WARNING !!" + deviceSettings.deviceControlStatus);
        Relay_1.write(0);
        Relay_2.write(0);
        Relay_3.write(0);
        
    }
}
//****************************** Imp Reconnection  ******************************
function mainProgramLoop() 
{
  // Ensure the program loops safely every second
  getTemp();
  SetRelay();
  getData(false);
  imp.wakeup(1.0, mainProgramLoop);
}
//****************************** Connect - Reconnect ******************************
function serverOut(reason)
{
    // This function is called if the server connection is broken or re-established
    if (reason != SERVER_CONNECTED)
    {
        disconnectedFlag = true;
        // If disconnected schedule an re-connection attempt in 5 mins (300 secs)
        imp.wakeup(30, function() 
        {
            server.connect(serverOut, 30)
    	}
    	)
    }
    else
    {
        disconnectedFlag = false;
    }
}
//******************************restart ******************************
// Call restart if needed 
function restart(duration)
{
    imp.reset();
}
// When we get a 'restsrt' message from the agent, call restart()
agent.on("restart", restart);
//******************************Starting point ****************************** 
// Configure the pulse to call PulseIn() when the pin's state changes
server.log("MEMS 4.2: Harry Walsh & Robert Carroll")
Pulseio.configure(DIGITAL_IN_PULLUP, PulseIn);
// Configure the Relay
Relay_1.configure(DIGITAL_OUT, 0);
Relay_2.configure(DIGITAL_OUT, 0);
Relay_3.configure(DIGITAL_OUT, 0);
// START OF RUNTIME
server.onunexpecteddisconnect(serverOut);
// Update the Flash and device setting from the JSON storied in Flash
readFlashAndUpdate();
// Enumerate the slaves on the bus
onewireSlaves();
// main program will do all needed
mainProgramLoop();
