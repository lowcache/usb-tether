## Android usb data tether 
### No hotspot subscription necessary

### CURRENTLY ONLY AVAILABLE FOR LINUX

Share your 4G or 5G data connection with your lapop or computer without a paid hotspot subscription. This works through ADB comnmnands and does not require a rooted phone.
- No root
- adb commands
- no hotspot subscription


##### Currently only tested on Verizon w/ Samsung Galaxy S23 ultra

## Dependencies
- ADB
- ip


### INSTALL ADB 
#### Arch Linux
``
sudo pacman -S android-tools
``

#### Ubuntu
``
sudo apt install -y android-tools0-adb
``


## Installation a& Usage

```bash
git clone https://github.com/lowcache/usb-tether.git
cd usb-tether
chmod +x mktether.sh
# make sure phone is plugged in and authorization is given
./mktether.sh
```

## TODO
- Convert to powershell for Windows compatiblity
- iOS & Mac compatibility
- error handling
- GUI
- Convert to more suitable language for full executable binary

