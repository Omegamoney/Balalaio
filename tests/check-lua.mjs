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
  "balalaio_adjust_extra",
  "balalaio_toggle_deck_selection_mode",
  "balalaio_toggle_deck_card",
  "balalaio_select_deck_cards",
  "balalaio_open_deck_bulk",
  "balalaio_change_deck_bulk_scope",
  "balalaio_change_deck_bulk_page",
  "balalaio_apply_deck_bulk",
  "balalaio_remove_deck_bulk",
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
  "G.hand.config.card_limit",
  "G.hand.config.highlighted_limit",
  "G.GAME.starting_params",
  "G.GAME.round_resets.ante",
  "G.GAME.round",
  "G.GAME.win_ante",
  "G.GAME.shop.joker_max",
  "G.GAME.round_resets.reroll_cost",
  "G.GAME.interest_amount",
  "G.GAME.interest_cap",
  "G.GAME.probabilities.normal",
]) {
  assert.ok(source.includes(runtimePath), `Missing runtime mapping: ${runtimePath}`);
}

assert.match(source, /tab_button\(\s*["']EXTRAS["']\s*,\s*["']extras["']/u);
assert.match(source, /function\s+Balalaio\.create_extras\s*\(/u);

for (const nativeMutation of [
  "G.hand:change_size",
  "SMODS.change_play_limit",
  "SMODS.change_discard_limit",
  "change_shop_size",
  "calculate_reroll_cost",
  "SMODS.change_base",
  "card:set_ability",
  "card:set_edition",
  "card:set_seal",
  "SMODS.calculate_context",
]) {
  assert.ok(
    source.includes(nativeMutation),
    `Missing native mutation path: ${nativeMutation}`,
  );
}

console.log(`Lua 5.1 parse passed (${ast.body.length} top-level statements).`);
