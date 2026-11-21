import { readFile } from "node:fs/promises";
import { stripTypeScriptTypes } from "node:module";

// These browser-native modules only import types. Exercise their actual exports
// in an isolated document without loading a second Rive runtime or a test build.
export async function moduleSource(name: "pointer-session" | "playback-session"): Promise<string> {
  return stripTypeScriptTypes(await readFile(new URL(`../src/${name}.ts`, import.meta.url), "utf8"));
}
