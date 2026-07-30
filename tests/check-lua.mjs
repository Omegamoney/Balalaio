import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import luaparse from "luaparse";

const currentDirectory = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(currentDirectory, "..");
const modulePath = path.join(
  repositoryRoot,
  "Balalaio",
  "balalaio.lua",
);
const source = fs.readFileSync(modulePath, "utf8");

const ast = luaparse.parse(source, {
  comments: true,
  locations: true,
  luaVersion: "5.1",
  scope: true,
});

assert.equal(ast.type, "Chunk");
assert.ok(ast.body.length > 0, "Lua module must not be empty");

for (const callback of [
  "balalaio_open_menu",
  "balalaio_adjust",
  "balalaio_add_joker",
  "balalaio_remove_joker",
  "balalaio_adjust_modifier",
]) {
  assert.match(source, new RegExp(`G\\.FUNCS\\.${callback}\\s*=`));
}

for (const runtimePath of [
  "G.GAME.current_round.hands_left",
  "G.GAME.round_resets.hands",
  "G.GAME.current_round.discards_left",
  "G.GAME.round_resets.discards",
  "G.jokers.config.card_limit",
  "G.GAME.dollars",
  "G.consumeables.config.card_limit",
]) {
  assert.ok(source.includes(runtimePath), `Missing runtime mapping: ${runtimePath}`);
}

console.log(`Lua 5.1 parse passed (${ast.body.length} top-level statements).`);
