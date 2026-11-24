// A JSON import has wide types: each string is `string`, and each object in an
// array gets the keys of the other objects as optional `undefined` keys. So a
// fixture cannot satisfy a type with string literals. `Json<T>` is the type
// that a JSON import of a `T` gets, so `fixture satisfies Json<T>` checks the
// shape of each sample. The literal values need a check at run time.

type Keys<T> = T extends unknown ? keyof T : never;

export type Json<T, All = T> = T extends string
	? string
	: T extends readonly (infer Item)[]
		? Json<Item>[]
		: T extends object
			? { [K in keyof T]: Json<T[K]> } & { [K in Exclude<Keys<All>, keyof T>]?: undefined }
			: T;

/** The values of a string union, as the keys of an object that names each value once. */
export function values<T extends string>(record: Record<T, true>): Set<string> {
	return new Set(Object.keys(record));
}
