/*
 * Copyright (c) 2018 Tiago Martins.
 * Available under the MIT license. See https://opensource.org/licenses/MIT
 *
 * A simple UART over Bluetooth Low Energy, based on the Nordic UART Service.
 * 
 * Most UART functionality is encapsulated by a BleUART object. 
 * You can use the BleUART object to obtain scan results and then decide to which device to connect.
 * Otherwise you can instead directly tell the BleUART to connect to a MAC address.
 * In this case, the BleUART will attempt to find and connect to the device by itself.
 *
 * In this example, the BleUART is first used to scan; and then to 
 * connect to the first device with "UART" in it's name, if any.
 *
 * Before calling init() on the BleUART object, you need to ensure that:
 *  1. the device's Bluetooth is on;
 *  2. the device's location services are on (battery saving or coarse location should be enough);
 *  3. permission for "access coarse location" has been explicitly granted by the user.
 *
 * The BleUART will notify when a device is discovered, the connection state changes or a message is received.
 * For this purpose you need to implement the following (optional) methods in your sketch:
 *
 *  void bleUARTDeviceDiscovered(String name, String address);
 *  void bleUARTScanningFinished();
 *  void bleUARTConnected();
 *  void bleUARTDisconnected();
 *  void bleUARTMessageReceived(String message);
 *
 * The BleUART requires the following permissions: 
 *  ACCESS_COARSE_LOCATION (user prompt), BLUETOOTH, BLUETOOTH_ADMIN
 */


import android.widget.Toast;

static final String permissionCoarseLocation = "android.permission.ACCESS_COARSE_LOCATION";

BleUART bleUart;

String appText         = "";
String deviceListText  = "";
String messageSent     = "";
String messageReceived = "";


void setup() {
  fullScreen();
  orientation(PORTRAIT);
  
  float fontSize = height/35; 
  textFont(createFont("Monospaced", fontSize));
  
  bleUart = new BleUART(this);
  
  // this will make the BleUART object print a lot of info on the console
  // bleUart.setVerbose(true);
  
  // we need to prompt the user for the coarse location permission, 
  // as this is necessary for initializing the Ble
  if (!hasPermission(permissionCoarseLocation)) {
    println("setup() requesting permission ACCESS_COARSE_LOCATION (for Bluetooth LE scanning)");
    requestPermission(permissionCoarseLocation, "onLocationPermission");
  }
  else {
    // skip the prompt, trigger the callback
    onLocationPermission(true);
  }
}


// Called once the location permission is granted, initializes the BleUART object
void onLocationPermission(boolean permitted) {
  if (permitted) {
    bleUart.init();
  }
  else {
    println("You must grant the ACCESS_COARSE_LOCATION  permission, as this is required for Bluetooth LE scanning.");
  }
}


void draw() {
  // compose a string to display status on screen
  
  if (bleUart.isConnecting()) {
    appText = "BLE is connecting...";
  }
  else if (bleUart.isConnected()) {
    appText = "BLE is connected and ready";
    appText += "\n\nlast message received is";
    appText += "\n string [" + messageReceived + "]";
    appText += "\n hex [" + toHexString(messageReceived) + "]";
    appText += "\n\nlast message sent is";
    appText += "\n [" + messageSent + "]";
  }
  else if (bleUart.isScanning()) {
    appText = "BLE is scanning...";
  }
  else {
    appText = "BLE is disconnected";
  }
  
  if (bleUart.isConnected()) {
    appText += "\n\ntap to send a message";
  }
  else if (bleUart.getResultCount() > 0) {
    appText += "\n\ntap to connect to the first device with \"UART\" in the name";
    appText += "\n\n" + deviceListText;
  }
  else if (!bleUart.isScanning()) {
    appText += "\n\ntap to scan";
  }
  
  // draw 
  background(0);
  fill(255);
  text(appText, 20, 20, width -40, height -40);
}


void mousePressed() {
  // if the UART is connected and ready, send a message with the mouse position
  if (bleUart.isConnected()) {
    messageSent = "mouse: (" + mouseX + ", " + mouseY + ")";
    println("Sending message <" + messageSent + ">");
    bleUart.sendMessage(messageSent);
    return;
  }
  
  // otherwise, check if the Ble knows a device with "UART" in the name
  // if there is one, connect to it
  ArrayList<BLEDeviceSimple> deviceList = bleUart.getDeviceList();
  for (BLEDeviceSimple device : deviceList) {
    if (device.getName().contains("UART")) {
      println("Connecting to device <" + device.getName() + "> <" + device.getAddress() + ">"); 
      if (bleUart.isScanning) bleUart.stopScanning();
      bleUart.connectTo(device.getAddress());
      return;
    }
  }
  
  // otherwise start scanning
  bleUart.startScanning();
}


// updates the on-screen list of known devices
// called when a device is discovered
void updateDeviceListText() {
  deviceListText = "Device List --------";
  ArrayList<BLEDeviceSimple> deviceList = bleUart.getDeviceList();
  for (BLEDeviceSimple device : deviceList) {
    deviceListText += "\n  [" + device.getName() + "]\n  " + device.getAddress();
  }
}


// converts a string to hexadecimal format 
String toHexString(String str) {
  String hexStr = "";
  for (int i = 0; i < str.length(); i++) {
    hexStr += hex(str.charAt(i), 2);
  }
  return hexStr;
}


// tidy up
@Override
void stop() {
  if (bleUart != null) bleUart.dispose();
}


// Ble UART Callbacks -------------------------------------------------------------------------


// callback from the BleUART, when a device is discovered
void bleUARTDeviceDiscovered(String name, String address) {
  println("bleUARTDeviceDiscovered() <" + name + "> <" + address + ">");
  updateDeviceListText();
  
  // if you need the actual BluetoothDevice object, you can do:
  //   BluetoothDevice device = bleUart.getBluetoothDeviceByAddress(address);
  // addresses are unique whereas names are not, but you can also do:
  //   BluetoothDevice device = bleUart.getBluetoothDeviceByName(name);
}


// callback from the BleUART, when scanning has finished
void bleUARTScanningFinished() {
  println("bleUARTScanningFinished()");
  updateDeviceListText();
}


// callback from the BleUART, when the device is successfully connected 
// and configured (i.e. ready to transmit/receive) 
void bleUARTConnected() {
  println("bleUARTConnected()");
}


// callback from the BleUART, when the device is disconnected
void bleUARTDisconnected() {
  println("bleUARTDisconnected()");
}


// callback for when a message is received through the UART
// avoid doing heavy lifting here, just store the message and handle it during draw
void bleUARTMessageReceived(String message) {
  println("bleUARTMessageReceived() <" + message + ">");
  messageReceived = message;
}