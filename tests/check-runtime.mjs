import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { lua, lauxlib, lualib, to_luastring, to_jsstring } from "fengari";

const currentDirectory = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(currentDirectory, "..");
const moduleSource = fs.readFileSync(
  path.join(repositoryRoot, "Balalaio", "balalaio.lua"),
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

local function copy_value(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, nested in pairs(value) do
        result[key] = copy_value(nested)
    end
    return result
end

local function make_card(kind, area, center, front)
    center = center or {name = kind, set = kind, config = {}}
    local card = {
        area = area,
        added_to_deck = false,
        created_on_pause = true,
        REMOVED = false,
        ability = {
            name = center.name or kind,
            set = kind,
            mult = center.config and center.config.mult or 0,
            x_mult = center.config
                and (center.config.Xmult or center.config.x_mult)
                or 1,
            h_chips = 0,
            x_chips = 1,
            h_x_chips = 1,
            repetitions = 0,
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
            perma_x_mult = 0,
            card_limit = 0,
            extra_slots_used = 0,
            bonus = 0,
            max_highlighted = center.config
                and center.config.max_highlighted
                or nil,
            extra = center.config
                and copy_value(center.config.extra)
                or nil,
        },
        config = {center = center, card = front},
        base = front and {
            suit = front.suit,
            value = front.value,
            nominal = front.nominal,
            suit_nominal = front.suit_nominal,
        } or nil,
    }
    if kind ~= "Joker" and center.config then
        -- This mirrors Card:set_ability: consumable is the one deliberately
        -- shared center-config alias; extra and the other instance values are
        -- copied and may be edited independently.
        card.ability.consumeable = center.config
    end
    function card:add_to_deck()
        self.added_to_deck = true
        self.add_calls = (self.add_calls or 0) + 1
    end
    function card:remove_from_deck()
        self.added_to_deck = false
        self.remove_calls = (self.remove_calls or 0) + 1
    end
    function card:remove()
        G.lifecycle_log = G.lifecycle_log or {}
        G.lifecycle_log[#G.lifecycle_log + 1] =
            "remove:" .. tostring(self.playing_card or "card")
        remove_from_area(self)
        if self.playing_card and G and G.playing_cards then
            for index = #G.playing_cards, 1, -1 do
                if G.playing_cards[index] == self then
                    table.remove(G.playing_cards, index)
                    break
                end
            end
            for index, survivor in ipairs(G.playing_cards) do
                survivor.playing_card = index
            end
        end
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
        self.set_edition_calls = (self.set_edition_calls or 0) + 1
        local was_negative = self.edition and self.edition.negative
        local capacity_area = self.area == G.jokers and G.jokers
            or (self.area == G.consumeables and G.consumeables or nil)
        if was_negative and self.added_to_deck and capacity_area then
            capacity_area.config.card_limit =
                capacity_area.config.card_limit - 1
        end
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
                if self.added_to_deck and capacity_area then
                    capacity_area.config.card_limit =
                        capacity_area.config.card_limit + 1
                end
            end
        end
    end
    function card:set_ability(new_center)
        self.set_ability_calls = (self.set_ability_calls or 0) + 1
        self.config.center = new_center
        self.ability.name = new_center.name
        self.ability.set = new_center.set
        self.ability.consumeable =
            new_center.set ~= "Joker" and new_center.config or nil
        self.ability.extra = new_center.config
            and copy_value(new_center.config.extra)
            or nil
    end
    function card:set_seal(new_seal)
        self.set_seal_calls = (self.set_seal_calls or 0) + 1
        self.seal = new_seal
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
    deck = make_area(0),
    hand = make_area(52),
    discard = make_area(52),
    play = make_area(5),
    playing_cards = {},
    playing_card = 3,
    P_CENTERS = {
        c_base = {
            key = "c_base",
            name = "Base",
            set = "Default",
            order = 0,
            config = {},
        },
        c_tarot_test = {
            key = "c_tarot_test",
            name = "Test Tarot",
            set = "Tarot",
            order = 1,
            config = {
                max_highlighted = 2,
                extra = {quarter = 0.25, amount = 2},
            },
        },
        c_tarot_second = {
            key = "c_tarot_second",
            name = "Second Tarot",
            set = "Tarot",
            order = 2,
            config = {extra = {amount = 3}},
        },
        c_planet_test = {
            key = "c_planet_test",
            name = "Test Planet",
            set = "Planet",
            order = 1,
            config = {extra = {amount = 1}},
        },
        c_planet_second = {
            key = "c_planet_second",
            name = "Second Planet",
            set = "Planet",
            order = 2,
            config = {extra = {amount = 2}},
        },
        c_spectral_test = {
            key = "c_spectral_test",
            name = "Test Spectral",
            set = "Spectral",
            order = 1,
            config = {extra = {amount = 1}},
        },
        c_spectral_second = {
            key = "c_spectral_second",
            name = "Second Spectral",
            set = "Spectral",
            order = 2,
            config = {extra = {amount = 2}},
        },
        m_bonus = {
            key = "m_bonus",
            name = "Bonus Card",
            set = "Enhanced",
            order = 1,
            config = {bonus = 30},
        },
        j_test = {
            key = "j_test",
            name = "Test Joker",
            set = "Joker",
            rarity = 1,
            order = 1,
            config = {
                mult = 4,
                Xmult = 1.5,
                extra = {
                    chips = 2,
                    quarter = 0.25,
                    hundredth = 0.01,
                },
            },
        },
        e_foil = {config = {extra = 50}},
        e_holo = {config = {extra = 10}},
        e_polychrome = {config = {extra = 1.5}},
        e_custom = {config = {x_mult = 1.25}},
        j_lower_xmult = {
            key = "j_lower_xmult",
            name = "Lowercase Xmult Joker",
            set = "Joker",
            rarity = 1,
            order = 2,
            config = {x_mult = 0.25},
        },
        j_picker_three = {
            key = "j_picker_three",
            name = "Picker Three",
            set = "Joker",
            rarity = 2,
            order = 3,
            config = {},
        },
        j_picker_four = {
            key = "j_picker_four",
            name = "Picker Four",
            set = "Joker",
            rarity = 3,
            order = 4,
            config = {},
        },
        j_picker_five = {
            key = "j_picker_five",
            name = "Picker Five",
            set = "Joker",
            rarity = 4,
            order = 5,
            config = {},
        },
        j_picker_six = {
            key = "j_picker_six",
            name = "Picker Six",
            set = "Joker",
            rarity = 1,
            order = 6,
            config = {},
        },
    },
    P_CENTER_POOLS = {
        Joker = {},
        Tarot = {},
        Planet = {},
        Spectral = {},
        Enhanced = {},
    },
    P_CARDS = {
        S_2 = {
            key = "S_2",
            suit = "Spades",
            value = "2",
            nominal = 2,
            suit_nominal = 4,
        },
        S_3 = {
            key = "S_3",
            suit = "Spades",
            value = "3",
            nominal = 3,
            suit_nominal = 4,
        },
        H_2 = {
            key = "H_2",
            suit = "Hearts",
            value = "2",
            nominal = 2,
            suit_nominal = 3,
        },
        H_3 = {
            key = "H_3",
            suit = "Hearts",
            value = "3",
            nominal = 3,
            suit_nominal = 3,
        },
        C_2 = {
            key = "C_2",
            suit = "Clubs",
            value = "2",
            nominal = 2,
            suit_nominal = 2,
        },
        C_3 = {
            key = "C_3",
            suit = "Clubs",
            value = "3",
            nominal = 3,
            suit_nominal = 2,
        },
        D_2 = {
            key = "D_2",
            suit = "Diamonds",
            value = "2",
            nominal = 2,
            suit_nominal = 1,
        },
        D_3 = {
            key = "D_3",
            suit = "Diamonds",
            value = "3",
            nominal = 3,
            suit_nominal = 1,
        },
    },
    P_SEALS = {
        Red = {key = "Red", order = 1},
        Blue = {key = "Blue", order = 2},
    },
}
G.deck.config.card_limits = {total_slots = 0}
G.P_CENTER_POOLS.Joker = {
    G.P_CENTERS.j_test,
    G.P_CENTERS.j_lower_xmult,
    G.P_CENTERS.j_picker_three,
    G.P_CENTERS.j_picker_four,
    G.P_CENTERS.j_picker_five,
    G.P_CENTERS.j_picker_six,
}
G.P_CENTER_POOLS.Tarot = {
    G.P_CENTERS.c_tarot_test,
    G.P_CENTERS.c_tarot_second,
}
G.P_CENTER_POOLS.Planet = {
    G.P_CENTERS.c_planet_test,
    G.P_CENTERS.c_planet_second,
}
G.P_CENTER_POOLS.Spectral = {
    G.P_CENTERS.c_spectral_test,
    G.P_CENTERS.c_spectral_second,
}
G.P_CENTER_POOLS.Enhanced = {G.P_CENTERS.m_bonus}

SMODS = {
    Suits = {
        Spades = {key = "Spades", card_key = "S", suit_nominal = 4},
        Hearts = {key = "Hearts", card_key = "H", suit_nominal = 3},
        Clubs = {key = "Clubs", card_key = "C", suit_nominal = 2},
        Diamonds = {key = "Diamonds", card_key = "D", suit_nominal = 1},
    },
    Ranks = {
        ["2"] = {key = "2", card_key = "2", nominal = 2},
        ["3"] = {key = "3", card_key = "3", nominal = 3},
    },
    Seal = {obj_buffer = {"Red", "Blue"}},
    Sticker = {obj_buffer = {}},
}

function SMODS.change_base(card, suit, rank)
    SMODS.change_base_calls = (SMODS.change_base_calls or 0) + 1
    local next_suit = suit or card.base.suit
    local next_rank = rank or card.base.value
    local prefix = SMODS.Suits[next_suit] and SMODS.Suits[next_suit].card_key
    local suffix = SMODS.Ranks[next_rank] and SMODS.Ranks[next_rank].card_key
    local front = prefix and suffix and G.P_CARDS[prefix .. "_" .. suffix]
    if not front then return false end
    card.config.card = front
    card.base = {
        suit = front.suit,
        value = front.value,
        nominal = front.nominal,
        suit_nominal = front.suit_nominal,
    }
    return true
end

function SMODS.calculate_context(context)
    SMODS.context_calls = (SMODS.context_calls or 0) + 1
    SMODS.last_context = context
    G.lifecycle_log = G.lifecycle_log or {}
    G.lifecycle_log[#G.lifecycle_log + 1] = "remove_context"
end

function create_card(kind, area, legendary, rarity, skip, soulable, key)
    local center = key and G.P_CENTERS[key]
        or (
            kind == "Tarot"
            and G.P_CENTERS.c_tarot_test
            or {name = kind, set = kind, config = {}}
        )
    return make_card(kind, area, center)
end

function create_playing_card(init, area)
    G.playing_card = (G.playing_card or 0) + 1
    local card = make_card(
        "Default",
        area,
        init.center or G.P_CENTERS.c_base,
        init.front
    )
    card.playing_card = G.playing_card
    card:add_to_deck()
    G.playing_cards[#G.playing_cards + 1] = card
    area:emplace(card)
    card:start_materialize(nil, true)
    return card
end

function playing_card_joker_effects(cards)
    G.playing_card_effect_calls = (G.playing_card_effect_calls or 0) + 1
    G.last_playing_card_effects = cards
    G.lifecycle_log = G.lifecycle_log or {}
    G.lifecycle_log[#G.lifecycle_log + 1] = "playing_card_added"
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

runLua(moduleSource, "@Balalaio/balalaio.lua");
runLua(
  `
first_balalaio_instance = Balalaio
first_balalaio_game_update = Game.update
`,
  "@capture-reload-state.lua",
);
runLua(moduleSource, "@Balalaio/balalaio-reload.lua");
runLua(
  `
assert(Balalaio == first_balalaio_instance)
assert(Game.update == first_balalaio_game_update)

local replacement_update_calls = 0
Balalaio = {
    update = function()
        replacement_update_calls = replacement_update_calls + 1
    end,
}
local replacement_game = {}
Game.update(replacement_game, 0.016)
assert(replacement_game.original_updates == 1)
assert(replacement_update_calls == 1)
Balalaio = first_balalaio_instance
`,
  "@reload-tests.lua",
);

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

local real_open = Balalaio.open
local real_open_editor = Balalaio.open_editor
Balalaio.open = function(view) Balalaio.last_opened = view end
Balalaio.open_editor = function(card, kind)
    Balalaio.last_edited = card
    Balalaio.last_editor_kind = kind
    Balalaio.state.editor_kind = kind or "joker"
    Balalaio.state.selected_card = card
    if kind == "joker" then Balalaio.state.selected_joker = card end
end
Balalaio.open_picker = function(kind)
    Balalaio.last_picker_kind = kind
end

G.FUNCS.balalaio_add_joker({
    config = {ref_table = {center_key = "j_test"}}
})
assert(#G.jokers.cards == 1)
assert(G.jokers.cards[1].ability.name == "Test Joker")
assert(G.jokers.cards[1].created_on_pause == nil)
assert(G.GAME.used_jokers.j_test)
local card = G.jokers.cards[1]
card.ability.unknown_stat = 7

G.CARD_W = 1
G.CARD_H = 1.4
G.UIT = {R = "R", C = "C", T = "T", O = "O"}
G.C = {
    UI = {TEXT_LIGHT = {}, TRANSPARENT_DARK = {}, BACKGROUND_INACTIVE = {}},
    JOKER_GREY = {},
    RARITY = {[1] = {}, [2] = {}, [3] = {}, [4] = {}},
    SECONDARY_SET = {
        Tarot = {},
        Planet = {},
        Spectral = {},
        Edition = {},
        Enhanced = {},
    },
    SUITS = {
        Spades = {},
        Hearts = {},
        Clubs = {},
        Diamonds = {},
    },
    RED = {},
    GREEN = {},
    BLUE = {},
    GREY = {},
    ORANGE = {},
    PURPLE = {},
    GOLD = {},
    ETERNAL = {},
    PERISHABLE = {},
    RENTAL = {},
}
G.I = {CARD = {}, CARDAREA = {}}
function create_UIBox_generic_options(args)
    return {
        n = "ROOT",
        config = args,
        nodes = args.contents or {},
    }
end
G.FUNCS.overlay_menu = function(args)
    G.OVERLAY_MENU = args
end
Moveable = {
    remove = function(target)
        target.REMOVED = true
    end,
}
CardArea = function(x, y, width, height, config)
    local area = {
        T = {x = x, y = y, w = width, h = height},
        config = config,
        cards = {},
    }
    G.I.CARDAREA[#G.I.CARDAREA + 1] = area
    function area:emplace(target)
        self.cards[#self.cards + 1] = target
        target.area = self
        if self.config.type == "title"
            and target.states
            and target.states.drag
        then
            -- Native CardArea:set_ranks turns drag back on for title cards.
            target.states.drag.can = true
        end
    end
    function area:remove_card(target)
        for index = #self.cards, 1, -1 do
            if self.cards[index] == target then
                table.remove(self.cards, index)
                break
            end
        end
        target.area = nil
    end
    function area:remove()
        -- Engine-faithful: native CardArea:remove clears membership but does
        -- not call Card:remove on each card. Balalaio must tear previews down
        -- explicitly before delegating here.
        self.cards = {}
        for index = #G.I.CARDAREA, 1, -1 do
            if G.I.CARDAREA[index] == self then
                table.remove(G.I.CARDAREA, index)
                break
            end
        end
        self.REMOVED = true
    end
    return area
end
Card = function(x, y, width, height, front, center)
    if center and center.key and G.GAME and G.GAME.used_jokers then
        G.GAME.used_jokers[center.key] = true
    end
    if center and center.key == G.preview_constructor_error_key then
        error("forced preview constructor failure")
    end
    local preview = {
        T = {x = x, y = y, w = width, h = height},
        config = {center = center, card = front},
        ability = {name = center.name, set = center.set},
        base = front and {
            suit = front.suit,
            value = front.value,
            nominal = front.nominal,
            suit_nominal = front.suit_nominal,
        } or nil,
        children = {},
        states = {drag = {can = true}, focus = {is = false}},
        REMOVED = false,
    }
    function preview:generate_UIBox_ability_table()
        return {from_preview_fallback = true}
    end
    G.I.CARD[#G.I.CARD + 1] = preview
    if center and type(center.set_ability) == "function" then
        center:set_ability(preview)
    end
    return preview
end

local source_tooltip_calls = 0
function card:generate_UIBox_ability_table(vars_only)
    source_tooltip_calls = source_tooltip_calls + 1
    return {from_live_source = true, vars_only = vars_only}
end
local center_update_calls = 0
card.config.center.update = function()
    center_update_calls = center_update_calls + 1
end
local center_set_ability_calls = 0
local custom_set_ability = function()
    center_set_ability_calls = center_set_ability_calls + 1
    G.GAME.dollars = G.GAME.dollars + 1000
end
card.config.center.set_ability = custom_set_ability
card.edition = {
    negative = true,
    type = "negative",
    nested_visual = {value = 9},
}
local capacity_before_gallery = G.jokers.config.card_limit
local live_count_before_gallery = #G.jokers.cards
local gallery = Balalaio.create_jokers()
local preview_area = nil
local edit_targets_live_card = false
local remove_targets_live_card = false
local function inspect_gallery(node)
    if type(node) ~= "table" then return end
    if node.n == G.UIT.O and node.config and node.config.object then
        preview_area = node.config.object
    end
    if node.config and node.config.button == "balalaio_edit_joker" then
        edit_targets_live_card =
            node.config.ref_table and node.config.ref_table.card == card
    end
    if node.config and node.config.button == "balalaio_remove_joker" then
        remove_targets_live_card =
            node.config.ref_table and node.config.ref_table.card == card
    end
    for _, child in ipairs(node.nodes or {}) do inspect_gallery(child) end
end
inspect_gallery(gallery)
assert(preview_area and #preview_area.cards == 1)
local preview = preview_area.cards[1]
assert(preview ~= card)
assert(preview.config.center == card.config.center)
assert(preview.edition and preview.edition.negative)
assert(preview.edition ~= card.edition)
assert(preview.edition.nested_visual ~= card.edition.nested_visual)
assert(preview.balalaio_source_card == card)
assert(preview.states.drag.can == false)
assert(edit_targets_live_card and remove_targets_live_card)
assert(center_set_ability_calls == 0)
assert(card.config.center.set_ability == custom_set_ability)
local tooltip = preview:generate_UIBox_ability_table(true)
assert(tooltip.from_live_source and tooltip.vars_only)
assert(source_tooltip_calls == 1)
preview:update(0.016)
assert(center_update_calls == 0)
local focused_ui_removed = false
preview.children.focused_ui = {
    remove = function() focused_ui_removed = true end,
}
preview:update(0.016)
assert(focused_ui_removed and preview.children.focused_ui == nil)
preview_area:remove()
assert(preview.REMOVED)
assert(#G.I.CARD == 0)
assert(#G.I.CARDAREA == 0)
assert(#G.jokers.cards == live_count_before_gallery)
assert(G.jokers.cards[1] == card)
assert(G.jokers.config.card_limit == capacity_before_gallery)
card.edition = nil
card.config.center.update = nil
card.config.center.set_ability = nil

local function walk_ui(node, visit)
    if type(node) ~= "table" then return end
    visit(node)
    for _, child in ipairs(node.nodes or {}) do walk_ui(child, visit) end
    for _, child in ipairs(node.contents or {}) do walk_ui(child, visit) end
end

local function assert_picker_gallery(kind, centers)
    Balalaio.state.picker_kind = kind
    Balalaio.state.picker_page = 1
    Balalaio.state.picker_rarity = 0
    Balalaio.state.picker_consumable_set = "All"
    Balalaio.state.picker_suit = "All"

    local hook_calls = 0
    local hook = function() hook_calls = hook_calls + 1 end
    for _, center in ipairs(centers) do center.set_ability = hook end
    local absent_center = centers[#centers]
    local existing_center = centers[#centers - 1]
    local absent_had_value =
        rawget(G.GAME.used_jokers, absent_center.key) ~= nil
    local absent_old_value =
        rawget(G.GAME.used_jokers, absent_center.key)
    rawset(G.GAME.used_jokers, absent_center.key, nil)
    local existing_had_value = existing_center
        and rawget(G.GAME.used_jokers, existing_center.key) ~= nil
    local existing_old_value = existing_center
        and rawget(G.GAME.used_jokers, existing_center.key)
    if existing_center then
        rawset(G.GAME.used_jokers, existing_center.key, "keep-me")
    end

    local root = Balalaio.create_picker_modal()
    local areas = {}
    local add_buttons = {}
    walk_ui(root, function(node)
        if node.n == G.UIT.O and node.config and node.config.object then
            areas[#areas + 1] = node.config.object
        elseif node.config
            and node.config.button == "balalaio_add_picker_card"
        then
            add_buttons[#add_buttons + 1] = node
        end
    end)

    assert(#areas == 5, kind .. " picker must render exactly five cards")
    assert(#add_buttons == 5, kind .. " picker must expose five ADD actions")
    for _, button in ipairs(add_buttons) do
        assert(button.config.hold_repeat ~= true)
        assert(button.config.ref_table.kind == kind)
    end
    for _, area in ipairs(areas) do
        assert(area.config.type == "title")
        assert(area.config.highlight_limit == 0)
        assert(#area.cards == 1)
        assert(area.cards[1].states.drag.can == false)
        assert(not area.cards[1].added_to_deck)
        if kind == "playing" then
            assert(area.cards[1].config.card)
        end
    end
    assert(hook_calls == 0, kind .. " previews must suppress center hooks")
    for _, center in ipairs(centers) do assert(center.set_ability == hook) end
    assert(rawget(G.GAME.used_jokers, absent_center.key) == nil)
    if existing_center then
        assert(
            rawget(G.GAME.used_jokers, existing_center.key) == "keep-me"
        )
    end

    for _, area in ipairs(areas) do area:remove() end
    assert(#G.I.CARD == 0)
    assert(#G.I.CARDAREA == 0)
    for _, center in ipairs(centers) do center.set_ability = nil end
    rawset(
        G.GAME.used_jokers,
        absent_center.key,
        absent_had_value and absent_old_value or nil
    )
    if existing_center then
        rawset(
            G.GAME.used_jokers,
            existing_center.key,
            existing_had_value and existing_old_value or nil
        )
    end
end

assert_picker_gallery("joker", {
    G.P_CENTERS.j_test,
    G.P_CENTERS.j_lower_xmult,
    G.P_CENTERS.j_picker_three,
    G.P_CENTERS.j_picker_four,
    G.P_CENTERS.j_picker_five,
})
assert_picker_gallery("consumable", {
    G.P_CENTERS.c_tarot_test,
    G.P_CENTERS.c_tarot_second,
    G.P_CENTERS.c_planet_test,
    G.P_CENTERS.c_planet_second,
    G.P_CENTERS.c_spectral_test,
})
assert_picker_gallery("playing", {G.P_CENTERS.c_base})

Balalaio.state.picker_kind = "joker"
Balalaio.state.picker_page = 1
Balalaio.state.picker_rarity = 0
G.preview_constructor_error_key = "j_picker_three"
rawset(G.GAME.used_jokers, G.preview_constructor_error_key, "survive-error")
local error_picker = Balalaio.create_picker_modal()
assert(
    rawget(G.GAME.used_jokers, G.preview_constructor_error_key)
        == "survive-error"
)
local error_areas = {}
walk_ui(error_picker, function(node)
    if node.n == G.UIT.O and node.config and node.config.object then
        error_areas[#error_areas + 1] = node.config.object
    end
end)
assert(#error_areas == 4)
for _, area in ipairs(error_areas) do area:remove() end
assert(#G.I.CARD == 0)
assert(#G.I.CARDAREA == 0)
rawset(G.GAME.used_jokers, G.preview_constructor_error_key, nil)
G.preview_constructor_error_key = nil

local modifiers = Balalaio.collect_modifiers(card)
local extra_chips = nil
local extra_quarter = nil
local extra_hundredth = nil
local root_x_mult = nil
local unknown_stat = nil
for _, entry in ipairs(modifiers) do
    assert(entry.key ~= "order")
    assert(not (
        entry.root == "ability"
        and (
            entry.key == "h_chips"
            or entry.key == "x_chips"
            or entry.key == "h_x_chips"
            or entry.key == "repetitions"
            or entry.key == "perma_x_mult"
            or entry.key == "card_limit"
            or entry.key == "extra_slots_used"
        )
    ))
    if entry.label == "extra.chips" then extra_chips = entry end
    if entry.label == "extra.quarter" then extra_quarter = entry end
    if entry.label == "extra.hundredth" then extra_hundredth = entry end
    if entry.root == "ability" and entry.key == "x_mult" then
        root_x_mult = entry
    end
    if entry.root == "ability" and entry.key == "unknown_stat" then
        unknown_stat = entry
    end
end
assert(extra_chips and extra_chips.parent[extra_chips.key] == 2)
assert(extra_chips.default == 2)
assert(extra_chips.step == 1)
assert(extra_quarter and extra_quarter.default == 0.25)
assert(extra_quarter.step == 0.25)
assert(extra_hundredth and extra_hundredth.default == 0.01)
assert(extra_hundredth.step == 0.01)
assert(root_x_mult and root_x_mult.default == 1.5)
assert(root_x_mult.step == 1.5)
assert(unknown_stat and unknown_stat.default == nil)
assert(unknown_stat.step == 1)

local lowercase_card =
    create_card("Joker", nil, nil, nil, nil, nil, "j_lower_xmult")
local lowercase_x_mult = nil
for _, entry in ipairs(Balalaio.collect_modifiers(lowercase_card)) do
    if entry.root == "ability" and entry.key == "x_mult" then
        lowercase_x_mult = entry
    end
end
assert(lowercase_x_mult and lowercase_x_mult.default == 0.25)
assert(lowercase_x_mult.step == 0.25)

lowercase_card.edition = {type = "custom", x_mult = 1.25}
local custom_edition_x_mult = nil
for _, entry in ipairs(Balalaio.collect_modifiers(lowercase_card)) do
    if entry.root == "edition" and entry.key == "x_mult" then
        custom_edition_x_mult = entry
    end
end
assert(custom_edition_x_mult and custom_edition_x_mult.default == 1.25)
assert(custom_edition_x_mult.step == 1.25)

G.FUNCS.balalaio_adjust_modifier({
    config = {ref_table = {entry = extra_chips, delta = 1}}
})
assert(extra_chips.parent[extra_chips.key] == 3)
assert(extra_chips.display == "3")
assert(card.remove_calls == 1)
assert(card.add_calls == 2)

local function adjust_modifier(entry, delta)
    G.FUNCS.balalaio_adjust_modifier({
        config = {ref_table = {entry = entry, delta = delta}}
    })
end

adjust_modifier(extra_quarter, 1)
assert(extra_quarter.parent[extra_quarter.key] == 0.5)
assert(extra_quarter.display == "0.5")
adjust_modifier(extra_quarter, -1)
assert(extra_quarter.parent[extra_quarter.key] == 0.25)

for _ = 1, 25 do adjust_modifier(extra_hundredth, 1) end
assert(extra_hundredth.parent[extra_hundredth.key] == 0.26)
assert(extra_hundredth.display == "0.26")
for _ = 1, 25 do adjust_modifier(extra_hundredth, -1) end
assert(extra_hundredth.parent[extra_hundredth.key] == 0.01)
assert(extra_hundredth.display == "0.01")

adjust_modifier(root_x_mult, 1)
assert(root_x_mult.parent[root_x_mult.key] == 3)
assert(root_x_mult.display == "3")
adjust_modifier(root_x_mult, -1)
assert(root_x_mult.parent[root_x_mult.key] == 1.5)
assert(root_x_mult.display == "1.5")

adjust_modifier(unknown_stat, 1)
assert(unknown_stat.parent[unknown_stat.key] == 8)
adjust_modifier(unknown_stat, -1)
assert(unknown_stat.parent[unknown_stat.key] == 7)

assert(type(Balalaio.update_hold_repeat) == "function")
G.TIMERS = {REAL = 0}

local repeat_calls = 0
local repeat_button = {
    config = {
        hold_repeat = true,
        button = "balalaio_test_repeat",
        ref_table = {sentinel = "repeat"},
    },
    states = {visible = true},
    disable_button = false,
}
local repeat_target = {
    config = {button_UIE = repeat_button},
    states = {visible = true},
}
G.FUNCS.balalaio_test_repeat = function(element)
    assert(element == repeat_button)
    assert(element.config.ref_table.sentinel == "repeat")
    repeat_calls = repeat_calls + 1
end
G.CONTROLLER = {
    is_cursor_down = true,
    cursor_down = {target = repeat_target},
    cursor_hover = {target = repeat_target},
}

Balalaio.update_hold_repeat()
assert(repeat_calls == 0)
assert(repeat_button.disable_button == false)
G.TIMERS.REAL = 0.299
Balalaio.update_hold_repeat()
assert(repeat_calls == 0)
G.TIMERS.REAL = 0.30
Balalaio.update_hold_repeat()
assert(repeat_calls == 1)
assert(repeat_button.disable_button == true)
G.TIMERS.REAL = 0.399
Balalaio.update_hold_repeat()
assert(repeat_calls == 1)
G.TIMERS.REAL = 0.40
Balalaio.update_hold_repeat()
assert(repeat_calls == 2)

G.TIMERS.REAL = 3
Balalaio.update_hold_repeat()
assert(repeat_calls == 3)
Balalaio.update_hold_repeat()
assert(repeat_calls == 3)
G.TIMERS.REAL = 3.099
Balalaio.update_hold_repeat()
assert(repeat_calls == 3)
G.TIMERS.REAL = 3.10
Balalaio.update_hold_repeat()
assert(repeat_calls == 4)

G.CONTROLLER.is_cursor_down = false
G.CONTROLLER.cursor_down.target = nil
Balalaio.update_hold_repeat()
assert(repeat_calls == 4)
assert(repeat_button.disable_button == false)

local held_modifier_button = {
    config = {
        hold_repeat = true,
        button = "balalaio_adjust_modifier",
        ref_table = {entry = extra_chips, delta = 1},
    },
    states = {visible = true},
}
local held_modifier_target = {
    config = {button_UIE = held_modifier_button},
    states = {visible = true},
}
G.TIMERS.REAL = 10
G.CONTROLLER = {
    is_cursor_down = true,
    cursor_down = {target = held_modifier_target},
    cursor_hover = {target = held_modifier_target},
}
G.FILE_HANDLER = {}
local saves_before_modifier_hold = G.save_run_calls
local chips_before_modifier_hold = extra_chips.parent[extra_chips.key]
Balalaio.update_hold_repeat()
G.TIMERS.REAL = 10.30
Balalaio.update_hold_repeat()
assert(extra_chips.parent[extra_chips.key] == chips_before_modifier_hold + 1)
assert(G.save_run_calls == saves_before_modifier_hold)
G.TIMERS.REAL = 10.40
Balalaio.update_hold_repeat()
assert(extra_chips.parent[extra_chips.key] == chips_before_modifier_hold + 2)
assert(G.save_run_calls == saves_before_modifier_hold)
assert(next(G.FILE_HANDLER) == nil)
assert(held_modifier_button.disable_button == true)

G.CONTROLLER.is_cursor_down = false
G.CONTROLLER.cursor_down.target = nil
Balalaio.update_hold_repeat()
assert(held_modifier_button.disable_button == nil)
assert(G.save_run_calls == saves_before_modifier_hold + 1)
assert(
    G.FILE_HANDLER.run
    and G.FILE_HANDLER.update_queued
    and G.FILE_HANDLER.force
)
Balalaio.update_hold_repeat()
assert(G.save_run_calls == saves_before_modifier_hold + 1)

G.FUNCS.balalaio_test_repeat = nil
G.CONTROLLER = nil
G.TIMERS = nil

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

-- Picker routing must preserve the card kind and use kind-specific filters.
local saves_before_picker_navigation = G.save_run_calls
G.FUNCS.balalaio_open_picker({
    config = {
        ref_table = {kind = "consumable", return_view = "consumables"},
    },
})
assert(Balalaio.state.picker_kind == "consumable")
assert(Balalaio.state.picker_return == "consumables")
assert(Balalaio.last_picker_kind == "consumable")
G.FUNCS.balalaio_picker_filter({
    config = {ref_table = {kind = "consumable", value = "Planet"}},
})
assert(Balalaio.state.picker_consumable_set == "Planet")
G.FUNCS.balalaio_picker_filter({
    config = {ref_table = {kind = "playing", value = "Hearts"}},
})
assert(Balalaio.state.picker_suit == "Hearts")
G.FUNCS.balalaio_picker_filter({
    config = {ref_table = {kind = "joker", value = 3}},
})
assert(Balalaio.state.picker_rarity == 3)
assert(G.save_run_calls == saves_before_picker_navigation)

-- General-tab +Consumable routes to the exact-card picker without mutating.
assert(Balalaio.run_ready(), "run must remain ready after picker navigation")
Balalaio.adjust_general("current_consumables", 1)
assert(Balalaio.state.picker_kind == "consumable")
assert(
    Balalaio.state.picker_return == "general",
    "general consumable picker return was "
        .. tostring(Balalaio.state.picker_return)
)
assert(Balalaio.last_picker_kind == "consumable")
assert(G.save_run_calls == saves_before_picker_navigation)

-- Exact consumable addition expands capacity once and preserves the forced key.
G.consumeables.config.card_limit = 0
G.consumeables.config.real_card_limit = 0
G.GAME.banned_keys.c_tarot_test = "restore-ban"
Balalaio.state.picker_return = "consumables"
local saves_before_consumable_add = G.save_run_calls
G.FUNCS.balalaio_add_picker_card({
    config = {
        ref_table = {
            kind = "consumable",
            center_key = "c_tarot_test",
        },
    },
})
assert(G.save_run_calls == saves_before_consumable_add + 1)
assert(#G.consumeables.cards == 1)
local exact_consumable = G.consumeables.cards[1]
assert(exact_consumable.config.center == G.P_CENTERS.c_tarot_test)
assert(exact_consumable.added_to_deck)
assert(exact_consumable.created_on_pause == nil)
assert(exact_consumable.materialized)
assert(G.consumeables.config.card_limit == 1)
assert(G.consumeables.config.real_card_limit == 1)
assert(G.GAME.used_jokers.c_tarot_test)
assert(G.GAME.banned_keys.c_tarot_test == "restore-ban")
assert(Balalaio.last_opened == "consumables")

G.FUNCS.balalaio_edit_consumable({
    config = {ref_table = {card = exact_consumable}},
})
assert(Balalaio.last_edited == exact_consumable)
assert(Balalaio.last_editor_kind == "consumable")

-- Never expose the globally shared ability.consumeable/center.config alias.
assert(exact_consumable.ability.consumeable == exact_consumable.config.center.config)
local consumable_amount = nil
local consumable_max_highlighted = nil
for _, entry in ipairs(Balalaio.collect_modifiers(exact_consumable)) do
    assert(entry.path[1] ~= "consumeable")
    if entry.label == "extra.amount" then consumable_amount = entry end
    if entry.label == "max highlighted" then
        consumable_max_highlighted = entry
    end
end
assert(consumable_amount)
assert(consumable_max_highlighted)
assert(
    exact_consumable.ability.extra
        ~= exact_consumable.config.center.config.extra
)
local center_amount_before =
    exact_consumable.config.center.config.extra.amount
local saves_before_consumable_edit = G.save_run_calls
G.FUNCS.balalaio_adjust_modifier({
    config = {ref_table = {entry = consumable_amount, delta = 1}},
})
assert(
    exact_consumable.ability.extra.amount == center_amount_before + 1,
    "consumable amount became "
        .. tostring(exact_consumable.ability.extra.amount)
        .. " from "
        .. tostring(center_amount_before)
        .. " with step "
        .. tostring(consumable_amount.step)
)
assert(exact_consumable.config.center.config.extra.amount == center_amount_before)
assert(
    exact_consumable.ability.consumeable
        ~= exact_consumable.config.center.config
)
assert(
    exact_consumable.ability.consumeable.extra.amount
        == exact_consumable.ability.extra.amount
)
assert(G.save_run_calls == saves_before_consumable_edit + 1)

local global_max_highlighted =
    exact_consumable.config.center.config.max_highlighted
local saves_before_consumable_max_edit = G.save_run_calls
G.FUNCS.balalaio_adjust_modifier({
    config = {
        ref_table = {
            entry = consumable_max_highlighted,
            delta = 1,
        },
    },
})
assert(
    exact_consumable.ability.max_highlighted
        == global_max_highlighted + 1
)
assert(
    exact_consumable.ability.consumeable.max_highlighted
        == exact_consumable.ability.max_highlighted
)
assert(
    exact_consumable.config.center.config.max_highlighted
        == global_max_highlighted
)
assert(G.save_run_calls == saves_before_consumable_max_edit + 1)

-- Invalid and stale consumable actions are strict no-ops and do not save.
local consumable_limit_before_invalid =
    G.consumeables.config.card_limit
local saves_before_invalid_consumable = G.save_run_calls
G.FUNCS.balalaio_add_picker_card({
    config = {
        ref_table = {
            kind = "consumable",
            center_key = "c_missing",
        },
    },
})
assert(#G.consumeables.cards == 1)
assert(G.consumeables.config.card_limit == consumable_limit_before_invalid)
assert(G.save_run_calls == saves_before_invalid_consumable)
local stale_parent = {value = 9}
G.FUNCS.balalaio_adjust_modifier({
    config = {
        ref_table = {
            entry = {
                card = {REMOVED = true},
                parent = stale_parent,
                key = "value",
                label = "stale",
                step = 1,
            },
            delta = 1,
        },
    },
})
assert(stale_parent.value == 9)
assert(G.save_run_calls == saves_before_invalid_consumable)

-- Seed deliberately non-contiguous IDs with a stale high-water counter.
G.playing_cards = {}
G.deck.cards = {}
G.playing_card = 0
local seed_two = create_playing_card(
    {front = G.P_CARDS.S_2, center = G.P_CENTERS.c_base},
    G.deck
)
local seed_seven = create_playing_card(
    {front = G.P_CARDS.H_3, center = G.P_CENTERS.c_base},
    G.deck
)
seed_two.playing_card = 2
seed_seven.playing_card = 7
G.playing_card = 3
G.deck.config.card_limits.total_slots = #G.playing_cards
G.playing_card_effect_calls = 0
G.last_playing_card_effects = nil
G.lifecycle_log = {}

local saves_before_playing_add = G.save_run_calls
Balalaio.state.picker_return = "deck"
G.FUNCS.balalaio_add_picker_card({
    config = {
        ref_table = {kind = "playing", front_key = "S_3"},
    },
})
assert(G.save_run_calls == saves_before_playing_add + 1)
assert(#G.playing_cards == 3)
local added_playing = G.playing_cards[3]
assert(added_playing.config.card == G.P_CARDS.S_3)
assert(added_playing.config.center == G.P_CENTERS.c_base)
assert(added_playing.area == G.deck)
assert(added_playing.added_to_deck)
assert(added_playing.playing_card == 8)
assert(G.playing_card == 8)
assert(G.playing_card_effect_calls == 1)
assert(G.last_playing_card_effects[1] == added_playing)
assert(G.lifecycle_log[1] == "playing_card_added")
assert(G.deck.config.card_limits.total_slots == 3)
local membership = 0
local ids = {}
for _, live in ipairs(G.playing_cards) do
    if live == added_playing then membership = membership + 1 end
    assert(not ids[live.playing_card])
    ids[live.playing_card] = true
end
assert(membership == 1)
assert(Balalaio.last_opened == "deck")

G.FUNCS.balalaio_edit_playing_card({
    config = {ref_table = {card = added_playing}},
})
assert(Balalaio.last_edited == added_playing)
assert(Balalaio.last_editor_kind == "playing")

-- Deck editor changes must flow through the native setter APIs.
SMODS.change_base_calls = 0
local saves_before_deck_edits = G.save_run_calls
G.FUNCS.balalaio_cycle_deck_property({
    config = {
        ref_table = {
            card = added_playing,
            property = "rank",
            delta = 1,
        },
    },
})
assert(added_playing.base.value == "2")
assert(SMODS.change_base_calls == 1)
G.FUNCS.balalaio_cycle_deck_property({
    config = {
        ref_table = {
            card = added_playing,
            property = "suit",
            delta = 1,
        },
    },
})
assert(added_playing.base.suit == "Diamonds")
assert(added_playing.config.card == G.P_CARDS.D_2)
assert(SMODS.change_base_calls == 2)
G.FUNCS.balalaio_cycle_deck_property({
    config = {
        ref_table = {
            card = added_playing,
            property = "enhancement",
            delta = 1,
        },
    },
})
assert(added_playing.config.center == G.P_CENTERS.m_bonus)
assert(added_playing.set_ability_calls == 1)
G.FUNCS.balalaio_cycle_edition({
    config = {
        ref_table = {
            card = added_playing,
            kind = "playing",
            delta = 1,
        },
    },
})
assert(added_playing.edition and added_playing.edition.foil)
assert(added_playing.set_edition_calls == 1)
G.FUNCS.balalaio_cycle_deck_property({
    config = {
        ref_table = {
            card = added_playing,
            property = "seal",
            delta = 1,
        },
    },
})
assert(added_playing.seal == "Red")
assert(added_playing.set_seal_calls == 1)
assert(G.save_run_calls == saves_before_deck_edits + 5)

-- Remove context precedes native removal, capacity is synchronous, and
-- survivor IDs match Card:remove's renumbering contract.
SMODS.context_calls = 0
SMODS.last_context = nil
G.lifecycle_log = {}
local saves_before_playing_remove = G.save_run_calls
G.FUNCS.balalaio_remove_playing_card({
    config = {ref_table = {card = added_playing}},
})
assert(G.save_run_calls == saves_before_playing_remove + 1)
assert(#G.playing_cards == 2)
assert(added_playing.REMOVED)
assert(SMODS.context_calls == 1)
assert(SMODS.last_context.remove_playing_cards)
assert(SMODS.last_context.removed[1] == added_playing)
assert(G.lifecycle_log[1] == "remove_context")
assert(G.lifecycle_log[2] == "remove:8")
assert(G.deck.config.card_limits.total_slots == 2)
assert(G.playing_cards[1].playing_card == 1)
assert(G.playing_cards[2].playing_card == 2)
assert(G.playing_card == 8)

-- Repeated/foreign removal, stale editing, invalid properties, and missing
-- picker fronts must not trigger contexts, setters, capacity changes, or saves.
local saves_before_stale_deck = G.save_run_calls
local contexts_before_stale_deck = SMODS.context_calls
local change_base_before_stale = SMODS.change_base_calls
G.FUNCS.balalaio_remove_playing_card({
    config = {ref_table = {card = added_playing}},
})
local foreign_card = {
    playing_card = 99,
    area = G.hand,
    base = {value = "2", suit = "Clubs"},
    remove = function(self) self.foreign_removed = true end,
}
G.FUNCS.balalaio_remove_playing_card({
    config = {ref_table = {card = foreign_card}},
})
G.FUNCS.balalaio_cycle_deck_property({
    config = {
        ref_table = {
            card = added_playing,
            property = "rank",
            delta = 1,
        },
    },
})
G.FUNCS.balalaio_cycle_edition({
    config = {
        ref_table = {
            card = added_playing,
            kind = "playing",
            delta = 1,
        },
    },
})
G.FUNCS.balalaio_cycle_deck_property({
    config = {
        ref_table = {
            card = seed_two,
            property = "unsupported",
            delta = 1,
        },
    },
})
G.FUNCS.balalaio_add_picker_card({
    config = {
        ref_table = {kind = "playing", front_key = "missing_front"},
    },
})
assert(not foreign_card.foreign_removed)
assert(#G.playing_cards == 2)
assert(G.deck.config.card_limits.total_slots == 2)
assert(SMODS.context_calls == contexts_before_stale_deck)
assert(SMODS.change_base_calls == change_base_before_stale)
assert(G.save_run_calls == saves_before_stale_deck)

local game = {}
Game.update(game, 0.016)
assert(game.original_updates == 1)

print("Lua runtime mutation tests passed.")
`,
  "@runtime-tests.lua",
);
