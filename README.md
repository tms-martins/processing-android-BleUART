
# processing-android-BleUART

An example of using the Nordic UART service on Bluetooth LE from Processing's Android Mode.

Made with Processing 3.3.6, Android Mode 4.0.1
Tested on a Moto G2 running Android 7.1.2 (custom ROM), with a Sparkfun ESP-32 Thing running a [Nordic UART Arduino example](https://github.com/nkolban/ESP32_BLE_Arduino/tree/af865a916795289c8e7e09b091ff2140c33fc3fe/examples/BLE_uart).

The example is currently missing code for enabling location and Bluetooth from within the app. This is pending on [an open issue](https://github.com/processing/processing-android/issues/452).

## Using the BleUART class

The BleUART class wraps the Bluetooth LE functionality for scanning, connecting and exchanging data with a BLE server running the Nordic UART service.

 1. Create and instantiate a BleUART object:
    `BleUART bleUart = new BleUART(this);` 
 2. Before initializing the object (see next step), make sure that
    1. The device's Bluetooth is on.
    2. The device's location services are on (battery saving or coarse location should be enough).
    3. permission for `Access Coarse Location` has been explicitly granted by the user.
 3. Initialize the BleUART object: 
    `bleUart.init();`
 4. If you have a fixed device you want to connect to, you can call: 
    `bleUart.connectTo("F0:12:34:56:78:9A");`
     passing the device's MAC address as a `String`. In this case, the BleUART will attempt to find (i.e. scan for) and connect to the device automatically. **Skip** to step 11.
 5. Otherwise, call:
    `bleUart.startScanning();`
    You can pass the scan timeout in milliseconds as an `int`, otherwise the default timeout of 5000 (5 seconds) is used. 
 6. Every time a device is found, BleUART will call the method
    `void bleUARTDeviceDiscovered(String name, String address);`
    which you may implement in your sketch.
 7. When scanning is finished, BleUART will call the method
    `void bleUARTScanningFinished();`
    which you may implement in your sketch.
 8. You can also explicitly stop scanning by calling `bleUart.stopScanning()`. Scanning will also be stopped if you call `bleUart.connectTo(...)`.
 9. You can get an `ArrayList` of devices (name and address) with:
    `ArrayList<BLEDeviceSimple> knownDevices = bleUart.getDeviceList();` 
    You can get the name and address of a `BLEDeviceSimple` object using `getName()` or `getAddress()`.
 10. Connect to a known device by passing the address or the `BLEDeviceSimple` object:
     bleUart.connectTo( ... );
  11. On a successful connection, BleUART will call the method
      `void bleUARTConnected();`
      which you may implement in your sketch.
  12. If the connection fails (or later, if the device is disconnected) , BleUART will call the method
      `void bleUARTDisconnected();`
      which you may implement in your sketch.
  13. To send a message via the UART, use:
      `bleUart.sendMessage("Hello World");`
      The BleUART is set-up to allow messages of up to 512 bytes (that's 512 "simple" characters). Everything else will be truncated. 
  14. When a message is received, BleUART will call the method
      `bleUARTMessageReceived(String message);`
      which you may implement in your sketch. **Avoid doing complicated logic here**. It's best to store the message in another variable and process it during the `draw()` loop.
  15. When cleaning up - for instance, on `stop()` - dispose of the BleUART by calling
      `bleUart.dispose();`
