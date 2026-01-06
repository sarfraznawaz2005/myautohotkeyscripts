#Requires AutoHotkey v2.0+
#SingleInstance Force

; Control + Backtick

; Hotkey to trigger the DPI change sequence
^`::
{
	fixMyDPI()    
    return
}

fixMyDPI()
{
    ; Get the device path of the monitor where the mouse is currently located
    monitorPath := getCurrentDisplayPathByMouse()

	/*
	"dpi_recommended",-1,
	"dpi_100",0,
	"dpi_125",1,
	"dpi_150",2,
	"dpi_175",3,
	"dpi_200",4,
	"dpi_225",5,
	"dpi_250",6,
	"dpi_300",7,
	"dpi_350",8,
	"dpi_400",9,
	"dpi_450",10,
	"dpi_500",11	
	*/

    setDPI(monitorPath, 4)
    Sleep 1000
    setDPI(monitorPath, -1)
}

getCurrentDisplayPathByMouse()
{
	static DisplayPath := ""
	
	if (DisplayPath == "")
	{
		DisplayPath := Map()
		for k, dsp in GetEnumDisplays()
		{
			DisplayPath[dsp.Name] := dsp.Path
		}
	}

	CoordMode("Mouse","Screen")
	MouseGetPos(&mx,&my)
	
	Loop MonitorGetCount()
	{
		MonitorGet(a_index, &Left, &Top, &Right, &Bottom)
		if (Left <= mx && mx <= Right && Top <= my && my <= Bottom)
			Return DisplayPath[MonitorGetName(a_index)]
	}
	
	Return 1
}

; by FuPeiJiang
setDPI(monitorDevicePath, dpi_enum_value) {
	static QDC_ONLY_ACTIVE_PATHS := 0x00000002

	DllCall("GetDisplayConfigBufferSizes", "Uint", QDC_ONLY_ACTIVE_PATHS, "Uint*",&pathsCount:=0, "Uint*",&modesCount:=0)
	DISPLAYCONFIG_PATH_INFO_arr:=Buffer(72*pathsCount)
	DISPLAYCONFIG_MODE_INFO_arr:=Buffer(64*modesCount)
	DllCall("QueryDisplayConfig",
			"Uint" , QDC_ONLY_ACTIVE_PATHS,
			"Uint*", &pathsCount,
			"Ptr"  , DISPLAYCONFIG_PATH_INFO_arr,
			"Uint*", &modesCount,
			"Ptr"  , DISPLAYCONFIG_MODE_INFO_arr,
			"Ptr"  ,0)

	i_:=0
	end:=DISPLAYCONFIG_PATH_INFO_arr.Size
	DISPLAYCONFIG_TARGET_DEVICE_NAME:=Buffer(420)
	NumPut("Int",2,DISPLAYCONFIG_TARGET_DEVICE_NAME,0) ;2=DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_NAME
	NumPut("Uint",DISPLAYCONFIG_TARGET_DEVICE_NAME.Size,DISPLAYCONFIG_TARGET_DEVICE_NAME,4)
	while (i_ < end) {
		adapterID:=NumGet(DISPLAYCONFIG_PATH_INFO_arr, i_+0, "Uint64")
		sourceID:=NumGet(DISPLAYCONFIG_PATH_INFO_arr, i_+8, "Uint")
		targetID:=NumGet(DISPLAYCONFIG_PATH_INFO_arr, i_+28, "Uint")

		NumPut("Uint64",adapterID,DISPLAYCONFIG_TARGET_DEVICE_NAME,8)
		NumPut("Uint",targetID,DISPLAYCONFIG_TARGET_DEVICE_NAME,16)
		DllCall("DisplayConfigGetDeviceInfo", "Ptr",DISPLAYCONFIG_TARGET_DEVICE_NAME)
		temp_monitorDevicePath:=StrGet(DISPLAYCONFIG_TARGET_DEVICE_NAME.Ptr + 164, "UTF-16")

		if (temp_monitorDevicePath==monitorDevicePath) {

			DISPLAYCONFIG_SOURCE_DPI_SCALE_GET:=Buffer(32)
			NumPut("Int",-3,DISPLAYCONFIG_SOURCE_DPI_SCALE_GET,0) ;-3=DISPLAYCONFIG_DEVICE_INFO_GET_DPI_SCALE
			NumPut("Uint",DISPLAYCONFIG_SOURCE_DPI_SCALE_GET.Size,DISPLAYCONFIG_SOURCE_DPI_SCALE_GET,4)
			NumPut("Uint64",adapterID,DISPLAYCONFIG_SOURCE_DPI_SCALE_GET,8)
			NumPut("Uint",sourceID,DISPLAYCONFIG_SOURCE_DPI_SCALE_GET,16)
			DllCall("DisplayConfigGetDeviceInfo", "Ptr",DISPLAYCONFIG_SOURCE_DPI_SCALE_GET)
			minScaleRel:=NumGet(DISPLAYCONFIG_SOURCE_DPI_SCALE_GET, 20, "Int")
			recommendedDpi:=Abs(minScaleRel)
			dpiRelativeVal:=0
			if (dpi_enum_value!==-1) {
				dpiRelativeVal:=dpi_enum_value - recommendedDpi
			}


			DISPLAYCONFIG_SOURCE_DPI_SCALE_SET:=Buffer(24)
			NumPut("Int",-4,DISPLAYCONFIG_SOURCE_DPI_SCALE_SET,0) ;-4=DISPLAYCONFIG_DEVICE_INFO_SET_DPI_SCALE
			NumPut("Uint",DISPLAYCONFIG_SOURCE_DPI_SCALE_SET.Size,DISPLAYCONFIG_SOURCE_DPI_SCALE_SET,4)
			NumPut("Uint64",adapterID,DISPLAYCONFIG_SOURCE_DPI_SCALE_SET,8)
			NumPut("Uint",sourceID,DISPLAYCONFIG_SOURCE_DPI_SCALE_SET,16)
			NumPut("Int",dpiRelativeVal,DISPLAYCONFIG_SOURCE_DPI_SCALE_SET,20)
			DllCall("DisplayConfigSetDeviceInfo", "Ptr",DISPLAYCONFIG_SOURCE_DPI_SCALE_SET)

			break
		}


		i_+=72
	}
}

GetEnumDisplays()
{
	Displays := []
	
	Loop MonitorGetCount()
	{
		Name := MonitorGetName(a_index)
		Display := EnumDisplayDevices(a_index, 1)
		if InStr(Display["DeviceName"],Name)
			Displays.Push({Name:Name,Path:Display["DeviceID"]})

	}
	
	return Displays
}


EnumDisplayDevices(iDevNum, dwFlags:=0)    {
	Static   EDD_GET_DEVICE_INTERFACE_NAME := 0x00000001
			,byteCount              := 4+4+((32+128+128+128)*2)
			,offset_cb              := 0
			,offset_DeviceName      := 4                            ,length_DeviceName      := 32
			,offset_DeviceString    := 4+(32*2)                     ,length_DeviceString    := 128
			,offset_StateFlags      := 4+((32+128)*2)
			,offset_DeviceID        := 4+4+((32+128)*2)             ,length_DeviceID        := 128
			,offset_DeviceKey       := 4+4+((32+128+128)*2)         ,length_DeviceKey       := 128

	DISPLAY_DEVICEA:=""
	if (iDevNum~="\D" || (dwFlags!=0 && dwFlags!=EDD_GET_DEVICE_INTERFACE_NAME))
		return false
	lpDisplayDevice:=Buffer(byteCount,0)            ,Numput("UInt",byteCount,lpDisplayDevice,offset_cb)
	if !DllCall("EnumDisplayDevices", "Ptr",0, "UInt",iDevNum, "Ptr",lpDisplayDevice.Ptr, "UInt",0)
		return false
	if (dwFlags==EDD_GET_DEVICE_INTERFACE_NAME)    {
		DeviceName:=MonitorGetName(iDevNum)
		lpDisplayDevice.__New(byteCount,0)          ,Numput("UInt",byteCount,lpDisplayDevice,offset_cb)
		lpDevice:=Buffer(length_DeviceName*2,0)     ,StrPut(DeviceName, lpDevice,length_DeviceName)
		DllCall("EnumDisplayDevices", "Ptr",lpDevice.Ptr, "UInt",0, "Ptr",lpDisplayDevice.Ptr, "UInt",dwFlags)
	}

	DISPLAY_DEVICEA:=Map("cb",0,"DeviceName","","DeviceString","","StateFlags",0,"DeviceID","","DeviceKey","")
	For k in DISPLAY_DEVICEA {
		Switch k
		{
			case "cb","StateFlags": DISPLAY_DEVICEA[k]:=NumGet(lpDisplayDevice, offset_%k%,"UInt")
			default:                DISPLAY_DEVICEA[k]:=StrGet(lpDisplayDevice.Ptr+offset_%k%, length_%k%)
		}
	}
	return DISPLAY_DEVICEA
}