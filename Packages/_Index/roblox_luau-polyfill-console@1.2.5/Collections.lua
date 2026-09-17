local REQUIRED_MODULE = require(script.Parent.Parent["roblox_luau-polyfill-collections@1.2.5"]["luau-polyfill-collections"])
export type Array<T> = REQUIRED_MODULE.Array<T>
export type Map<T, V> = REQUIRED_MODULE.Map<T, V>
export type Object = REQUIRED_MODULE.Object 
export type Set<T> = REQUIRED_MODULE.Set<T>
export type WeakMap<T, V> = REQUIRED_MODULE.WeakMap<T, V>
return REQUIRED_MODULE
