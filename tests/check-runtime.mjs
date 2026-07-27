import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { lua, lauxlib, lualib, to_luastring, to_jsstring } from "fengari";

const currentDirectory = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(currentDirectory, "..");
const moduleSource = fs.readFileSync(
  path.join(repositoryRoot, "src", "balalaio.lua"),
  "utf8",
);
if (/focus_args\s*=\s*\{\s*type\s*=\s*["']none["']\s*\}/u.test(moduleSource)) {
  throw new Error(
    "Interactive Balalaio controls must not opt out of Balatro focus hit-testing.",
  );
}
if (!/instance_type\s*=\s*["']POPUP["']/u.test(moduleSource)) {
  throw new Error(
    "The floating launcher must render after Cards and tutorial overlays.",
  );
}

const state = lauxlib.luaL_newstate();
lualib.luaL_openlibs(state);

function runLua(source, chunkName) {
  const loadStatus = lauxlib.luaL_loadbuffer(
    state,
    to_luastring(source),
    null,
    to_luastring(chunkName),
  );
  if (loadStatus !== lua.LUA_OK) {
    throw new Error(to_jsstring(lua.lua_tostring(state, -1)));
  }
  const callStatus = lua.lua_pcall(state, 0, lua.LUA_MULTRET, 0);
  if (callStatus !== lua.LUA_OK) {
    throw new Error(to_jsstring(lua.lua_tostring(state, -1)));
  }
}

runLua(
  `
local function remove_from_area(card)
    if not card.area then return end
    for index = #card.area.cards, 1, -1 do
        if card.area.cards[index] == card then
            table.remove(card.area.cards, index)
            break
        end
    end
end

local function make_card(kind, area, center)
    local card = {
        area = area,
        added_to_deck = false,
        created_on_pause = true,
        REMOVED = false,
        ability = {
            name = center and center.name or kind,
            set = kind,
            mult = center and center.config and center.config.mult or 0,
            x_mult = 1,
            h_mult = 0,
            h_x_mult = 0,
            h_dollars = 0,
            p_dollars = 0,
            t_mult = 0,
            t_chips = 0,
            h_size = 0,
            d_size = 0,
            extra_value = 0,
            perma_bonus = 0,
            bonus = 0,
            extra = center and center.config and center.config.extra or nil,
        },
        config = {center = center or {name = kind, config = {}}},
    }
    function card:add_to_deck()
        self.added_to_deck = true
        self.add_calls = (self.add_calls or 0) + 1
    end
    function card:remove_from_deck()
        self.added_to_deck = false
        self.remove_calls = (self.remove_calls or 0) + 1
    end
    function card:remove()
        remove_from_area(self)
        self.added_to_deck = false
        self.removed = true
        self.REMOVED = true
    end
    function card:start_materialize() self.materialized = true end
    function card:set_cost() self.cost_updates = (self.cost_updates or 0) + 1 end
    function card:set_rental(enabled)
        self.ability.rental = enabled or nil
        self:set_cost()
    end
    function card:set_edition(edition)
        self.edition = nil
        if edition then
            self.edition = {}
            for key, value in pairs(edition) do self.edition[key] = value end
            if edition.foil then self.edition.type = "foil"; self.edition.chips = 50 end
            if edition.holo then self.edition.type = "holo"; self.edition.mult = 10 end
            if edition.polychrome then
                self.edition.type = "polychrome"
                self.edition.x_mult = 1.5
            end
            if edition.negative then
                self.edition.type = "negative"
                if self.added_to_deck then
                    G.jokers.config.card_limit = G.jokers.config.card_limit + 1
                end
            end
        end
    end
    return card
end

local function make_area(limit)
    local area = {cards = {}, config = {card_limit = limit}}
    function area:emplace(card)
        self.cards[#self.cards + 1] = card
        card.area = self
    end
    return area
end

G = {
    FUNCS = {},
    STAGES = {RUN = 1},
    STAGE = 1,
    SETTINGS = {paused = false},
    GAME = {
        current_round = {hands_left = 2, discards_left = 1},
        round_resets = {hands = 4, discards = 3},
        dollars = 10,
        banned_keys = {},
        used_jokers = {},
        perishable_rounds = 5,
    },
    jokers = make_area(1),
    consumeables = make_area(1),
    P_CENTERS = {
        j_test = {
            key = "j_test",
            name = "Test Joker",
            set = "Joker",
            rarity = 1,
            order = 1,
            config = {mult = 4, extra = {chips = 2}},
        },
        e_foil = {config = {extra = 50}},
        e_holo = {config = {extra = 10}},
        e_polychrome = {config = {extra = 1.5}},
    },
    P_CENTER_POOLS = {Joker = {}},
}
G.P_CENTER_POOLS.Joker[1] = G.P_CENTERS.j_test

function create_card(kind, area, legendary, rarity, skip, soulable, key)
    return make_card(kind, area, key and G.P_CENTERS[key] or nil)
end

function find_joker(name)
    local found = {}
    for _, area in ipairs({G.jokers, G.consumeables}) do
        for _, card in ipairs(area.cards) do
            if card.ability.name == name then found[#found + 1] = card end
        end
    end
    return found
end

function save_run()
    G.save_run_calls = (G.save_run_calls or 0) + 1
    G.FILE_HANDLER = G.FILE_HANDLER or {}
    G.FILE_HANDLER.run = true
    G.FILE_HANDLER.update_queued = true
end

Game = {
    update = function(self)
        self.original_updates = (self.original_updates or 0) + 1
    end,
}
`,
  "@runtime-prelude.lua",
);

runLua(moduleSource, "@src/balalaio.lua");

runLua(
  `
assert(Balalaio.run_ready())
Balalaio.refresh_values()
assert(Balalaio.values.current_hands == "2")
assert(Balalaio.values.max_jokers == "1")

Balalaio.adjust_general("current_hands", -1)
Balalaio.adjust_general("max_hands", 1)
Balalaio.adjust_general("current_discards", -1)
Balalaio.adjust_general("max_discards", 1)
Balalaio.adjust_general("money", -1)
assert(G.GAME.current_round.hands_left == 1)
assert(G.GAME.round_resets.hands == 5)
assert(G.GAME.current_round.discards_left == 0)
assert(G.GAME.round_resets.discards == 4)
assert(G.GAME.dollars == 9)
assert(G.save_run_calls == 5)
assert(G.FILE_HANDLER.run and G.FILE_HANDLER.update_queued and G.FILE_HANDLER.force)

Balalaio.adjust_general("current_hands", -10)
Balalaio.adjust_general("current_discards", -10)
assert(G.GAME.current_round.hands_left == 0)
assert(G.GAME.current_round.discards_left == 0)

Balalaio.adjust_general("current_consumables", 1)
assert(#G.consumeables.cards == 1)
assert(G.consumeables.cards[1].added_to_deck)
assert(G.consumeables.cards[1].created_on_pause == nil)
local consumable_key = G.consumeables.cards[1].config.center.key
if consumable_key then assert(G.GAME.used_jokers[consumable_key]) end
Balalaio.adjust_general("current_consumables", -1)
assert(#G.consumeables.cards == 0)
if consumable_key then assert(not G.GAME.used_jokers[consumable_key]) end

Balalaio.open = function(view) Balalaio.last_opened = view end
Balalaio.open_editor = function(card) Balalaio.last_edited = card end

G.FUNCS.balalaio_add_joker({
    config = {ref_table = {center_key = "j_test"}}
})
assert(#G.jokers.cards == 1)
assert(G.jokers.cards[1].ability.name == "Test Joker")
assert(G.jokers.cards[1].created_on_pause == nil)
assert(G.GAME.used_jokers.j_test)
local card = G.jokers.cards[1]

local modifiers = Balalaio.collect_modifiers(card)
local extra_chips = nil
for _, entry in ipairs(modifiers) do
    assert(entry.key ~= "order")
    if entry.label == "extra.chips" then extra_chips = entry end
end
assert(extra_chips and extra_chips.parent[extra_chips.key] == 2)

G.FUNCS.balalaio_adjust_modifier({
    config = {ref_table = {entry = extra_chips, delta = 1}}
})
assert(extra_chips.parent[extra_chips.key] == 3)
assert(extra_chips.display == "3")
assert(card.remove_calls == 1)
assert(card.add_calls == 2)

G.FUNCS.balalaio_toggle_flag({
    config = {ref_table = {card = card, key = "eternal"}}
})
assert(card.ability.eternal)
G.FUNCS.balalaio_toggle_flag({
    config = {ref_table = {card = card, key = "perishable"}}
})
assert(card.ability.perishable)
assert(not card.ability.eternal)
assert(card.ability.perish_tally == 5)
G.FUNCS.balalaio_toggle_flag({
    config = {ref_table = {card = card, key = "rental"}}
})
assert(card.ability.rental)

local capacity_before_negative = G.jokers.config.card_limit
G.FUNCS.balalaio_cycle_edition({
    config = {ref_table = {card = card, delta = -1}}
})
assert(card.edition and card.edition.negative)
assert(G.jokers.config.card_limit == capacity_before_negative + 1)
G.FUNCS.balalaio_cycle_edition({
    config = {ref_table = {card = card, delta = 1}}
})
assert(card.edition == nil)
assert(G.jokers.config.card_limit == capacity_before_negative)

G.FUNCS.balalaio_remove_joker({
    config = {ref_table = {card = card}}
})
assert(#G.jokers.cards == 0)
assert(not G.GAME.used_jokers.j_test)

local game = {}
Game.update(game, 0.016)
assert(game.original_updates == 1)

print("Lua runtime mutation tests passed.")
`,
  "@runtime-tests.lua",
);
