import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import luaparse from "luaparse";

const currentDirectory = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(currentDirectory, "..");
const modDirectory = path.join(repositoryRoot, "Balalaio");
const metadataPath = path.join(modDirectory, "Balalaio.json");
const metadata = JSON.parse(fs.readFileSync(metadataPath, "utf8"));

assert.deepEqual(
  fs.readdirSync(modDirectory).sort(),
  ["Balalaio.json", "balalaio.lua"],
  "The install-ready mod directory should contain only Steamodded files.",
);
assert.equal(metadata.id, "Balalaio");
assert.equal(metadata.prefix, "balalaio");
assert.equal(metadata.main_file, "balalaio.lua");
assert.match(metadata.version, /^\d+\.\d+\.\d+$/u);
assert.ok(Array.isArray(metadata.author) && metadata.author.length > 0);
assert.ok(
  metadata.dependencies.includes("Lovely (>=0.9.0)"),
  "Lovely 0.9+ must be declared.",
);
assert.ok(
  metadata.dependencies.some((dependency) =>
    dependency.startsWith("Steamodded"),
  ),
  "Steamodded must be declared.",
);
assert.ok(
  metadata.dependencies.includes("Balatro (==1.0.1o-FULL)"),
  "The tested Balatro revision must be pinned.",
);

const entryPath = path.resolve(modDirectory, metadata.main_file);
assert.equal(
  path.dirname(entryPath),
  modDirectory,
  "main_file must stay inside the mod directory.",
);
const source = fs.readFileSync(entryPath, "utf8");
luaparse.parse(source, { luaVersion: "5.1" });
assert.match(
  source,
  new RegExp(`VERSION\\s*=\\s*["']${metadata.version}["']`, "u"),
  "Lua and metadata versions must match.",
);

console.log(
  `Steamodded package metadata passed (Balalaio ${metadata.version}).`,
);
