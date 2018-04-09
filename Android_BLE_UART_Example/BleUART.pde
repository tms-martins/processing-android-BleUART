import java.lang.reflect.Method;
import java.lang.reflect.InvocationTargetException;

import java.util.List;
import java.util.Map;
import java.util.Timer;
import java.util.TimerTask;
import java.util.UUID;

import android.content.Context;
import android.content.pm.PackageManager;

import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothManager;
import android.bluetooth.le.BluetoothLeScanner;
import android.bluetooth.le.ScanFilter;
import android.bluetooth.le.ScanSettings;
import android.bluetooth.le.ScanCallback;
import android.bluetooth.le.ScanResult;
import android.bluetooth.BluetoothProfile;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothGatt;
import android.bluetooth.BluetoothGattCallback;
import android.bluetooth.BluetoothGattCharacteristic;
import android.bluetooth.BluetoothGattDescriptor;
import android.bluetooth.BluetoothGattService;


// Utility class for basic information about a BT device: name and MAC address
class BLEDeviceSimple {
  protected String name;
  protected String address;
  
  BLEDeviceSimple() {
    this.name = "unnamed";
    this.address = "none";
  }
  
  BLEDeviceSimple(String name, String address) {
    this.name = name;
    this.address = address;
  }
  
  String getName() { return this.name; }
  
  String getAddress() { return this.address; }
}


class BleUART {
  
  static final String UUID_SERVICE_UART = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E";
  static final String UUID_CHARACT_TX   = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E";
  static final String UUID_CHARACT_RX   = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E";

  static final int DEFAULT_SCAN_TIMEOUT = 5000;
  
  protected PApplet parent;
  protected BluetoothManager    bluetoothManager;
  protected BluetoothAdapter    bluetoothAdapter;
  protected BluetoothLeScanner  bleScanner;
  protected BleUARTScanCallback scanCallback;
  protected BleUARTGatt         uartGatt;
  
  protected boolean isInit           = false;
  protected boolean isScanning       = false;
  protected boolean isShowAllDevices = true;
  
  protected static final String methodNameDeviceDiscovered = "bleUARTDeviceDiscovered";
  protected static final String methodNameScanningFinished = "bleUARTScanningFinished";
  protected static final String methodNameConnected        = "bleUARTConnected";
  protected static final String methodNameDisconnected     = "bleUARTDisconnected";
  protected static final String methodNameMessageReceived  = "bleUARTMessageReceived";
  
  protected Method parentMethodDeviceDiscovered;
  protected Method parentMethodScanningFinished;
  protected Method parentMethodConnected;
  protected Method parentMethodDisconnected;
  protected Method parentMethodMessageReceived;

  protected Timer stopScanTimer;

  //protected BLEDeviceMap deviceMap;
  protected HashMap<String, BluetoothDevice> deviceMap;
  
  protected String targetMacAddress = null;

  protected boolean verbose = false;

  BleUART (PApplet parent) {
    this.parent  = parent;
    
    deviceMap    = new HashMap<String, BluetoothDevice>(); //new BLEDeviceMap();
    scanCallback = new BleUARTScanCallback();
    uartGatt     = new BleUARTGatt(parent);
    
    getParentCallbacks();
  }

  void init() {
    bluetoothManager = (BluetoothManager) parent.getContext().getSystemService(Context.BLUETOOTH_SERVICE);
    bluetoothAdapter = bluetoothManager.getAdapter();
    bleScanner       = bluetoothAdapter.getBluetoothLeScanner();

    isInit = true;
    printlnDebug("BleUART.init(): initialized");
  }
  
  int dispose() {
    if (isScanning) stopScanning();
    if (uartGatt.state >= BleUARTGatt.CONNECTING) disconnect();
    return 0;
  }
  
  boolean isInitialized() {
    return isInit;
  }
  
  void setVerbose(boolean value) {
    verbose = value;
  }
  
  boolean isScanning() {
    return isScanning;
  }
  
  void startScanning() {
    startScanning(DEFAULT_SCAN_TIMEOUT);
  }
  
  void startScanning(int scanInterval) {
    if (!isInit) {
      printlnDebug("BleUART.scan(): BleUART isn't initialized.");
      return;
    }
    
    deviceMap.clear();

    bleScanner.startScan(scanCallback);
    
    setTimerToStopScan(scanInterval);
    isScanning = true;
    printlnDebug("BleUART.startScan(): scanning started.");
  }

  void stopScanning() {
    if (!isInit) {
      printlnDebug("BleUART.scan() ERROR: BleUART isn't initialized.");
      return;
    }
    if (!isScanning) {
      printlnDebug("BleUART.stopScan() scanning was already stopped");
      return;
    }
    
    bleScanner.flushPendingScanResults(scanCallback);
    bleScanner.stopScan(scanCallback);
    isScanning = false;
    printlnDebug("BleUART.stopScan(): scanning stopped");
    
    // if there is a target mac, the scan wasn't explicitly started by the developer
    // since the developed didn't explicitly start the scan, we return here 
    // and don't trigger the bleUARTScanningFinished method
    if (targetMacAddress != null) return;
    
    try {
      if (parentMethodScanningFinished != null) 
        parentMethodScanningFinished.invoke(parent);
    } catch (InvocationTargetException ite) {
      printlnDebug("BleUARTGatt.onCharacteristicChanged() ERROR: InvocationTargetException for method " + parentMethodScanningFinished.getName() + " on parent");
    } catch (IllegalAccessException iae) {
      printlnDebug("BleUARTGatt.onCharacteristicChanged() ERROR: IllegalAccessException for method " + parentMethodScanningFinished.getName() + " on parent");
    }
  }
  
  int getResultCount() {
    return deviceMap.size();
  }
  
  ArrayList<BLEDeviceSimple> getDeviceList() {
    ArrayList<BLEDeviceSimple> result = new ArrayList<BLEDeviceSimple>();
    for (Map.Entry<String, BluetoothDevice> entry : deviceMap.entrySet()) {
      BluetoothDevice device = entry.getValue();
      if (device.getName() != null) {
        result.add(new BLEDeviceSimple(device.getName(), device.getAddress()));
      }
    }
    return result;
  }
  
  BLEDeviceSimple getScanResult(int i) {
    BluetoothDevice device = getMapDeviceAtIndex(i);
    if (device == null) return null;
    return new BLEDeviceSimple(device.getName(), device.getAddress());
  }
  
  protected BluetoothDevice getMapDeviceAtIndex(int index) {
    int i = 0;
    for (Map.Entry<String, BluetoothDevice> entry : deviceMap.entrySet()) {
      if (index == i)
        return entry.getValue();
      i++;
    }
    return null;
  }
  
  BluetoothDevice getBluetoothDeviceByAddress (String address) {
    return deviceMap.get(address);
  }
  
  BluetoothDevice getBluetoothDeviceByName (String name) {
    for (Map.Entry<String, BluetoothDevice> entry : deviceMap.entrySet()) {
      BluetoothDevice device = entry.getValue();
      if (device.getName().equals(name))
        return device;
    }
    return null;
  }
  
  void connectTo (BLEDeviceSimple device) {
    printlnDebug("BleUART.connectTo() " + device.getName() + " " + device.getAddress());
    connectTo(device.getAddress());
  }

  void connectTo(String deviceAddress) {
    if (uartGatt.state == BleUARTGatt.READY) {
      printlnDebug("BleUART.connectTo(): WARNING gatt is already connected");
      return;
    }
    else if (uartGatt.state >= BleUARTGatt.CONNECTING) {
      printlnDebug("BleUART.connectTo(): WARNING gatt is already connecting");
      return;
    }
    
    BluetoothDevice device = deviceMap.get(deviceAddress);
    if (device == null) {
      printlnDebug("BleUART.connectTo(): device address <" + deviceAddress + "> not in map; starting scan");
      startScanning(DEFAULT_SCAN_TIMEOUT);
      targetMacAddress = deviceAddress;
      return;
    }
    
    printlnDebug("BleUART.connectTo(): connecting to <" + deviceAddress + ">");
    uartGatt.init(device);
    return;      
  }
  
  void disconnect() {
    if (uartGatt.state >= BleUARTGatt.CONNECTING) {
      printlnDebug("BleUARTGatt.disconnect(): disconnecting");
      uartGatt.gatt.disconnect();
    } else {
      printlnDebug("BleUARTGatt.disconnect(): already disconnected");
    }
  }
  
  boolean isConnecting() {
    return uartGatt.state == BleUARTGatt.CONNECTING
        || uartGatt.state == BleUARTGatt.CONFIGURING;
  }
  
  boolean isConnected() {
    return uartGatt.state == BleUARTGatt.READY;
  }
  
  BLEDeviceSimple getDevice() {
    BluetoothDevice device = uartGatt.bluetoothDevice;
    if (device == null) return null;
    return new BLEDeviceSimple(device.getName(), device.getAddress());
  }  
  
  protected void handleScanResult(BluetoothDevice device) {
    if (device.getName() != null) {
      deviceMap.put(device.getAddress(), device);
      try {
        if (parentMethodDeviceDiscovered != null) 
          parentMethodDeviceDiscovered.invoke(parent, device.getName(), device.getAddress());
      } catch (InvocationTargetException ite) {
        printlnDebug("BleUARTGatt.onCharacteristicChanged() ERROR: InvocationTargetException for method " + parentMethodDeviceDiscovered.getName() + " on parent");
      } catch (IllegalAccessException iae) {
        printlnDebug("BleUARTGatt.onCharacteristicChanged() ERROR: IllegalAccessException for method " + parentMethodDeviceDiscovered.getName() + " on parent");
      }
      
      if (targetMacAddress != null && targetMacAddress.equalsIgnoreCase(device.getAddress())) {
        printlnDebug("BleUARTScanCallback.handleScanResult(): found the target, stopping scan and connecting");
        stopScanning();
        targetMacAddress = null;
        connectTo(device.getAddress());
      }
    }
  }
  
  protected void setTimerToStopScan(int scanInterval) {
    stopScanTimer = new Timer();
    stopScanTimer.schedule(new TimerTask() {
      @Override
      public void run() {
        printlnDebug("BleUART.setTimerToStopScan(): timer triggered to stop scan");
        stopScanning();
      }
    }, scanInterval);
  }
  
  boolean sendMessage(String message) {
    return uartGatt.sendMessage(message);
  }
  
  void getParentCallbacks() {
    Class<?> parentClass = parent.getClass();
    try {
      parentMethodDeviceDiscovered = parentClass.getMethod(methodNameDeviceDiscovered, new Class[] { String.class, String.class });
    } catch (NoSuchMethodException nsme) {
      printlnDebug("BleUART.getParentCallbacks() no public " + methodNameDeviceDiscovered + "() method in the class " + parentClass.getName());
    }
    try {
      parentMethodScanningFinished = parentClass.getMethod(methodNameScanningFinished, new Class[] {});
    } catch (NoSuchMethodException nsme) {
      printlnDebug("BleUART.getParentCallbacks() no public " + methodNameScanningFinished + "() method in the class " + parentClass.getName());
    }
    try {
      parentMethodConnected = parentClass.getMethod(methodNameConnected, new Class[] {});
    } catch (NoSuchMethodException nsme) {
      printlnDebug("BleUART.getParentCallbacks() no public " + methodNameConnected + "() method in the class " + parentClass.getName());
    }
    try {
      parentMethodDisconnected = parentClass.getMethod(methodNameDisconnected, new Class[] {});
    } catch (NoSuchMethodException nsme) {
      printlnDebug("BleUART.getParentCallbacks() no public " + methodNameDisconnected + "() method in the class " + parentClass.getName());
    }
    try {
      parentMethodMessageReceived = parentClass.getMethod(methodNameMessageReceived, new Class[] { String.class });
    } catch (NoSuchMethodException nsme) {
      printlnDebug("BleUART.getParentCallbacks() no public " + methodNameMessageReceived + "() method in the class " + parentClass.getName());
    }
  }
  
  String deviceMapToFormattedString() {
    String result = "";
    for (Map.Entry<String, BluetoothDevice> entry : deviceMap.entrySet()) {
      BluetoothDevice device = entry.getValue();
      result += "<" + device.getName() + "> : <" + device.getAddress() + "> type " + device.getType() + "\n";
    }
    return result;
  }
  
  void printlnDebug(String message) {
    if (verbose) PApplet.println(message);
  }
  
  
  ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  // SCAN CALLBACKS //////////////////////////////////////////////////////////////////////////////////////////////////
  ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  
  
  class BleUARTScanCallback extends ScanCallback {
    
    @Override
      void onScanResult(int callbackType, ScanResult result) {
      BluetoothDevice device = result.getDevice();
      printlnDebug("BleUARTScanCallback.onScanResult(): <" + device.getName() + "> : <" + device.getAddress() + "> type " + device.getType());
      handleScanResult(device);
    }
    
    @Override
      void onBatchScanResults(List<ScanResult> results) {
      printlnDebug("BleUARTScanCallback.onBatchScanResults(): got " + results.size() + " results");
      for (int i = 0; i <results.size(); i++) {
        BluetoothDevice device = results.get(i).getDevice();
        printlnDebug("  [" + i + "]: <" + device.getName() + "> : <" + device.getAddress() + "> type " + device.getType() );
        handleScanResult(device);
      }
    }
    
    @Override
      void onScanFailed(int errorCode) {
      printlnDebug("BleUARTScanCallback.onScanFailed(): ERROR code " + errorCode);
    }
  };


  ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  // GATT OBJECT AND CALLBACKS ///////////////////////////////////////////////////////////////////////////////////////
  ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


  class BleUARTGatt extends BluetoothGattCallback {
    
    static final short DISCONNECTED = 0;
    static final short CONNECTING   = 1;
    static final short CONFIGURING  = 2;
    static final short READY        = 3;

    protected PApplet parent;
    
    protected BluetoothGatt gatt;
    protected BluetoothDevice bluetoothDevice;
    protected BluetoothGattService gattService;

    protected BluetoothGattCharacteristic charactRx;
    protected BluetoothGattCharacteristic charactTx;
    
    protected BluetoothGattDescriptor descriptorTxClientCharactConfig;
    
    protected short   state        = DISCONNECTED;
    protected boolean isGattBusy   = false;

    BleUARTGatt (PApplet parent) {
      super();
      this.parent = parent;
    }

    void init(BluetoothDevice device) {
      bluetoothDevice = device;
      //isConnecting = true;
      state = CONNECTING;
      gatt = device.connectGatt(parent.getContext(), true, this);
    }
    
    boolean sendMessage(String message) {
      if (state != READY) {
        printlnDebug("BleUART.sendMessage() ERROR: gatt isn't ready (still connecting or retrieving characteristics)");
        return false;
      }
      printlnDebug("BleUART.sendMessage()");
      printlnDebug("  <" + message + ">");
      synchronized (this) {
        if (isGattBusy) {
          printlnDebug("BleUARTGatt.sendClientCommand() WARNING: gatt is still busy sending previous command");
          return false;
        }
        isGattBusy = true;
        printlnDebug("BleUARTGatt.sendClientCommand() writing");
        charactRx.setValue(message); 
        gatt.writeCharacteristic(charactRx);
      }
      return true;
    }

    @Override
    void onCharacteristicChanged(BluetoothGatt gatt, BluetoothGattCharacteristic characteristic) {
      if (characteristic == charactTx) {
        String message = charactTx.getStringValue(0);
        printlnDebug("BleUARTGatt.onCharacteristicChanged() - received message <" + message + ">");
        
        try {
          if (parentMethodMessageReceived != null) 
            parentMethodMessageReceived.invoke(parent, message);
        } catch (InvocationTargetException ite) {
          printlnDebug("BleUARTGatt.onCharacteristicChanged() ERROR: InvocationTargetException for method " + parentMethodMessageReceived.getName() + " on parent");
        } catch (IllegalAccessException iae) {
          printlnDebug("BleUARTGatt.onCharacteristicChanged() ERROR: IllegalAccessException for method " + parentMethodMessageReceived.getName() + " on parent");
        }
      } 
    }

    @Override
    void onCharacteristicRead(BluetoothGatt gatt, BluetoothGattCharacteristic characteristic, int status) {
      printlnDebug("BleUARTGatt.onCharacteristicRead()");
    }

    @Override
    void onCharacteristicWrite(BluetoothGatt gatt, BluetoothGattCharacteristic characteristic, int status) {
      if (characteristic == charactRx) {
        if (status == BluetoothGatt.GATT_SUCCESS) {
          printlnDebug("BleUARTGatt.onCharacteristicWrite() message successfully sent");
        }
        else {
          printlnDebug("BleUARTGatt.onCharacteristicWrite() ERROR sending message, status: " + status);
        }
      }
      isGattBusy = false;
    }

    @Override
    void onConnectionStateChange(BluetoothGatt gatt, int status, int newState) {
      //isConnecting = false;
      if (status == BluetoothGatt.GATT_SUCCESS) {
        if (newState == BluetoothProfile.STATE_CONNECTED) {
          printlnDebug("BleUARTGatt.onConnectionStateChange(): connected");
          if (state < CONFIGURING) {
            this.gatt   = gatt;
            //isConnected = true;
            //isReady     = false;
            state = CONFIGURING;
            bluetoothDevice = gatt.getDevice();
            gatt.requestMtu(517);
          }
        }
        else {
          printlnDebug("BleUARTGatt.onConnectionStateChange(): disconnected");
          //isConnected = false;
          //isReady     = false;
          state = DISCONNECTED;
          isGattBusy  = false;
        }
      } else {
        String currentState = "";
        if (newState == BluetoothProfile.STATE_CONNECTED) {
          currentState = "connected";
          //isConnected  = true;
          state = READY;
          isGattBusy   = false;
          }
        else {
          currentState = "disconnected";
          //isConnected  = false;
          //isReady      = false;
          state = DISCONNECTED;
          isGattBusy   = false;
        }
        printlnDebug("BleUARTGatt.onConnectionStateChange() ERROR: failed to change connection state; current statate is: " + currentState);
      }
      
      if (state == DISCONNECTED) {
        try {
          if (parentMethodDisconnected != null) 
              parentMethodDisconnected.invoke(parent);
        } catch (InvocationTargetException ite) {
          printlnDebug("BleUARTGatt.onCharacteristicChanged() ERROR: InvocationTargetException for method " + parentMethodDisconnected.getName() + " on parent");
        } catch (IllegalAccessException iae) {
          printlnDebug("BleUARTGatt.onCharacteristicChanged() ERROR: IllegalAccessException for method " + parentMethodDisconnected.getName() + " on parent");
        }
      }
    }

    @Override
    void onDescriptorRead(BluetoothGatt gatt, BluetoothGattDescriptor descriptor, int status) {
      printlnDebug("BleUARTGatt onDescriptorRead");
    }

    @Override
    void onDescriptorWrite(BluetoothGatt gatt, BluetoothGattDescriptor descriptor, int status) {
      if (descriptor == descriptorTxClientCharactConfig) {
        if (status == BluetoothGatt.GATT_SUCCESS) {
          printlnDebug("BleUARTGatt.onDescriptorWrite() success writing characteristic config for Tx");
          state = READY;
      
          try {
            if (parentMethodConnected != null) 
                parentMethodConnected.invoke(parent);
          } catch (InvocationTargetException ite) {
            printlnDebug("BleUARTGatt.onCharacteristicChanged() ERROR: InvocationTargetException for method " + parentMethodConnected.getName() + " on parent");
          } catch (IllegalAccessException iae) {
            printlnDebug("BleUARTGatt.onCharacteristicChanged() ERROR: IllegalAccessException for method " + parentMethodConnected.getName() + " on parent");
          }
        }
        else {
          printlnDebug("BleUARTGatt.onDescriptorWrite() ERROR writing characteristic config for Tx");
        }
      }
      else {
        printlnDebug("BleUARTGatt.onDescriptorWrite() status " + status);
      }
    }

    @Override
    void onMtuChanged(BluetoothGatt gatt, int mtu, int status) {
      if (status == BluetoothGatt.GATT_SUCCESS) {
        printlnDebug("BleUARTGatt.onMtuChanged() MTU successfully changed to " + mtu);
      }
      else {
        printlnDebug("BleUARTGatt.onMtuChanged() WARNING MTU change failed, current mtu " + mtu);
      }
      gatt.discoverServices();
    }

    @Override
    void onPhyRead(BluetoothGatt gatt, int txPhy, int rxPhy, int status) {
      printlnDebug("BleUARTGatt onPhyRead");
    }

    @Override
    void onPhyUpdate(BluetoothGatt gatt, int txPhy, int rxPhy, int status) {
      printlnDebug("BleUARTGatt onPhyUpdate");
    }

    @Override
    void onReadRemoteRssi(BluetoothGatt gatt, int rssi, int status) {
      printlnDebug("BleUARTGatt onReadRemoteRssi");
    }

    @Override
    void onReliableWriteCompleted(BluetoothGatt gatt, int status) {
      printlnDebug("BleUARTGatt onReliableWriteCompleted");
    }

    @Override
    void onServicesDiscovered(BluetoothGatt gatt, int status) {
      if (status == BluetoothGatt.GATT_SUCCESS) {
        printlnDebug("BleUARTGatt.onServicesDiscovered(): success");
        gattService = gatt.getService(UUID.fromString(UUID_SERVICE_UART));
        if (gattService != null) {
          printlnDebug("BleUARTGatt.onServicesDiscovered(): got UART service");

          charactRx = gattService.getCharacteristic(UUID.fromString(UUID_CHARACT_RX));
          if (charactRx != null) {
            printlnDebug("BleUARTGatt got characteristic Rx");
          } else {
            printlnDebug("BleUARTGatt ERROR getting characteristic Rx");
          }
          
          charactTx = gattService.getCharacteristic(UUID.fromString(UUID_CHARACT_TX));
          if (charactTx != null) {
            printlnDebug("BleUARTGatt got characteristic Tx");
            gatt.setCharacteristicNotification(charactTx, true);
            
            //Enable remote notifications 
            printlnDebug("BleUARTGatt getting descriptor");
            descriptorTxClientCharactConfig = charactTx.getDescriptor(UUID.fromString("00002902-0000-1000-8000-00805f9b34fb"));//("0x2902")); 
            if (descriptorTxClientCharactConfig == null) {
              printlnDebug("BleUARTGatt ERROR descriptor for Tx is null");
            }
            else {
              printlnDebug("BleUARTGatt setting descriptor");
              boolean result = descriptorTxClientCharactConfig.setValue(BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE);
              printlnDebug("BleUARTGatt set descriptor value: " + result);
              printlnDebug("BleUARTGatt writing descriptor");
              result = gatt.writeDescriptor(descriptorTxClientCharactConfig);
              printlnDebug("BleUARTGatt wrote descriptor: " + result);
            }
          } else {
            printlnDebug("BleUARTGatt ERROR getting characteristic Tx");
          }
          
        } else {
          printlnDebug("BleUARTGatt.onServicesDiscovered(): ERROR getting UART service");
          return;
        }
      }
      else {
        printlnDebug("BleUARTGatt.onServicesDiscovered(): ERROR failed discovering services");
      }
    }
  }
  
}