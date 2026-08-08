import os

version = "2.0"
windows_path = f"%localappdata%/Roblox/Plugins/MaterialFlip v{version}.rbxmx"
posix_path = f"~/Documents/Roblox/Plugins/MaterialFlip v{version}.rbxmx"

if os.name == "nt":
	os.system(f"rojo build . -o \"{windows_path}\"")
else:
	os.system(f"rojo build . -o \"{posix_path}\"")
