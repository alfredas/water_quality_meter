
#include <WaspFrame.h>
#include <WaspSensorSW.h>
#include <WaspWIFI_PRO.h>

// SETTINGS ///////////////////////

// define folder and file to store data
char DATA_FOLDER[] = "DATA";

// how long (mins) do we collect data before hibernating
long long AWAKE_MILLIS = 1LL * 60LL * 1000LL;

// enable local file storage
uint8_t ENABLE_WRITE_TO_FILE = 0;

// enable tcp data send
uint8_t ENABLE_SEND_OVER_TCP = 1;

char SLEEP_STRING[] = "00:00:01:00";

// WIFI settings ////////////////////////
char ESSID[] = "HomeBox-D790_2.4G";
char PASSW[] = "a5ec43d2e";
char SERVER_IP[] = "192.168.1.32";
char SERVER_PORT[] = "12345";
char LOCAL_PORT[]  = "3000";
char MOTE_ID[] = "WET_01";


// GLOBAL VARIABLES ////////////////////

// sd status variable
uint8_t error;
// data file
char data_file[20];
// buffer to write into Sd File
char toWrite[200];
// wifi socket
uint8_t socket = SOCKET0;
// wifi socket handle id
uint16_t socket_handle = 0;
// when was the last awake state
unsigned long last_wake_up_millis;

/////////////////////////////////////////


// SENSORS: //////////////////////////////

// Temperature /////////////////////////
pt1000Class temperatureSensor;

// PH //////////////////////////////////
pHClass pHSensor;

// PH Calibration values
#define cal_point_10  1.985
#define cal_point_7   2.070
#define cal_point_4   2.227

// Temperature at which calibration was carried out
#define cal_temp 23.7

// DO //////////////////////////////////
DOClass DOSensor;

// Calibration of the sensor in normal air
#define air_calibration 2.65
// Calibration of the sensor under 0% solution
#define zero_calibration 0.0

// EC //////////////////////////////////
conductivityClass ConductivitySensor;

// Value 1 used to calibrate the sensor
#define point1_cond 10500
// Value 2 used to calibrate the sensor
#define point2_cond 40000

// Point 1 of the calibration 
#define point1_cal 197.00
// Point 2 of the calibration 
#define point2_cal 150.00


///END SENSORS //////////////////////////



/**
 * Create folder for data on SD card
 */
void create_data_folder() {

  if (error == 1) {
    USB.println(F("STATUS: Skipping creating data folder."));
  } else {
    // list all files fyi
    SD.ls(LS_R|LS_DATE|LS_SIZE);

    // check if the data folder exists
    if ( SD.isDir(DATA_FOLDER) < 0 ) { 

      // make a new data folder
      error = !SD.mkdir(DATA_FOLDER);

      if ( error == 0 ) { 
        USB.println(F("STATUS: Data path created"));
      } else {
        USB.println(F("ERROR: Create data path failed"));
      }
    } else {
      USB.println(F("STATUS: Data path already exists. Will not create new."));
    }
  }
}

/**
 * Create data file in the data folder for data on SD card
 */
void create_data_file() {

  if (error == 1) {
    USB.println(F("STATUS: Skipping creating data file."));
  } else {
    USB.println(F("STATUS: Creating data file..."));

    // create new file for data
    // take the last 8 digits of current epoch and create 
    // a file DATA/12345678.TXT
    snprintf(data_file, sizeof(data_file), "%s/%lu.txt", DATA_FOLDER, (RTC.getEpochTime() % 100000000) );

    error = !SD.create(data_file);
    
    if ( error == 0 ) { 
      USB.print(F("STATUS: Data file created: "));
    } else {
      USB.print(F("ERROR: Failed to create data file:"));
    }
    USB.println(data_file);
  }
}

/**
 * Write frames to data file
 */
void write_frame_to_file() {
  memset(toWrite, 0x00, sizeof(toWrite)); 

  // Conversion from Binary to ASCII
  Utils.hex2str(frame.buffer, toWrite, frame.length);

  error = !SD.appendln(data_file, toWrite);

  if ( error == 0 ) {
    USB.println(F("STATUS: Frame appended to file"));
  } else {
    USB.println(F("ERROR: Write data to file failed"));
  }
}


/**
 * WIFI config 
 */
void configure_wifi() {
  
  error = WIFI_PRO.setESSID(ESSID);

  if (error == 0) {    
    USB.println(F("STATUS: WiFi set ESSID OK"));
  } else {
    USB.println(F("ERROR: WiFi set ESSID ERROR"));
  }

  error = WIFI_PRO.setPassword(WPA2, PASSW);

  if (error == 0) {    
    USB.println(F("STATUS: WiFi set AUTHKEY OK"));
  } else {
    USB.println(F("ERROR: WiFi set AUTHKEY ERROR"));
  }

  error = WIFI_PRO.softReset();

  if (error == 0) {    
    USB.println(F("STATUS: WiFi softReset OK"));
  } else {
    USB.println(F("ERROR: WiFi softReset ERROR"));
  }

}


/**
 * TCP connection 
 */
void connect_tcp() {

  error = WIFI_PRO.ON(socket);

  if (error == 0) {    
    USB.println(F("STATUS: WiFi ON"));
  } else {
    USB.println(F("ERROR: WiFi did not initialize correctly"));
  }

  // Check if module is connected
  if (WIFI_PRO.isConnected() == false) {
    // configure wifi
    configure_wifi();
  }

  if (WIFI_PRO.isConnected() == true) {
    // establish tcp connection
    error = WIFI_PRO.setTCPclient( SERVER_IP, SERVER_PORT, LOCAL_PORT);

    // check response
    if (error == 0) {
      // get socket handle (from 0 to 9)
      socket_handle = WIFI_PRO._socket_handle;
      USB.print(F("STATUS: Open TCP socket OK in handle: "));
      USB.println(socket_handle, DEC);
    } else {
      USB.println(F("ERROR: Error calling 'setTCPclient' function"));
      WIFI_PRO.printErrorCode();
    }
    
  } else {
    USB.println(F("ERROR: WiFi is not connected."));
  }
  
}

/**
 * Close TCP connection 
 */
void close_tcp() {
  error = WIFI_PRO.closeSocket(socket_handle);

  // check response
  if (error == 0) {
    USB.println(F("STATUS: Close socket OK"));   
  } else {
    USB.println(F("ERROR: Error calling 'closeSocket' function"));
    WIFI_PRO.printErrorCode(); 
  }

}


/**
 * Come back from hibernation
 */
void hibInterrupt() {
  // clear interruption flag
  intFlag &= ~(RTC_INT);
  
  USB.println(F("STATUS: Waking up."));

  // turn on water sensors
  Water.ON(); 
  USB.println(F("STATUS: WATER ON"));

  /////////////////////////////////
  // enable data over tcp?
  /////////////////////////////////
  if (ENABLE_SEND_OVER_TCP > 0) {
    // establish tcp connection
    connect_tcp();
  }

  // capture wake up millis
  last_wake_up_millis = millis();
}


/**
 * Send data over TCP 
 */
void send_frame_over_tcp() {
  
  // send data and check response
  if ( WIFI_PRO.send(socket_handle, frame.buffer,frame.length) == 0 ) {
    USB.println(F("STATUS: Send data OK"));   
  } else {
    USB.println(F("ERROR: Error calling 'send' function"));
    WIFI_PRO.printErrorCode();       
  }
}



/**
 * Calibrate Sensors
 */
void calibrate_sensors() {
  USB.println(F("STATUS: Calibrating sensors"));  
  
  // PH: Configure the calibration values 
  pHSensor.setCalibrationPoints(cal_point_10, cal_point_7, cal_point_4, cal_temp);

  // DO: Configure the calibration values
  DOSensor.setCalibrationPoints(air_calibration, zero_calibration);

  // EC: Configure the calibration values
  ConductivitySensor.setCalibrationPoints(point1_cond, point1_cal, point2_cond, point2_cal);
}

/**
 * Setup 
 */
void setup()  {

  USB.println(F("--------------SETUP-----------------"));
  
  USB.print(F("Free Memory:"));
  USB.println(freeMemory());

  // set error state to 0
  error = 0;

  // turn on USB
  USB.ON();
  USB.println(F("STATUS: USB ON"));

  // turn on time
  RTC.ON();
  USB.println(F("STATUS: RTC ON"));

  // calibrate sensors
  calibrate_sensors();

  // turn on water sensors
  Water.ON(); 
  USB.println(F("STATUS: WATER ON"));

  

  /////////////////////////////////
  // write data to file?
  /////////////////////////////////
  if (ENABLE_WRITE_TO_FILE > 0) {

    // turn on SD
    SD.ON();
    USB.println(F("STATUS: SD ON"));

    // create folder to store data
    create_data_folder();

    // create new file for data
    create_data_file();
  } else {
    USB.println(F("STATUS: File storage disabled."));
  }

  /////////////////////////////////
  // enable data over tcp?
  /////////////////////////////////
  if (ENABLE_SEND_OVER_TCP > 0) {
    connect_tcp();
  }  else {
    USB.println(F("STATUS: Send over TCP disabled."));
  }

  USB.println(F("--------------SETUP DONE-----------------"));

}


/**
 * Loop 
 */
void loop() { 

  // After wake up check interruption source
  if ( intFlag & RTC_INT ) {
    hibInterrupt();
  }

  if (error == 1) {
    USB.println(F("ERROR: Skipping loop."));
  } else {

    // Create new frame (ASCII)
    frame.createFrame(ASCII); 

    // read and add date
    //frame.addSensor(SENSOR_DATE, RTC.year, RTC.month, RTC.day);
    
    // read and add time
    // frame.addSensor(SENSOR_TIME, RTC.hour, RTC.minute, RTC.second );

    // read and add epoch
    frame.addSensor(SENSOR_TST, RTC.getEpochTime());

    // read and add battery levels
    frame.addSensor(SENSOR_BAT, PWR.getBatteryLevel());

    // Temperature sensor
    float temp = temperatureSensor.readTemperature();
    frame.addSensor(SENSOR_WATER_WT, temp);

    // PH sensor
    frame.addSensor(SENSOR_WATER_PH, pHSensor.pHConversion( pHSensor.readpH(), temp ) );

    // DO sensor
    frame.addSensor(SENSOR_WATER_DO, DOSensor.DOConversion( DOSensor.readDO() ) ); 
    
    // EC sonsor
    frame.addSensor(SENSOR_WATER_COND, ConductivitySensor.conductivityConversion( ConductivitySensor.readConductivity() ) );

    // add other sensors here

    //SENSOR_WATER_ORP  LITERAL1
    //SENSOR_WATER_TURB LITERAL1

    // log
    frame.showFrame();

    /////////////////////////////////
    // write data to file?
    /////////////////////////////////
    if (ENABLE_WRITE_TO_FILE > 0) {
      // write to file
      write_frame_to_file();
    }

    /////////////////////////////////
    // enable data over tcp?
    /////////////////////////////////
    if (ENABLE_SEND_OVER_TCP > 0) {
      send_frame_over_tcp();
    }


    // go to sleep if active for more than active_millis time
    if ( (millis() - last_wake_up_millis) > AWAKE_MILLIS) {
      // hibernate
      USB.println(F("STATUS: Going to sleep."));

      /////////////////////////////////
      // enable data over tcp?
      /////////////////////////////////
      if (ENABLE_SEND_OVER_TCP > 0) {
        // close tcp connection; we will need to reestablish it on wake up 
        close_tcp();
      }

      // turn OFF water sensors
      Water.OFF(); 
      USB.println(F("STATUS: WATER OFF"));

      // Set Waspmote to Hibernate, waking up after 30 minutes
      PWR.deepSleep(SLEEP_STRING, RTC_OFFSET,RTC_ALM1_MODE1,ALL_OFF);
    }


  }

  delay(2000);

}




