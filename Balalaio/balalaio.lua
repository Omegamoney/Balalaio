-- Balalaio
-- Offline cheat controls for Balatro.

local existing = rawget(_G, "Balalaio")
if existing and existing.VERSION == "0.4.0" then
    return existing
end
if existing and type(existing.remove_float_button) == "function" then
    pcall(existing.remove_float_button)
end

local Balalaio = {
    VERSION = "0.4.0",
    ui = {
        status = "",
    },
    state = {
        view = "general",
        joker_page = 1,
        consumable_page = 1,
        deck_page = 1,
        picker_page = 1,
        picker_kind = "joker",
        picker_rarity = 0,
        picker_consumable_set = "All",
        picker_suit = "All",
        picker_return = "jokers",
        modifier_page = 1,
        selected_joker = nil,
        selected_card = nil,
        editor_kind = "joker",
    },
    values = {},
    float_box = nil,
    float_drag_offset = nil,
    hold_repeat = {
        owner = nil,
        next_at = nil,
        repeated = false,
        previous_disable = nil,
        defer_save = false,
        save_pending = false,
    },
}

_G.Balalaio = Balalaio

local JOKERS_PER_PAGE = 5
local CONSUMABLES_PER_PAGE = 5
local DECK_PER_PAGE = 5
local PICKER_PER_PAGE = 5
local MODIFIERS_PER_PAGE = 5
local HOLD_REPEAT_DELAY = 0.30
local HOLD_REPEAT_INTERVAL = 0.10
local CARD_PREVIEW_SCALE = 0.9
local PICKER_PREVIEW_SCALE = 0.82

local EDITIONS = {
    {label = "Base", value = nil},
    {label = "Foil", value = {foil = true}},
    {label = "Holographic", value = {holo = true}},
    {label = "Polychrome", value = {polychrome = true}},
    {label = "Negative", value = {negative = true}},
}

local PLAYING_CARD_EDITIONS = {
    EDITIONS[1],
    EDITIONS[2],
    EDITIONS[3],
    EDITIONS[4],
}

local DEFAULT_ABILITY_NUMBERS = {
    mult = 0,
    h_mult = 0,
    h_x_mult = 0,
    h_dollars = 0,
    p_dollars = 0,
    t_mult = 0,
    t_chips = 0,
    x_mult = 1,
    h_chips = 0,
    x_chips = 1,
    h_x_chips = 1,
    repetitions = 0,
    h_size = 0,
    d_size = 0,
    extra_value = 0,
    perma_bonus = 0,
    perma_x_chips = 0,
    perma_mult = 0,
    perma_x_mult = 0,
    perma_h_chips = 0,
    perma_h_x_chips = 0,
    perma_h_mult = 0,
    perma_h_x_mult = 0,
    perma_p_dollars = 0,
    perma_h_dollars = 0,
    perma_repetitions = 0,
    card_limit = 0,
    extra_slots_used = 0,
    perma_score = 0,
    perma_h_score = 0,
    perma_x_score = 0,
    perma_h_x_score = 0,
    perma_blind_size = 0,
    perma_h_blind_size = 0,
    perma_x_blind_size = 0,
    perma_h_x_blind_size = 0,
    bonus = 0,
}

local CENTER_CONFIG_KEYS = {
    x_mult = "Xmult",
}

local function clamp(value, low, high)
    value = math.max(low, value)
    if high then value = math.min(high, value) end
    return value
end

local function shallow_copy(source)
    local result = {}
    if source then
        for key, value in pairs(source) do
            result[key] = value
        end
    end
    return result
end

local function format_number(value)
    if type(value) ~= "number" then return tostring(value or "") end
    if value == math.floor(value) then return string.format("%.0f", value) end
    return string.format("%.4g", value)
end

local function page_count(total, per_page)
    return math.max(1, math.ceil(total / per_page))
end

local function set_status(message)
    Balalaio.ui.status = message or ""
end

function Balalaio.run_ready()
    return G
        and G.STAGES
        and G.STAGE == G.STAGES.RUN
        and G.GAME
        and G.GAME.current_round
        and G.GAME.round_resets
        and G.jokers
        and G.jokers.cards
        and G.consumeables
        and G.consumeables.cards
end

local function flag_run_dirty()
    if not G then return end
    G.FILE_HANDLER = G.FILE_HANDLER or {}
    G.FILE_HANDLER.run = true
    G.FILE_HANDLER.update_queued = true
    G.FILE_HANDLER.force = true
end

local function persist_run_now()
    if not G then return end

    if type(save_run) == "function" then
        local ok = pcall(save_run)
        if ok then
            flag_run_dirty()
            return
        end
    end

    flag_run_dirty()
end

local function mark_run_dirty()
    local repeat_state = Balalaio.hold_repeat
    if repeat_state and repeat_state.defer_save then
        repeat_state.save_pending = true
        return
    end
    persist_run_now()
end

local function flush_repeat_save()
    local repeat_state = Balalaio.hold_repeat
    if not repeat_state or not repeat_state.save_pending then return end
    repeat_state.save_pending = false
    persist_run_now()
end

local function refresh_hud()
    if G and G.HUD and G.HUD.recalculate then
        pcall(function() G.HUD:recalculate() end)
    end
end

local function queue_change(change, after)
    local function execute()
        local ok, result = pcall(change)
        if not ok then
            set_status("Change failed: " .. tostring(result))
        else
            if result ~= false then
                mark_run_dirty()
                Balalaio.refresh_values()
                refresh_hud()
            end
            if after then after(result ~= false) end
        end
        return true
    end

    if G and G.E_MANAGER and G.E_MANAGER.add_event and Event then
        G.E_MANAGER:add_event(Event({
            trigger = "after",
            delay = 0,
            blocking = false,
            blockable = false,
            func = execute,
        }))
    else
        execute()
    end
end

function Balalaio.refresh_values()
    if not Balalaio.run_ready() then return end
    Balalaio.values.current_hands = format_number(G.GAME.current_round.hands_left)
    Balalaio.values.max_hands = format_number(G.GAME.round_resets.hands)
    Balalaio.values.current_discards = format_number(G.GAME.current_round.discards_left)
    Balalaio.values.max_discards = format_number(G.GAME.round_resets.discards)
    Balalaio.values.current_jokers = format_number(#G.jokers.cards)
    Balalaio.values.max_jokers = format_number(G.jokers.config.card_limit)
    Balalaio.values.money = format_number(G.GAME.dollars)
    Balalaio.values.current_consumables = format_number(#G.consumeables.cards)
    Balalaio.values.max_consumables = format_number(G.consumeables.config.card_limit)
end

local function remove_card_now(card)
    if not card or card.REMOVED then return false end

    local center_key = card.config
        and card.config.center
        and card.config.center.key
    local center_name = card.ability and card.ability.name

    if card.remove then
        card:remove()

        -- Card:remove deliberately skips used_jokers bookkeeping while an
        -- overlay is open. Balalaio always removes from an overlay, so mirror
        -- the stock cleanup after the card has left its area.
        if center_key
            and center_name
            and G.GAME
            and G.GAME.used_jokers
            and type(find_joker) == "function"
            and not next(find_joker(center_name, true))
        then
            G.GAME.used_jokers[center_key] = nil
        end
        return true
    end
    return false
end

local function mark_center_used(card)
    local center_key = card
        and card.config
        and card.config.center
        and card.config.center.key
    if center_key and G.GAME and G.GAME.used_jokers then
        G.GAME.used_jokers[center_key] = true
    end
end

local function expand_area_for_one(area)
    if #area.cards >= area.config.card_limit then
        area.config.card_limit = #area.cards + 1
        area.config.real_card_limit = area.config.card_limit
    end
end

local function create_forced_card(card_type, area, center_key, soulable)
    local banned_keys = G.GAME and G.GAME.banned_keys
    local was_banned = banned_keys and center_key and banned_keys[center_key]
    if banned_keys and center_key then banned_keys[center_key] = nil end

    local ok, card = pcall(
        create_card,
        card_type,
        area,
        nil,
        nil,
        true,
        soulable,
        center_key,
        "balalaio"
    )

    if banned_keys and center_key and was_banned then
        banned_keys[center_key] = was_banned
    end
    if not ok then error(card) end
    return card
end

local function add_consumable_now(center_key)
    local center = center_key
        and G.P_CENTERS
        and G.P_CENTERS[center_key]
    if center_key and not center then return false end

    expand_area_for_one(G.consumeables)
    local card = create_forced_card(
        (center and center.set) or "Tarot",
        G.consumeables,
        center_key,
        not center_key
    )
    if not card then return false end
    if card.add_to_deck then card:add_to_deck() end
    G.consumeables:emplace(card)
    card.created_on_pause = nil
    mark_center_used(card)
    if card.start_materialize then card:start_materialize(nil, true) end
    return true
end

local function add_joker_now(center_key)
    if not center_key or not G.P_CENTERS or not G.P_CENTERS[center_key] then
        return false
    end

    expand_area_for_one(G.jokers)

    local card = create_forced_card(
        "Joker",
        G.jokers,
        center_key,
        false
    )

    if not card then return false end
    if card.add_to_deck then card:add_to_deck() end
    G.jokers:emplace(card)
    card.created_on_pause = nil
    mark_center_used(card)
    if card.start_materialize then card:start_materialize(nil, true) end
    return true
end

local function add_playing_card_now(front_key)
    local front = front_key and G.P_CARDS and G.P_CARDS[front_key]
    if not front
        or not G.deck
        or not G.deck.config
        or not G.playing_cards
        or not G.P_CENTERS
        or not G.P_CENTERS.c_base
        or type(create_playing_card) ~= "function"
    then
        return false
    end

    local highest_id = tonumber(G.playing_card) or 0
    for _, existing_card in ipairs(G.playing_cards) do
        highest_id = math.max(
            highest_id,
            tonumber(existing_card.playing_card) or 0
        )
    end
    G.playing_card = highest_id

    local card = create_playing_card(
        {front = front, center = G.P_CENTERS.c_base},
        G.deck,
        false,
        true
    )
    if not card then return false end
    card.created_on_pause = nil
    if type(playing_card_joker_effects) == "function" then
        playing_card_joker_effects({card})
    end
    if G.deck.config.card_limits then
        G.deck.config.card_limits.total_slots = #G.playing_cards
    else
        G.deck.config.card_limit = #G.playing_cards
    end
    return true
end

local function remove_playing_card_now(card)
    if not card or card.REMOVED or not card.playing_card then return false end
    local found = false
    for _, live_card in ipairs(G.playing_cards or {}) do
        if live_card == card then
            found = true
            break
        end
    end
    if not found
        or card.getting_sliced
        or card.destroyed
        or card.shattered
        or not card.area
        or (G.play and card.area == G.play)
    then
        return false
    end
    if SMODS and type(SMODS.calculate_context) == "function" then
        SMODS.calculate_context({
            remove_playing_cards = true,
            removed = {card},
        })
    end
    if card.remove then
        card:remove()
        if G.deck and G.deck.config then
            if G.deck.config.card_limits then
                G.deck.config.card_limits.total_slots = #G.playing_cards
            else
                G.deck.config.card_limit = #G.playing_cards
            end
        end
        return true
    end
    return false
end

function Balalaio.adjust_general(key, delta)
    if not Balalaio.run_ready() then
        set_status("Start or continue a run first.")
        return
    end

    if key == "current_jokers" and delta > 0 then
        Balalaio.state.picker_return = "general"
        Balalaio.state.picker_page = 1
        Balalaio.state.picker_kind = "joker"
        set_status("Choose a Joker to add.")
        Balalaio.open_picker("joker")
        return
    end

    if key == "current_consumables" and delta > 0 then
        Balalaio.state.picker_return = "general"
        Balalaio.state.picker_page = 1
        Balalaio.state.picker_kind = "consumable"
        set_status("Choose a consumable to add.")
        Balalaio.open_picker("consumable")
        return
    end

    queue_change(function()
        if key == "current_hands" then
            G.GAME.current_round.hands_left =
                math.max(0, G.GAME.current_round.hands_left + delta)
        elseif key == "max_hands" then
            G.GAME.round_resets.hands =
                math.max(0, G.GAME.round_resets.hands + delta)
        elseif key == "current_discards" then
            G.GAME.current_round.discards_left =
                math.max(0, G.GAME.current_round.discards_left + delta)
        elseif key == "max_discards" then
            G.GAME.round_resets.discards =
                math.max(0, G.GAME.round_resets.discards + delta)
        elseif key == "current_jokers" then
            local card = G.jokers.cards[#G.jokers.cards]
            local changed = remove_card_now(card)
            if not changed then
                set_status("There is no Joker to remove.")
            else
                set_status("Removed the last Joker.")
            end
            return changed
        elseif key == "max_jokers" then
            G.jokers.config.card_limit =
                math.max(0, G.jokers.config.card_limit + delta)
            G.jokers.config.real_card_limit = G.jokers.config.card_limit
        elseif key == "money" then
            G.GAME.dollars = G.GAME.dollars + delta
        elseif key == "current_consumables" then
            local card = G.consumeables.cards[#G.consumeables.cards]
            local changed = remove_card_now(card)
            if not changed then
                set_status("There is no consumable to remove.")
            else
                set_status("Removed the last consumable.")
            end
            return changed
        elseif key == "max_consumables" then
            G.consumeables.config.card_limit =
                math.max(0, G.consumeables.config.card_limit + delta)
            G.consumeables.config.real_card_limit =
                G.consumeables.config.card_limit
        else
            return false
        end
        return true
    end)
end

local function text_node(text, scale, colour, config)
    config = config or {}
    config.text = text
    config.scale = scale or 0.35
    config.colour = colour or G.C.UI.TEXT_LIGHT
    return {n = G.UIT.T, config = config}
end

local function live_text_node(ref_table, ref_value, scale, colour)
    return {
        n = G.UIT.T,
        config = {
            text = "",
            ref_table = ref_table,
            ref_value = ref_value,
            scale = scale or 0.4,
            colour = colour or G.C.UI.TEXT_LIGHT,
            shadow = true,
        },
    }
end

local function compact_button(args)
    return {
        n = G.UIT.C,
        config = {
            id = args.id,
            align = "cm",
            minw = args.minw or 0.7,
            maxw = args.maxw or args.minw or 0.7,
            minh = args.minh or 0.52,
            padding = args.padding or 0.03,
            r = 0.1,
            colour = args.colour or G.C.BLUE,
            hover = true,
            shadow = true,
            button = args.button,
            ref_table = args.ref_table,
            choice = args.choice,
            chosen = args.chosen,
            hold_repeat = args.hold_repeat,
        },
        nodes = {
            text_node(
                args.label or "",
                args.scale or 0.32,
                args.text_colour or G.C.UI.TEXT_LIGHT,
                {shadow = true}
            ),
        },
    }
end

local function general_row(label, value_key, colour)
    return {
        n = G.UIT.R,
        config = {
            align = "cm",
            minw = 5.25,
            minh = 0.62,
            padding = 0.025,
            r = 0.08,
            colour = G.C.UI.TRANSPARENT_DARK,
        },
        nodes = {
            {
                n = G.UIT.C,
                config = {align = "cl", minw = 2.72, maxw = 2.72},
                nodes = {text_node(label, 0.31, G.C.JOKER_GREY)},
            },
            compact_button({
                label = "-",
                button = "balalaio_adjust",
                ref_table = {key = value_key, delta = -1},
                colour = G.C.RED,
                minw = 0.66,
                hold_repeat = true,
            }),
            {
                n = G.UIT.C,
                config = {align = "cm", minw = 0.9, maxw = 0.9},
                nodes = {
                    live_text_node(Balalaio.values, value_key, 0.4, colour),
                },
            },
            compact_button({
                label = "+",
                button = "balalaio_adjust",
                ref_table = {key = value_key, delta = 1},
                colour = G.C.GREEN,
                minw = 0.66,
                hold_repeat = value_key ~= "current_jokers"
                    and value_key ~= "current_consumables",
            }),
        },
    }
end

local function section_title(label, colour)
    return {
        n = G.UIT.R,
        config = {align = "cl", minw = 5.25, minh = 0.42},
        nodes = {
            text_node(label, 0.34, colour or G.C.ORANGE, {shadow = true}),
        },
    }
end

function Balalaio.create_general()
    Balalaio.refresh_values()
    local left = {
        section_title("ROUNDS", G.C.BLUE),
        general_row("Current hands", "current_hands", G.C.BLUE),
        general_row("Max hands", "max_hands", G.C.BLUE),
        general_row("Current discards", "current_discards", G.C.RED),
        general_row("Max discards", "max_discards", G.C.RED),
        section_title("ECONOMY", G.C.MONEY),
        general_row("Money", "money", G.C.MONEY),
    }

    local right = {
        section_title("JOKERS", G.C.PURPLE),
        general_row("Occupied slots", "current_jokers", G.C.PURPLE),
        general_row("Max slots", "max_jokers", G.C.PURPLE),
        section_title("CONSUMABLES", G.C.SECONDARY_SET.Tarot),
        general_row(
            "Occupied slots",
            "current_consumables",
            G.C.SECONDARY_SET.Tarot
        ),
        general_row(
            "Max slots",
            "max_consumables",
            G.C.SECONDARY_SET.Tarot
        ),
    }

    return {
        n = G.UIT.R,
        config = {align = "tm", padding = 0.08, minw = 10.9, minh = 4.55},
        nodes = {
            {
                n = G.UIT.C,
                config = {align = "tm", padding = 0.05},
                nodes = left,
            },
            {
                n = G.UIT.C,
                config = {align = "tm", padding = 0.05},
                nodes = right,
            },
        },
    }
end

local function sorted_joker_centers()
    local centers = {}
    local seen = {}

    if G.P_CENTER_POOLS and G.P_CENTER_POOLS.Joker then
        for _, center in ipairs(G.P_CENTER_POOLS.Joker) do
            if center and center.key and not seen[center.key] then
                centers[#centers + 1] = center
                seen[center.key] = true
            end
        end
    elseif G.P_CENTERS then
        for key, center in pairs(G.P_CENTERS) do
            if center and center.set == "Joker" then
                center.key = center.key or key
                centers[#centers + 1] = center
            end
        end
    end

    table.sort(centers, function(a, b)
        local ao = a.order or 9999
        local bo = b.order or 9999
        if ao == bo then return (a.name or "") < (b.name or "") end
        return ao < bo
    end)
    return centers
end

local function page_controls(kind, page, pages)
    return {
        n = G.UIT.R,
        config = {align = "cm", padding = 0.04, minh = 0.55},
        nodes = {
            compact_button({
                label = "<",
                button = page > 1 and "balalaio_change_page" or nil,
                ref_table = {kind = kind, delta = -1},
                colour = page > 1 and G.C.BLUE or G.C.GREY,
                minw = 0.75,
            }),
            {
                n = G.UIT.C,
                config = {align = "cm", minw = 2.1},
                nodes = {
                    text_node(
                        "Page " .. tostring(page) .. " / " .. tostring(pages),
                        0.3,
                        G.C.JOKER_GREY
                    ),
                },
            },
            compact_button({
                label = ">",
                button = page < pages and "balalaio_change_page" or nil,
                ref_table = {kind = kind, delta = 1},
                colour = page < pages and G.C.BLUE or G.C.GREY,
                minw = 0.75,
            }),
        },
    }
end

local function joker_name(card)
    return (card and card.ability and card.ability.name)
        or (card and card.config and card.config.center and card.config.center.name)
        or "Unknown Joker"
end

local function joker_rarity_colour(card)
    local rarity = card
        and card.config
        and card.config.center
        and card.config.center.rarity
    return (rarity and G.C.RARITY[rarity]) or G.C.JOKER_GREY
end

local function copy_visual_value(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, nested in pairs(value) do
        result[key] = copy_visual_value(nested, seen)
    end
    return result
end

local function remove_preview_card(card)
    if not card or card.REMOVED then return end
    card.removed = true
    card.added_to_deck = nil
    if card.ability then card.ability.queue_negative_removal = nil end
    if card.area and card.area.remove_card then
        card.area:remove_card(card)
    end
    if card.remove_from_area then card:remove_from_area() end

    if card.canvas_text
        and SMODS
        and type(SMODS.clean_up_canvas_text) == "function"
    then
        SMODS.clean_up_canvas_text(card)
    end
    if card.children and type(remove_all) == "function" then
        remove_all(card.children)
    end
    card.children = {}

    if G and G.I and G.I.CARD then
        for index = #G.I.CARD, 1, -1 do
            if G.I.CARD[index] == card then
                table.remove(G.I.CARD, index)
                break
            end
        end
    end

    if Moveable and Moveable.remove then
        Moveable.remove(card)
    else
        card.REMOVED = true
    end
end

local function construct_preview_card(area, width, height, front, center)
    -- Steamodded delegates Card construction to center:set_ability. Those
    -- hooks are intended for live cards and may mutate the run, so suppress
    -- only that custom hook while the core Card initializer builds a preview.
    local had_set_ability = rawget(center, "set_ability") ~= nil
    local center_set_ability = rawget(center, "set_ability")
    local used_jokers = G
        and G.GAME
        and G.GAME.used_jokers
    local center_key = center and center.key
    local had_used_center = used_jokers
        and center_key
        and rawget(used_jokers, center_key) ~= nil
    local used_center_value = used_jokers
        and center_key
        and rawget(used_jokers, center_key)
    rawset(center, "set_ability", false)
    local ok, preview = pcall(
        Card,
        area.T.x + area.T.w / 2,
        area.T.y,
        width,
        height,
        front,
        center,
        {
            bypass_discovery_center = true,
            bypass_discovery_ui = true,
            bypass_lock = true,
        }
    )
    if had_set_ability then
        rawset(center, "set_ability", center_set_ability)
    else
        rawset(center, "set_ability", nil)
    end
    -- Card:set_ability marks a center as used whenever a Card is constructed
    -- before the overlay itself exists. A modal definition is built first, so
    -- restore the exact live-run value after every private preview.
    if used_jokers and center_key then
        if had_used_center then
            rawset(used_jokers, center_key, used_center_value)
        else
            rawset(used_jokers, center_key, nil)
        end
    end
    if not ok then error(preview) end
    return preview
end

local function create_card_preview(args)
    args = args or {}
    local source = args.source
    local center = args.center
        or (source and source.config and source.config.center)
    local front = args.front
        or (source and source.config and source.config.card)
    if (source and source.REMOVED)
        or not center
        or (type(CardArea) ~= "table" and type(CardArea) ~= "function")
        or (type(Card) ~= "table" and type(Card) ~= "function")
        or not G.CARD_W
        or not G.CARD_H
    then
        return nil
    end

    local area = nil
    local preview = nil
    local ok, result = pcall(function()
        local scale = args.scale or CARD_PREVIEW_SCALE
        local card_width = G.CARD_W * scale
        local card_height = G.CARD_H * scale
        local area_width = args.area_width or 1.7
        area = CardArea(
            0,
            0,
            area_width,
            card_height + 0.28,
            {
                card_limit = 1,
                type = "title",
                highlight_limit = 0,
                card_w = card_width,
                no_card_count = true,
            }
        )

        local remove_area = area.remove
        area.remove = function(self)
            while self.cards and #self.cards > 0 do
                remove_preview_card(self.cards[#self.cards])
            end
            if remove_area then return remove_area(self) end
        end

        preview = construct_preview_card(
            area,
            card_width,
            card_height,
            front,
            center
        )

        if source then
            preview.edition = copy_visual_value(source.edition)
            preview.seal = source.seal
            preview.sticker = source.sticker
            preview.sticker_run = source.sticker_run
            preview.pinned = source.pinned
            preview.debuff = source.debuff
            preview.greyed = source.greyed
        end
        preview.added_to_deck = nil
        preview.playing_card = nil
        preview.facing = "front"
        preview.no_ui = false
        preview.balalaio_source_card = source
        preview.states.drag.can = false
        -- A gallery card is display-only. Card:update delegates to the
        -- Joker center's update hook, which can mutate run state; the normal
        -- Moveable pass still positions and animates this static preview.
        preview.update = function(self)
            if self.children
                and self.children.focused_ui
                and not (self.states and self.states.focus and self.states.focus.is)
            then
                self.children.focused_ui:remove()
                self.children.focused_ui = nil
            end
        end

        if preview.ability then
            preview.ability.eternal =
                source and source.ability and source.ability.eternal or nil
            preview.ability.perishable =
                source and source.ability and source.ability.perishable or nil
            preview.ability.perish_tally =
                source and source.ability and source.ability.perish_tally or nil
            preview.ability.rental =
                source and source.ability and source.ability.rental or nil
            preview.ability.queue_negative_removal = nil

            local sticker_keys = SMODS
                and SMODS.Sticker
                and SMODS.Sticker.obj_buffer
                or {}
            for _, sticker_key in ipairs(sticker_keys) do
                preview.ability[sticker_key] =
                    source
                    and source.ability
                    and source.ability[sticker_key]
                    or nil
            end
        end

        local preview_tooltip = preview.generate_UIBox_ability_table
        preview.generate_UIBox_ability_table = function(self, ...)
            if source
                and not source.REMOVED
                and type(source.generate_UIBox_ability_table) == "function"
            then
                return source:generate_UIBox_ability_table(...)
            end
            if preview_tooltip then
                return preview_tooltip(self, ...)
            end
        end
        preview.remove = remove_preview_card

        area:emplace(preview)
        -- CardArea:emplace -> set_ranks enables dragging for title areas.
        -- Reassert display-only behavior after the native insertion step.
        preview.states.drag.can = false
        return area
    end)

    if not ok then
        if preview and not preview.REMOVED then
            pcall(function() remove_preview_card(preview) end)
        end
        if area and not area.REMOVED and area.remove then
            pcall(function() area:remove() end)
        end
        return nil
    end
    return result
end

local function gallery_column(args)
    local column_width = args.column_width or 1.92
    local column_height = args.column_height or 2.15
    local preview_area = create_card_preview({
        source = args.source,
        center = args.center,
        front = args.front,
        scale = args.preview_scale,
        area_width = column_width - 0.22,
    })
    local preview_node = preview_area and {
        n = G.UIT.O,
        config = {object = preview_area},
    } or text_node("Preview unavailable", 0.2, G.C.JOKER_GREY)
    local action_nodes = {}
    for _, action in ipairs(args.actions or {}) do
        action_nodes[#action_nodes + 1] = compact_button({
            label = action.label,
            button = action.button,
            ref_table = action.ref_table,
            colour = action.colour,
            minw = action.minw,
            minh = action.minh or 0.5,
            scale = action.scale,
        })
    end

    return {
        n = G.UIT.C,
        config = {
            align = "tm",
            minw = column_width,
            maxw = column_width,
            minh = column_height,
            padding = 0.025,
            r = 0.09,
            colour = G.C.UI.TRANSPARENT_DARK,
        },
        nodes = {
            {
                n = G.UIT.R,
                config = {align = "cm", minh = args.preview_height or 1.22},
                nodes = {preview_node},
            },
            {
                n = G.UIT.R,
                config = {
                    align = "cm",
                    minw = column_width - 0.22,
                    maxw = column_width - 0.22,
                    minh = 0.4,
                },
                nodes = {
                    text_node(
                        args.label or "Unknown",
                        args.label_scale or 0.25,
                        args.colour or G.C.JOKER_GREY,
                        {shadow = true}
                    ),
                },
            },
            {
                n = G.UIT.R,
                config = {align = "cm", minh = 0.55, padding = 0.015},
                nodes = action_nodes,
            },
        },
    }
end

local function empty_gallery_column(column_width, column_height)
    column_width = column_width or 1.92
    return {
        n = G.UIT.C,
        config = {
            align = "cm",
            minw = column_width,
            maxw = column_width,
            minh = column_height or 2.15,
        },
        nodes = {},
    }
end

local function joker_gallery_column(card, index)
    return gallery_column({
        source = card,
        label = tostring(index) .. ". " .. joker_name(card),
        colour = joker_rarity_colour(card),
        actions = {
            {
                label = "EDIT",
                button = "balalaio_edit_joker",
                ref_table = {card = card},
                colour = G.C.BLUE,
                minw = 0.76,
                scale = 0.21,
            },
            {
                label = "REMOVE",
                button = "balalaio_remove_joker",
                ref_table = {card = card},
                colour = G.C.RED,
                minw = 1.02,
                scale = 0.17,
            },
        },
    })
end

function Balalaio.create_jokers()
    local cards = G.jokers.cards
    local pages = page_count(#cards, JOKERS_PER_PAGE)
    Balalaio.state.joker_page = clamp(Balalaio.state.joker_page, 1, pages)

    local page = Balalaio.state.joker_page
    local first = (page - 1) * JOKERS_PER_PAGE + 1
    local last = math.min(#cards, first + JOKERS_PER_PAGE - 1)
    local rows = {
        {
            n = G.UIT.R,
            config = {align = "cm", minw = 9.7, minh = 0.32},
            nodes = {
                text_node(
                    "HOVER OR PRESS A CARD FOR LIVE DETAILS",
                    0.24,
                    G.C.JOKER_GREY,
                    {shadow = true}
                ),
            },
        },
    }

    if #cards == 0 then
        rows[#rows + 1] = {
            n = G.UIT.R,
            config = {align = "cm", minw = 9.7, minh = 3.23},
            nodes = {
                text_node(
                    "No Jokers obtained yet. Add one below.",
                    0.38,
                    G.C.JOKER_GREY
                ),
            },
        }
    else
        local columns = {}
        local card_count = last - first + 1
        local leading_empty =
            math.floor((JOKERS_PER_PAGE - card_count) / 2)
        for _ = 1, leading_empty do
            columns[#columns + 1] = empty_gallery_column()
        end
        for index = first, last do
            columns[#columns + 1] =
                joker_gallery_column(cards[index], index)
        end
        while #columns < JOKERS_PER_PAGE do
            columns[#columns + 1] = empty_gallery_column()
        end
        rows[#rows + 1] = {
            n = G.UIT.R,
            config = {
                align = "tm",
                minw = 9.7,
                minh = 2.2,
                padding = 0.025,
            },
            nodes = columns,
        }
    end

    rows[#rows + 1] = page_controls("jokers", page, pages)
    rows[#rows + 1] = {
        n = G.UIT.R,
        config = {align = "cm", minh = 0.68},
        nodes = {
            compact_button({
                label = "+ ADD JOKER",
                button = "balalaio_open_picker",
                ref_table = {return_view = "jokers"},
                colour = G.C.GREEN,
                minw = 4.0,
                minh = 0.62,
                scale = 0.32,
            }),
        },
    }

    return {
        n = G.UIT.R,
        config = {align = "tm", padding = 0.05, minw = 10.9, minh = 4.55},
        nodes = rows,
    }
end

local function consumable_name(card)
    return (card and card.ability and card.ability.name)
        or (
            card
            and card.config
            and card.config.center
            and card.config.center.name
        )
        or "Unknown Consumable"
end

local function consumable_colour(card_or_center)
    local center = card_or_center
        and card_or_center.config
        and card_or_center.config.center
        or card_or_center
    local set = center and center.set
    return (set and G.C.SECONDARY_SET and G.C.SECONDARY_SET[set])
        or G.C.PURPLE
end

local function playing_card_name(card)
    local value = card and card.base and card.base.value or "?"
    local suit = card and card.base and card.base.suit or "Unknown"
    return tostring(value) .. " of " .. tostring(suit)
end

local function playing_card_colour(card_or_front)
    local suit = card_or_front
        and card_or_front.base
        and card_or_front.base.suit
        or (card_or_front and card_or_front.suit)
    return (suit and G.C.SUITS and G.C.SUITS[suit])
        or G.C.JOKER_GREY
end

local function centered_gallery_columns(
    cards,
    first,
    last,
    per_page,
    build_column
)
    local columns = {}
    local card_count = last >= first and (last - first + 1) or 0
    local leading_empty = math.floor((per_page - card_count) / 2)
    for _ = 1, leading_empty do
        columns[#columns + 1] = empty_gallery_column()
    end
    for index = first, last do
        columns[#columns + 1] = build_column(cards[index], index)
    end
    while #columns < per_page do
        columns[#columns + 1] = empty_gallery_column()
    end
    return columns
end

function Balalaio.create_consumables()
    local cards = G.consumeables.cards
    local pages = page_count(#cards, CONSUMABLES_PER_PAGE)
    Balalaio.state.consumable_page =
        clamp(Balalaio.state.consumable_page, 1, pages)

    local page = Balalaio.state.consumable_page
    local first = (page - 1) * CONSUMABLES_PER_PAGE + 1
    local last = math.min(#cards, first + CONSUMABLES_PER_PAGE - 1)
    local rows = {
        {
            n = G.UIT.R,
            config = {align = "cm", minw = 9.7, minh = 0.32},
            nodes = {
                text_node(
                    "HOVER OR PRESS A CARD FOR LIVE DETAILS",
                    0.24,
                    G.C.JOKER_GREY,
                    {shadow = true}
                ),
            },
        },
    }

    if #cards == 0 then
        rows[#rows + 1] = {
            n = G.UIT.R,
            config = {align = "cm", minw = 9.7, minh = 3.23},
            nodes = {
                text_node(
                    "No consumables held. Add one below.",
                    0.38,
                    G.C.JOKER_GREY
                ),
            },
        }
    else
        rows[#rows + 1] = {
            n = G.UIT.R,
            config = {
                align = "tm",
                minw = 9.7,
                minh = 2.2,
                padding = 0.025,
            },
            nodes = centered_gallery_columns(
                cards,
                first,
                last,
                CONSUMABLES_PER_PAGE,
                function(card, index)
                    return gallery_column({
                        source = card,
                        label = tostring(index) .. ". " .. consumable_name(card),
                        colour = consumable_colour(card),
                        actions = {
                            {
                                label = "EDIT",
                                button = "balalaio_edit_consumable",
                                ref_table = {card = card},
                                colour = G.C.BLUE,
                                minw = 1.42,
                                scale = 0.22,
                            },
                        },
                    })
                end
            ),
        }
    end

    rows[#rows + 1] =
        page_controls("consumables", page, pages)
    rows[#rows + 1] = {
        n = G.UIT.R,
        config = {align = "cm", minh = 0.68},
        nodes = {
            compact_button({
                label = "+ ADD CONSUMABLE",
                button = "balalaio_open_picker",
                ref_table = {
                    kind = "consumable",
                    return_view = "consumables",
                },
                colour = G.C.GREEN,
                minw = 4.0,
                minh = 0.62,
                scale = 0.29,
            }),
        },
    }

    return {
        n = G.UIT.R,
        config = {align = "tm", padding = 0.05, minw = 10.9, minh = 4.55},
        nodes = rows,
    }
end

local function sorted_playing_cards()
    local cards = {}
    for _, card in ipairs(G.playing_cards or {}) do
        if card and not card.REMOVED then cards[#cards + 1] = card end
    end
    table.sort(cards, function(a, b)
        local a_suit = a.base and a.base.suit_nominal or 0
        local b_suit = b.base and b.base.suit_nominal or 0
        if a_suit == b_suit then
            local a_rank = a.base and a.base.nominal or 0
            local b_rank = b.base and b.base.nominal or 0
            if a_rank == b_rank then
                return (a.playing_card or 0) < (b.playing_card or 0)
            end
            return a_rank > b_rank
        end
        return a_suit > b_suit
    end)
    return cards
end

function Balalaio.create_deck()
    local cards = sorted_playing_cards()
    local pages = page_count(#cards, DECK_PER_PAGE)
    Balalaio.state.deck_page = clamp(Balalaio.state.deck_page, 1, pages)

    local page = Balalaio.state.deck_page
    local first = (page - 1) * DECK_PER_PAGE + 1
    local last = math.min(#cards, first + DECK_PER_PAGE - 1)
    local rows = {
        {
            n = G.UIT.R,
            config = {align = "cm", minw = 9.7, minh = 0.32},
            nodes = {
                text_node(
                    "ALL PLAYING CARDS  -  HOVER OR PRESS FOR DETAILS",
                    0.24,
                    G.C.JOKER_GREY,
                    {shadow = true}
                ),
            },
        },
    }

    if #cards == 0 then
        rows[#rows + 1] = {
            n = G.UIT.R,
            config = {align = "cm", minw = 9.7, minh = 3.23},
            nodes = {
                text_node(
                    "The deck has no playing cards. Add one below.",
                    0.36,
                    G.C.JOKER_GREY
                ),
            },
        }
    else
        rows[#rows + 1] = {
            n = G.UIT.R,
            config = {
                align = "tm",
                minw = 9.7,
                minh = 2.2,
                padding = 0.025,
            },
            nodes = centered_gallery_columns(
                cards,
                first,
                last,
                DECK_PER_PAGE,
                function(card, index)
                    return gallery_column({
                        source = card,
                        label = tostring(index) .. ". " .. playing_card_name(card),
                        label_scale = 0.21,
                        colour = playing_card_colour(card),
                        actions = {
                            {
                                label = "EDIT",
                                button = "balalaio_edit_playing_card",
                                ref_table = {card = card},
                                colour = G.C.BLUE,
                                minw = 0.76,
                                scale = 0.21,
                            },
                            {
                                label = "REMOVE",
                                button = "balalaio_remove_playing_card",
                                ref_table = {card = card},
                                colour = G.C.RED,
                                minw = 1.02,
                                scale = 0.17,
                            },
                        },
                    })
                end
            ),
        }
    end

    rows[#rows + 1] = page_controls("deck", page, pages)
    rows[#rows + 1] = {
        n = G.UIT.R,
        config = {align = "cm", minh = 0.68},
        nodes = {
            compact_button({
                label = "+ ADD PLAYING CARD",
                button = "balalaio_open_picker",
                ref_table = {kind = "playing", return_view = "deck"},
                colour = G.C.GREEN,
                minw = 4.0,
                minh = 0.62,
                scale = 0.28,
            }),
        },
    }

    return {
        n = G.UIT.R,
        config = {align = "tm", padding = 0.05, minw = 10.9, minh = 4.55},
        nodes = rows,
    }
end

local function tab_button(label, view, colour)
    local selected = Balalaio.state.view == view
    return compact_button({
        label = label,
        button = "balalaio_change_view",
        ref_table = {view = view},
        colour = selected and colour or G.C.GREY,
        minw = 2.55,
        minh = 0.62,
        scale = label == "CONSUMABLES" and 0.23 or 0.28,
        choice = true,
        chosen = selected,
    })
end

local function modal_header()
    return {
        n = G.UIT.R,
        config = {align = "cm", padding = 0.02, minw = 10.9},
        nodes = {
            text_node("BALALAIO", 0.58, G.C.ORANGE, {shadow = true}),
            {
                n = G.UIT.C,
                config = {align = "br", minw = 1.6},
                nodes = {
                    text_node("v" .. Balalaio.VERSION, 0.22, G.C.JOKER_GREY),
                },
            },
        },
    }
end

local function modal_tabs()
    return {
        n = G.UIT.R,
        config = {align = "cm", padding = 0.05},
        nodes = {
            tab_button("GENERAL", "general", G.C.BLUE),
            tab_button("JOKERS", "jokers", G.C.PURPLE),
            tab_button(
                "CONSUMABLES",
                "consumables",
                G.C.SECONDARY_SET.Tarot
            ),
            tab_button("DECK", "deck", G.C.ORANGE),
        },
    }
end

local function status_row()
    return {
        n = G.UIT.R,
        config = {align = "cm", minw = 10.4, minh = 0.35},
        nodes = {
            live_text_node(Balalaio.ui, "status", 0.25, G.C.JOKER_GREY),
        },
    }
end

function Balalaio.create_main_modal()
    local body = nil
    if Balalaio.state.view == "jokers" then
        body = Balalaio.create_jokers()
    elseif Balalaio.state.view == "consumables" then
        body = Balalaio.create_consumables()
    elseif Balalaio.state.view == "deck" then
        body = Balalaio.create_deck()
    else
        body = Balalaio.create_general()
    end

    return create_UIBox_generic_options({
        minw = 11.35,
        padding = 0.08,
        back_label = "RESUME",
        back_colour = G.C.ORANGE,
        contents = {
            modal_header(),
            modal_tabs(),
            body,
            status_row(),
        },
    })
end

function Balalaio.open(view)
    if not Balalaio.run_ready() then
        set_status("Start or continue a run first.")
        return
    end

    Balalaio.remove_float_button()
    Balalaio.state.view = view or Balalaio.state.view or "general"
    G.SETTINGS.paused = true
    G.FUNCS.overlay_menu({
        definition = Balalaio.create_main_modal(),
        config = {offset = {x = 0, y = 0}},
    })
end

function Balalaio.open_picker(kind)
    if not Balalaio.run_ready() then return end
    if kind then Balalaio.state.picker_kind = kind end
    G.SETTINGS.paused = true
    G.FUNCS.overlay_menu({
        definition = Balalaio.create_picker_modal(),
        config = {offset = {x = 0, y = 0}},
    })
end

local function sorted_consumable_centers()
    local result = {}
    local seen = {}
    local sets = {"Tarot", "Planet", "Spectral"}
    for _, set in ipairs(sets) do
        local pool = G.P_CENTER_POOLS and G.P_CENTER_POOLS[set] or {}
        for _, center in ipairs(pool) do
            if center and center.key and not seen[center.key] then
                result[#result + 1] = center
                seen[center.key] = true
            end
        end
    end
    if #result == 0 then
        for _, center in pairs(G.P_CENTERS or {}) do
            if center
                and center.key
                and (
                    center.set == "Tarot"
                    or center.set == "Planet"
                    or center.set == "Spectral"
                )
                and not seen[center.key]
            then
                result[#result + 1] = center
                seen[center.key] = true
            end
        end
    end
    local set_order = {Tarot = 1, Planet = 2, Spectral = 3}
    table.sort(result, function(a, b)
        local a_set = set_order[a.set] or 99
        local b_set = set_order[b.set] or 99
        if a_set ~= b_set then return a_set < b_set end
        local a_order = a.order or 9999
        local b_order = b.order or 9999
        if a_order ~= b_order then return a_order < b_order end
        return (a.name or a.key) < (b.name or b.key)
    end)
    return result
end

local function sorted_playing_fronts()
    local result = {}
    for key, front in pairs(G.P_CARDS or {}) do
        if key ~= "empty"
            and front
            and front.suit
            and front.value
        then
            result[#result + 1] = {key = key, front = front}
        end
    end
    table.sort(result, function(a, b)
        local a_suit = SMODS
            and SMODS.Suits
            and SMODS.Suits[a.front.suit]
        local b_suit = SMODS
            and SMODS.Suits
            and SMODS.Suits[b.front.suit]
        local a_suit_order = a_suit and a_suit.suit_nominal or 0
        local b_suit_order = b_suit and b_suit.suit_nominal or 0
        if a_suit_order ~= b_suit_order then
            return a_suit_order > b_suit_order
        end
        local a_rank = SMODS
            and SMODS.Ranks
            and SMODS.Ranks[a.front.value]
        local b_rank = SMODS
            and SMODS.Ranks
            and SMODS.Ranks[b.front.value]
        local a_rank_order = a_rank and a_rank.nominal or 0
        local b_rank_order = b_rank and b_rank.nominal or 0
        if a_rank_order ~= b_rank_order then
            return a_rank_order > b_rank_order
        end
        return a.key < b.key
    end)
    return result
end

local function picker_current_filter()
    local kind = Balalaio.state.picker_kind
    if kind == "consumable" then
        return Balalaio.state.picker_consumable_set
    elseif kind == "playing" then
        return Balalaio.state.picker_suit
    end
    return Balalaio.state.picker_rarity
end

local function picker_filter_button(label, value, colour, width)
    local selected = picker_current_filter() == value
    return compact_button({
        label = label,
        button = "balalaio_picker_filter",
        ref_table = {
            kind = Balalaio.state.picker_kind,
            value = value,
        },
        colour = selected and colour or G.C.GREY,
        minw = width or 1.75,
        minh = 0.52,
        scale = 0.23,
        choice = true,
        chosen = selected,
    })
end

local function picker_filter_nodes()
    local kind = Balalaio.state.picker_kind
    if kind == "consumable" then
        return {
            picker_filter_button("ALL", "All", G.C.BLUE, 1.35),
            picker_filter_button(
                "TAROT",
                "Tarot",
                G.C.SECONDARY_SET.Tarot,
                2.0
            ),
            picker_filter_button(
                "PLANET",
                "Planet",
                G.C.SECONDARY_SET.Planet,
                2.0
            ),
            picker_filter_button(
                "SPECTRAL",
                "Spectral",
                G.C.SECONDARY_SET.Spectral,
                2.0
            ),
        }
    elseif kind == "playing" then
        return {
            picker_filter_button("ALL", "All", G.C.BLUE, 1.2),
            picker_filter_button(
                "SPADES",
                "Spades",
                G.C.SUITS.Spades,
                1.85
            ),
            picker_filter_button(
                "HEARTS",
                "Hearts",
                G.C.SUITS.Hearts,
                1.85
            ),
            picker_filter_button(
                "CLUBS",
                "Clubs",
                G.C.SUITS.Clubs,
                1.85
            ),
            picker_filter_button(
                "DIAMONDS",
                "Diamonds",
                G.C.SUITS.Diamonds,
                1.85
            ),
        }
    end
    return {
        picker_filter_button("ALL", 0, G.C.BLUE, 1.25),
        picker_filter_button("COMMON", 1, G.C.RARITY[1], 1.75),
        picker_filter_button("UNCOMMON", 2, G.C.RARITY[2], 1.75),
        picker_filter_button("RARE", 3, G.C.RARITY[3], 1.75),
        picker_filter_button("LEGENDARY", 4, G.C.RARITY[4], 1.75),
    }
end

local function filtered_picker_items()
    local result = {}
    local kind = Balalaio.state.picker_kind
    if kind == "consumable" then
        for _, center in ipairs(sorted_consumable_centers()) do
            if Balalaio.state.picker_consumable_set == "All"
                or center.set == Balalaio.state.picker_consumable_set
            then
                result[#result + 1] = {
                    center = center,
                    label = center.name or center.key,
                    colour = consumable_colour(center),
                    center_key = center.key,
                }
            end
        end
    elseif kind == "playing" then
        for _, descriptor in ipairs(sorted_playing_fronts()) do
            local front = descriptor.front
            if Balalaio.state.picker_suit == "All"
                or front.suit == Balalaio.state.picker_suit
            then
                result[#result + 1] = {
                    center = G.P_CENTERS.c_base,
                    front = front,
                    front_key = descriptor.key,
                    label = tostring(front.value)
                        .. " of "
                        .. tostring(front.suit),
                    colour = playing_card_colour(front),
                }
            end
        end
    else
        for _, center in ipairs(sorted_joker_centers()) do
            if Balalaio.state.picker_rarity == 0
                or center.rarity == Balalaio.state.picker_rarity
            then
                result[#result + 1] = {
                    center = center,
                    label = center.name or center.key,
                    colour = G.C.RARITY[center.rarity] or G.C.PURPLE,
                    center_key = center.key,
                }
            end
        end
    end
    return result
end

local function picker_gallery_column(item)
    return gallery_column({
        center = item.center,
        front = item.front,
        preview_scale = PICKER_PREVIEW_SCALE,
        label = item.label or "Unknown",
        label_scale = 0.22,
        colour = item.colour,
        actions = {
            {
                label = "ADD",
                button = "balalaio_add_picker_card",
                ref_table = {
                    kind = Balalaio.state.picker_kind,
                    center_key = item.center_key,
                    front_key = item.front_key,
                },
                colour = G.C.GREEN,
                minw = 1.4,
                scale = 0.22,
            },
        },
    })
end

function Balalaio.create_picker_modal()
    local items = filtered_picker_items()
    local pages = page_count(#items, PICKER_PER_PAGE)
    Balalaio.state.picker_page =
        clamp(Balalaio.state.picker_page, 1, pages)

    local page = Balalaio.state.picker_page
    local first = (page - 1) * PICKER_PER_PAGE + 1
    local last = math.min(#items, first + PICKER_PER_PAGE - 1)
    local kind = Balalaio.state.picker_kind
    local title = kind == "consumable"
        and "ADD A CONSUMABLE"
        or (kind == "playing" and "ADD A PLAYING CARD" or "ADD A JOKER")
    local title_colour = kind == "consumable"
        and G.C.SECONDARY_SET.Tarot
        or (kind == "playing" and G.C.ORANGE or G.C.PURPLE)
    local rows = {
        {
            n = G.UIT.R,
            config = {align = "cm", minw = 10.8},
            nodes = {
                text_node(title, 0.5, title_colour, {shadow = true}),
            },
        },
        {
            n = G.UIT.R,
            config = {align = "cm", padding = 0.035},
            nodes = picker_filter_nodes(),
        },
        {
            n = G.UIT.R,
            config = {align = "cm", minw = 9.7, minh = 0.3},
            nodes = {
                text_node(
                    "HOVER OR PRESS FOR DETAILS; USE ADD TO CHOOSE",
                    0.23,
                    G.C.JOKER_GREY
                ),
            },
        },
    }

    if #items == 0 then
        rows[#rows + 1] = {
            n = G.UIT.R,
            config = {align = "cm", minw = 9.7, minh = 2.2},
            nodes = {
                text_node("No cards match this filter.", 0.35, G.C.JOKER_GREY),
            },
        }
    else
        rows[#rows + 1] = {
            n = G.UIT.R,
            config = {
                align = "tm",
                minw = 9.7,
                minh = 2.2,
                padding = 0.025,
            },
            nodes = centered_gallery_columns(
                items,
                first,
                last,
                PICKER_PER_PAGE,
                function(item)
                    return picker_gallery_column(item)
                end
            ),
        }
    end

    rows[#rows + 1] = page_controls("picker", page, pages)
    rows[#rows + 1] = status_row()

    return create_UIBox_generic_options({
        minw = 11.2,
        padding = 0.08,
        back_label = "BACK",
        back_func = "balalaio_picker_back",
        back_colour = G.C.ORANGE,
        contents = rows,
    })
end

local function current_edition_index(card)
    if not card or not card.edition then return 1 end
    if card.edition.foil then return 2 end
    if card.edition.holo then return 3 end
    if card.edition.polychrome then return 4 end
    if card.edition.negative then return 5 end
    return 1
end

local function current_edition_label(card)
    return EDITIONS[current_edition_index(card)].label
end

local function edition_choices(kind)
    return kind == "playing" and PLAYING_CARD_EDITIONS or EDITIONS
end

local function current_edition_choice_index(card, choices)
    local current = EDITIONS[current_edition_index(card)]
    for index, choice in ipairs(choices) do
        if choice == current then return index end
    end
    return 1
end

local function include_numeric_modifier(card, root_name, path, key, value)
    if key == "order" then return false end
    if key == "mod_num"
        and card
        and card.ability
        and type(card.ability.consumeable) == "table"
    then
        return false
    end
    if root_name == "edition" then return true end
    if #path > 1 then return true end

    local default = DEFAULT_ABILITY_NUMBERS[key]
    if default == nil then return true end
    if value ~= default then return true end

    local center_config = card
        and card.config
        and card.config.center
        and card.config.center.config
        or {}
    local config_key = CENTER_CONFIG_KEYS[key] or key
    return center_config[config_key] ~= nil
        or (config_key ~= key and center_config[key] ~= nil)
end

local function modifier_label(root_name, path)
    local pieces = {}
    if root_name == "edition" then pieces[#pieces + 1] = "edition" end
    for _, part in ipairs(path) do
        pieces[#pieces + 1] = tostring(part):gsub("_", " ")
    end
    return table.concat(pieces, ".")
end

local function value_at_path(root, path, map_first_key)
    local current = root
    for index, key in ipairs(path) do
        if type(current) ~= "table" then return nil end
        local lookup_key = key
        if index == 1 and map_first_key then
            lookup_key = CENTER_CONFIG_KEYS[key] or key
        end
        current = current[lookup_key]
    end
    return current
end

local function modifier_default(card, root_name, path)
    if root_name == "ability" then
        local center_config = card
            and card.config
            and card.config.center
            and card.config.center.config
        local value = value_at_path(center_config, path, true)
        if type(value) ~= "number"
            and path
            and path[1] == "x_mult"
        then
            value = value_at_path(center_config, path, false)
        end
        if type(value) == "number" then return value end
    elseif root_name == "edition"
        and card
        and card.edition
        and card.edition.type
        and G.P_CENTERS
    then
        local center = G.P_CENTERS["e_" .. tostring(card.edition.type)]
        local config = center and center.config
        local value = value_at_path(config, path, false)
        if type(value) ~= "number" then
            value = config and config.extra
        end
        if type(value) == "number" then return value end
    end
    return nil
end

local function modifier_step(default)
    if type(default) ~= "number" then return 1 end
    if math.abs(default - math.floor(default)) < 0.000000001 then return 1 end
    local step = math.abs(default)
    return step > 0 and step or 1
end

local function decimal_precision(value)
    if type(value) ~= "number" then return 0 end
    local text = string.format("%.10f", math.abs(value))
    text = text:gsub("0+$", "")
    local decimal = text:match("%.(%d+)$")
    return decimal and math.min(#decimal, 8) or 0
end

local function round_decimal(value, precision)
    if not precision or precision <= 0 then return value end
    local factor = 10 ^ math.min(precision, 8)
    if value >= 0 then
        return math.floor(value * factor + 0.5) / factor
    end
    return math.ceil(value * factor - 0.5) / factor
end

local function collect_from_table(card, root_name, current, path, entries, seen, depth)
    if type(current) ~= "table" or seen[current] or depth > 4 then return end
    seen[current] = true

    local keys = {}
    for key, _ in pairs(current) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)

    for _, key in ipairs(keys) do
        local value = current[key]
        local next_path = shallow_copy(path)
        next_path[#next_path + 1] = key
        if type(value) == "number"
            and include_numeric_modifier(card, root_name, next_path, key, value)
        then
            local default = modifier_default(card, root_name, next_path)
            entries[#entries + 1] = {
                card = card,
                root = root_name,
                parent = current,
                key = key,
                path = next_path,
                label = modifier_label(root_name, next_path),
                display = format_number(value),
                default = default,
                step = modifier_step(default),
            }
        elseif type(value) == "table"
            and not (
                root_name == "ability"
                and #path == 0
                and key == "consumeable"
            )
        then
            collect_from_table(
                card,
                root_name,
                value,
                next_path,
                entries,
                seen,
                depth + 1
            )
        end
    end
end

function Balalaio.collect_modifiers(card)
    local entries = {}
    local seen = {}
    if card and card.ability then
        collect_from_table(card, "ability", card.ability, {}, entries, seen, 0)
    end
    if card and card.edition then
        collect_from_table(card, "edition", card.edition, {}, entries, seen, 0)
    end
    table.sort(entries, function(a, b) return a.label < b.label end)
    return entries
end

local function flag_button(card, label, key, colour)
    local active = card.ability and not not card.ability[key]
    return compact_button({
        label = label,
        button = "balalaio_toggle_flag",
        ref_table = {card = card, key = key},
        colour = active and colour or G.C.GREY,
        minw = 2.3,
        minh = 0.54,
        scale = 0.26,
        choice = true,
        chosen = active,
    })
end

local function modifier_row(entry)
    local label = entry.label
    if entry.step and entry.step ~= 1 then
        label = label .. "  (step " .. format_number(entry.step) .. ")"
    end
    return {
        n = G.UIT.R,
        config = {
            align = "cm",
            minw = 9.8,
            minh = 0.64,
            padding = 0.025,
            r = 0.08,
            colour = G.C.UI.TRANSPARENT_DARK,
        },
        nodes = {
            {
                n = G.UIT.C,
                config = {align = "cl", minw = 5.8, maxw = 5.8},
                nodes = {text_node(label, 0.29, G.C.JOKER_GREY)},
            },
            compact_button({
                label = "-",
                button = "balalaio_adjust_modifier",
                ref_table = {entry = entry, delta = -1},
                colour = G.C.RED,
                minw = 0.7,
                hold_repeat = true,
            }),
            {
                n = G.UIT.C,
                config = {align = "cm", minw = 1.2, maxw = 1.2},
                nodes = {live_text_node(entry, "display", 0.35, G.C.ORANGE)},
            },
            compact_button({
                label = "+",
                button = "balalaio_adjust_modifier",
                ref_table = {entry = entry, delta = 1},
                colour = G.C.GREEN,
                minw = 0.7,
                hold_repeat = true,
            }),
        },
    }
end

local function edition_row(card, editor_kind)
    return {
        n = G.UIT.R,
        config = {align = "cm", padding = 0.035},
        nodes = {
            {
                n = G.UIT.C,
                config = {align = "cl", minw = 3.0},
                nodes = {text_node("Edition", 0.32, G.C.JOKER_GREY)},
            },
            compact_button({
                label = "<",
                button = "balalaio_cycle_edition",
                ref_table = {
                    card = card,
                    kind = editor_kind,
                    delta = -1,
                },
                colour = G.C.PURPLE,
                minw = 0.7,
            }),
            {
                n = G.UIT.C,
                config = {align = "cm", minw = 3.2, maxw = 3.2},
                nodes = {
                    text_node(
                        current_edition_label(card),
                        0.33,
                        G.C.SECONDARY_SET.Edition,
                        {shadow = true}
                    ),
                },
            },
            compact_button({
                label = ">",
                button = "balalaio_cycle_edition",
                ref_table = {
                    card = card,
                    kind = editor_kind,
                    delta = 1,
                },
                colour = G.C.PURPLE,
                minw = 0.7,
            }),
        },
    }
end

local function card_in_list(card, cards)
    for _, candidate in ipairs(cards or {}) do
        if candidate == card then return true end
    end
    return false
end

local function editor_card_available(card, kind)
    if not card
        or card.REMOVED
        or card.getting_sliced
        or card.destroyed
        or card.shattered
    then
        return false
    end
    if kind == "consumable" then
        return G.consumeables
            and card_in_list(card, G.consumeables.cards)
    elseif kind == "playing" then
        return card.playing_card
            and card.area
            and not (G.play and card.area == G.play)
            and card_in_list(card, G.playing_cards)
    end
    return G.jokers and card_in_list(card, G.jokers.cards)
end

local function detached_consumable_config(card)
    if not card
        or not card.ability
        or not G.consumeables
        or not card_in_list(card, G.consumeables.cards)
    then
        return nil
    end
    local center_config = card.config
        and card.config.center
        and card.config.center.config
    if type(center_config) ~= "table" then return nil end

    local current = card.ability.consumeable
    if current == center_config or type(current) ~= "table" then
        current = copy_visual_value(
            type(current) == "table" and current or center_config
        )
        card.ability.consumeable = current
    end
    return current, center_config
end

local function mirror_consumable_modifier(card, entry, value)
    if not entry or entry.root ~= "ability" then return end
    local center_config = card
        and card.config
        and card.config.center
        and card.config.center.config
    if type(center_config) ~= "table"
        or type(value_at_path(center_config, entry.path, false)) ~= "number"
    then
        return
    end
    local config = detached_consumable_config(card)
    if not config then return end

    -- Native consumables read selection limits and counts through
    -- ability.consumeable, while many Steamodded effects read the copied
    -- top-level ability path. Mirror only paths originating in center.config
    -- so both consumers observe the same per-card edit without touching the
    -- shared center definition.
    local parent = config
    for index = 1, #entry.path - 1 do
        parent = type(parent) == "table" and parent[entry.path[index]] or nil
        if type(parent) ~= "table" then return end
    end
    parent[entry.path[#entry.path]] = value
end

function Balalaio.create_editor_modal(card, kind)
    kind = kind or Balalaio.state.editor_kind or "joker"
    local entries = Balalaio.collect_modifiers(card)
    local pages = page_count(#entries, MODIFIERS_PER_PAGE)
    Balalaio.state.modifier_page =
        clamp(Balalaio.state.modifier_page, 1, pages)

    local page = Balalaio.state.modifier_page
    local first = (page - 1) * MODIFIERS_PER_PAGE + 1
    local last = math.min(#entries, first + MODIFIERS_PER_PAGE - 1)
    local is_consumable = kind == "consumable"
    local card_name = is_consumable and consumable_name(card) or joker_name(card)
    local card_colour = is_consumable
        and consumable_colour(card)
        or joker_rarity_colour(card)
    local rows = {
        {
            n = G.UIT.R,
            config = {align = "cm", minw = 10.7},
            nodes = {
                text_node(card_name, 0.5, card_colour, {shadow = true}),
            },
        },
        edition_row(card, kind),
    }

    if kind == "joker" then
        rows[#rows + 1] = {
            n = G.UIT.R,
            config = {align = "cm", padding = 0.035},
            nodes = {
                flag_button(card, "ETERNAL", "eternal", G.C.ETERNAL),
                flag_button(card, "PERISHABLE", "perishable", G.C.PERISHABLE),
                flag_button(card, "RENTAL", "rental", G.C.RENTAL),
            },
        }
    end

    rows[#rows + 1] = {
        n = G.UIT.R,
        config = {align = "cl", minw = 9.8, minh = 0.35},
        nodes = {
            text_node(
                "INSTANCE VALUES  (PER-STAT STEP; HOLD +/- TO REPEAT)",
                0.27,
                G.C.ORANGE,
                {shadow = true}
            ),
        },
    }

    if #entries == 0 then
        rows[#rows + 1] = {
            n = G.UIT.R,
            config = {align = "cm", minw = 9.8, minh = 3.2},
            nodes = {
                text_node(
                    "This card has no numeric instance values.",
                    0.34,
                    G.C.JOKER_GREY
                ),
            },
        }
    else
        local displayed = 0
        for index = first, last do
            rows[#rows + 1] = modifier_row(entries[index])
            displayed = displayed + 1
        end
        while displayed < MODIFIERS_PER_PAGE do
            rows[#rows + 1] = {
                n = G.UIT.R,
                config = {align = "cm", minw = 9.8, minh = 0.64},
                nodes = {},
            }
            displayed = displayed + 1
        end
    end

    rows[#rows + 1] = page_controls("modifiers", page, pages)
    rows[#rows + 1] = status_row()

    return create_UIBox_generic_options({
        minw = 11.2,
        padding = 0.08,
        back_label = is_consumable and "CONSUMABLES" or "JOKERS",
        back_func = is_consumable
            and "balalaio_back_to_consumables"
            or "balalaio_back_to_jokers",
        back_colour = G.C.ORANGE,
        contents = rows,
    })
end

local function playing_front_for(suit, rank)
    for _, front in pairs(G.P_CARDS or {}) do
        if front and front.suit == suit and front.value == rank then
            return front
        end
    end
    return nil
end

local function option_index(options, value)
    for index, option in ipairs(options) do
        if option.key == value then return index end
    end
    return 1
end

local function object_label(object, fallback)
    if not object then return tostring(fallback or "Unknown") end
    if type(object.name) == "string" then return object.name end
    if object.loc_txt and type(object.loc_txt.name) == "string" then
        return object.loc_txt.name
    end
    return tostring(fallback or object.key or "Unknown")
end

local function playing_property_options(card, property)
    local options = {}
    local seen = {}
    if property == "suit" or property == "rank" then
        for _, descriptor in ipairs(sorted_playing_fronts()) do
            local front = descriptor.front
            local key = property == "suit" and front.suit or front.value
            local compatible = property == "suit"
                and front.value == card.base.value
                or (property == "rank" and front.suit == card.base.suit)
            if compatible and not seen[key] then
                options[#options + 1] = {
                    key = key,
                    label = tostring(key),
                    order = property == "suit"
                        and (
                            SMODS
                            and SMODS.Suits
                            and SMODS.Suits[key]
                            and SMODS.Suits[key].suit_nominal
                            or front.suit_nominal
                            or 0
                        )
                        or (
                            SMODS
                            and SMODS.Ranks
                            and SMODS.Ranks[key]
                            and SMODS.Ranks[key].nominal
                            or front.nominal
                            or 0
                        ),
                }
                seen[key] = true
            end
        end
        table.sort(options, function(a, b)
            if a.order ~= b.order then return a.order < b.order end
            return tostring(a.key) < tostring(b.key)
        end)
    elseif property == "enhancement" then
        local base = G.P_CENTERS and G.P_CENTERS.c_base
        options[#options + 1] = {
            key = base and base.key or "c_base",
            label = "Base",
            center = base,
        }
        seen[options[1].key] = true
        for _, center in ipairs(
            G.P_CENTER_POOLS and G.P_CENTER_POOLS.Enhanced or {}
        ) do
            if center and center.key and not seen[center.key] then
                options[#options + 1] = {
                    key = center.key,
                    label = object_label(center, center.key),
                    center = center,
                }
                seen[center.key] = true
            end
        end
    elseif property == "seal" then
        options[#options + 1] = {key = false, label = "None"}
        for key, seal in pairs(G.P_SEALS or {}) do
            options[#options + 1] = {
                key = key,
                label = object_label(seal, key),
                order = seal.order or 9999,
            }
        end
        table.sort(options, function(a, b)
            if a.key == false then return true end
            if b.key == false then return false end
            if (a.order or 9999) ~= (b.order or 9999) then
                return (a.order or 9999) < (b.order or 9999)
            end
            return tostring(a.key) < tostring(b.key)
        end)
    end
    return options
end

local function current_playing_property(card, property)
    if property == "suit" then return card.base and card.base.suit end
    if property == "rank" then return card.base and card.base.value end
    if property == "enhancement" then
        return card.config
            and card.config.center
            and card.config.center.key
            or "c_base"
    end
    if property == "seal" then return card.seal or false end
    return nil
end

local function playing_property_row(card, label, property, colour)
    local options = playing_property_options(card, property)
    local current = current_playing_property(card, property)
    local current_option = options[option_index(options, current)] or {}
    return {
        n = G.UIT.R,
        config = {
            align = "cm",
            minw = 9.8,
            minh = 0.66,
            padding = 0.025,
            r = 0.08,
            colour = G.C.UI.TRANSPARENT_DARK,
        },
        nodes = {
            {
                n = G.UIT.C,
                config = {align = "cl", minw = 3.0},
                nodes = {text_node(label, 0.32, G.C.JOKER_GREY)},
            },
            compact_button({
                label = "<",
                button = "balalaio_cycle_deck_property",
                ref_table = {card = card, property = property, delta = -1},
                colour = colour,
                minw = 0.7,
            }),
            {
                n = G.UIT.C,
                config = {align = "cm", minw = 3.2, maxw = 3.2},
                nodes = {
                    text_node(
                        current_option.label or tostring(current or "Unknown"),
                        0.31,
                        colour,
                        {shadow = true}
                    ),
                },
            },
            compact_button({
                label = ">",
                button = "balalaio_cycle_deck_property",
                ref_table = {card = card, property = property, delta = 1},
                colour = colour,
                minw = 0.7,
            }),
        },
    }
end

function Balalaio.create_deck_editor_modal(card)
    local enhancement_colour = (
        G.C.SECONDARY_SET and G.C.SECONDARY_SET.Enhanced
    ) or G.C.PURPLE
    return create_UIBox_generic_options({
        minw = 11.2,
        padding = 0.08,
        back_label = "DECK",
        back_func = "balalaio_back_to_deck",
        back_colour = G.C.ORANGE,
        contents = {
            {
                n = G.UIT.R,
                config = {align = "cm", minw = 10.7, minh = 0.6},
                nodes = {
                    text_node(
                        playing_card_name(card),
                        0.5,
                        playing_card_colour(card),
                        {shadow = true}
                    ),
                },
            },
            playing_property_row(
                card,
                "Suit",
                "suit",
                playing_card_colour(card)
            ),
            playing_property_row(card, "Rank", "rank", G.C.ORANGE),
            playing_property_row(
                card,
                "Enhancement",
                "enhancement",
                enhancement_colour
            ),
            edition_row(card, "playing"),
            playing_property_row(card, "Seal", "seal", G.C.GOLD),
            {
                n = G.UIT.R,
                config = {align = "cm", minw = 10.4, minh = 0.35},
                nodes = {
                    text_node(
                        "Native setters preserve card effects and mod hooks.",
                        0.24,
                        G.C.JOKER_GREY
                    ),
                },
            },
            status_row(),
        },
    })
end

local function cycle_playing_property_now(card, property, delta)
    if not editor_card_available(card, "playing") then return false end
    local options = playing_property_options(card, property)
    if #options < 1 then return false end
    local current = current_playing_property(card, property)
    local new_index = ((option_index(options, current) - 1 + delta) % #options) + 1
    local selected = options[new_index]

    if property == "suit" or property == "rank" then
        local suit = property == "suit" and selected.key or card.base.suit
        local rank = property == "rank" and selected.key or card.base.value
        local front = playing_front_for(suit, rank)
        if not front then return false end
        if SMODS and type(SMODS.change_base) == "function" then
            if SMODS.change_base(card, suit, rank) == false then return false end
        elseif card.set_base then
            card:set_base(front)
        else
            return false
        end
    elseif property == "enhancement" then
        local center = selected.center
            or (G.P_CENTERS and G.P_CENTERS[selected.key])
        if not center or not card.set_ability then return false end
        card:set_ability(center, nil, true)
    elseif property == "seal" then
        if not card.set_seal then return false end
        card:set_seal(selected.key or nil, true, true)
    else
        return false
    end
    if card.set_cost then card:set_cost() end
    return true
end

function Balalaio.open_editor(card, kind)
    kind = kind or Balalaio.state.editor_kind or "joker"
    local return_view = kind == "consumable" and "consumables"
        or (kind == "playing" and "deck" or "jokers")
    if not editor_card_available(card, kind) then
        set_status("That card is no longer safe to edit.")
        Balalaio.open(return_view)
        return
    end
    Balalaio.state.editor_kind = kind
    Balalaio.state.selected_card = card
    if kind == "joker" then Balalaio.state.selected_joker = card end
    G.SETTINGS.paused = true
    G.FUNCS.overlay_menu({
        definition = kind == "playing"
            and Balalaio.create_deck_editor_modal(card)
            or Balalaio.create_editor_modal(card, kind),
        config = {offset = {x = 0, y = 0}},
    })
end

local function set_edition_now(card, edition)
    if card.ability then card.ability.queue_negative_removal = nil end
    card:set_edition(edition.value, true, true)

    if card.set_cost then card:set_cost() end
end

local function toggle_flag_now(card, key)
    if not card.ability then return end
    if key == "eternal" then
        local enabled = not card.ability.eternal
        card.ability.eternal = enabled or nil
        if enabled then
            card.ability.perishable = nil
            card.ability.perish_tally = nil
        end
    elseif key == "perishable" then
        local enabled = not card.ability.perishable
        card.ability.perishable = enabled or nil
        if enabled then
            card.ability.eternal = nil
            card.ability.perish_tally = G.GAME.perishable_rounds or 5
        else
            card.ability.perish_tally = nil
        end
    elseif key == "rental" then
        if card.set_rental then
            card:set_rental(not card.ability.rental)
        else
            card.ability.rental = not card.ability.rental or nil
        end
    end
end

local function adjust_modifier_now(entry, delta)
    if not entry
        or not entry.card
        or entry.card.REMOVED
        or type(entry.parent[entry.key]) ~= "number"
    then
        return false
    end

    local card = entry.card
    local was_added = card.added_to_deck
    if was_added and card.remove_from_deck then card:remove_from_deck(true) end

    local current = entry.parent[entry.key]
    local step = type(entry.step) == "number" and entry.step or 1
    local precision = math.max(
        decimal_precision(current),
        decimal_precision(step)
    )
    entry.parent[entry.key] =
        round_decimal(current + delta * step, precision)
    mirror_consumable_modifier(
        card,
        entry,
        entry.parent[entry.key]
    )
    entry.display = format_number(entry.parent[entry.key])

    if was_added and card.add_to_deck then card:add_to_deck(true) end
    if card.set_cost then card:set_cost() end
    return true
end

local function repeat_owner(target)
    local current = target
    local seen = {}
    for _ = 1, 8 do
        if not current or seen[current] then return nil end
        seen[current] = true
        if current.config and current.config.hold_repeat then
            return current
        end
        current = current.config and current.config.button_UIE or nil
    end
    return nil
end

local function repeat_time()
    if G and G.TIMERS then
        return G.TIMERS.REAL or G.TIMERS.UPTIME or G.TIMERS.TOTAL or 0
    end
    return os.clock()
end

local function clear_hold_repeat()
    local state = Balalaio.hold_repeat
    if not state then return end

    if state.owner and not state.owner.REMOVED then
        state.owner.disable_button = state.previous_disable
    end
    state.defer_save = false
    flush_repeat_save()
    state.owner = nil
    state.next_at = nil
    state.repeated = false
    state.previous_disable = nil
    state.cancelled = false
end

function Balalaio.update_hold_repeat()
    local state = Balalaio.hold_repeat
    local controller = G and G.CONTROLLER
    if not state or not controller or not controller.is_cursor_down then
        clear_hold_repeat()
        return
    end

    local owner = repeat_owner(
        controller.cursor_down and controller.cursor_down.target
    )
    if not owner
        or owner.REMOVED
        or not owner.config
        or not owner.config.button
        or (owner.states and owner.states.visible == false)
    then
        clear_hold_repeat()
        return
    end

    local now = repeat_time()
    if state.owner ~= owner then
        clear_hold_repeat()
        state.owner = owner
        state.next_at = now + HOLD_REPEAT_DELAY
        state.repeated = false
        state.previous_disable = owner.disable_button
        state.cancelled = false
        return
    end
    if state.cancelled then return end

    local hover_target = controller.cursor_hover
        and controller.cursor_hover.target
    local hover_owner = repeat_owner(hover_target)
    if hover_target and hover_owner ~= owner then
        state.next_at =
            now + (state.repeated and HOLD_REPEAT_INTERVAL or HOLD_REPEAT_DELAY)
        return
    end

    if not state.next_at or now < state.next_at then return end

    if not state.repeated then
        state.repeated = true
        state.defer_save = true
        owner.disable_button = true
    end

    state.next_at = now + HOLD_REPEAT_INTERVAL
    owner.last_clicked = now
    owner.button_clicked = true
    local callback = G.FUNCS and G.FUNCS[owner.config.button]
    if type(callback) ~= "function" then
        state.cancelled = true
        return
    end

    local ok, err = pcall(callback, owner)
    if not ok then
        state.cancelled = true
        set_status("Repeat failed: " .. tostring(err))
    end
end

local function save_float_position()
    local box = Balalaio.float_box
    if not box or box.REMOVED or not G or not G.ROOM then return end
    local max_x = math.max(0.001, G.ROOM.T.w - box.T.w)
    local max_y = math.max(0.001, G.ROOM.T.h - box.T.h)
    G.SETTINGS.BALALAIO_BUTTON = {
        x = clamp(box.T.x / max_x, 0, 1),
        y = clamp(box.T.y / max_y, 0, 1),
    }
    if G.save_settings then pcall(function() G:save_settings() end) end
end

local function translate_float_children(node, dx, dy)
    if not node or (dx == 0 and dy == 0) then return end
    if node.T then
        node.T.x = node.T.x + dx
        node.T.y = node.T.y + dy
    end
    if node.VT then
        node.VT.x = node.VT.x + dx
        node.VT.y = node.VT.y + dy
    end
    for _, child in pairs(node.children or {}) do
        translate_float_children(child, dx, dy)
    end
end

local function set_float_box_position(box, x, y)
    if not box or not G or not G.ROOM then return end
    local max_x = math.max(0, G.ROOM.T.w - box.T.w)
    local max_y = math.max(0, G.ROOM.T.h - box.T.h)
    local next_x = clamp(x, 0, max_x)
    local next_y = clamp(y, 0, max_y)
    local dx = next_x - box.T.x
    local dy = next_y - box.T.y
    box:hard_set_T(next_x, next_y, box.T.w, box.T.h)
    box.NEW_ALIGNMENT = true
    translate_float_children(box.UIRoot, dx, dy)
end

local function clamp_float_box(box)
    if not box then return end
    set_float_box_position(box, box.T.x, box.T.y)
end

local function create_float_definition()
    return {
        n = G.UIT.ROOT,
        config = {
            align = "cm",
            colour = G.C.CLEAR,
            padding = 0,
        },
        nodes = {
            {
                n = G.UIT.R,
                config = {
                    id = "balalaio_float_button",
                    align = "cm",
                    minw = 1.78,
                    maxw = 1.78,
                    minh = 0.7,
                    padding = 0.055,
                    r = 0.14,
                    colour = G.C.DARK_EDITION,
                    outline = 1.2,
                    outline_colour = G.C.ORANGE,
                    hover = true,
                    shadow = true,
                    button = "balalaio_open_menu",
                },
                nodes = {
                    text_node(
                        "BALALAIO " .. Balalaio.VERSION,
                        0.235,
                        G.C.ORANGE,
                        {shadow = true}
                    ),
                },
            },
        },
    }
end

function Balalaio.create_float_button()
    if not Balalaio.run_ready()
        or not UIBox
        or not G.ROOM_ATTACH
        or G.SETTINGS.paused
        or G.OVERLAY_MENU
        or (
            G.CONTROLLER
            and G.CONTROLLER.interrupt
            and G.CONTROLLER.interrupt.focus
        )
        or Balalaio.float_box
    then
        return
    end

    local box = UIBox({
        definition = create_float_definition(),
        config = {
            align = "tri",
            offset = {x = -0.25, y = 0.25},
            major = G.ROOM_ATTACH,
            bond = "Weak",
            instance_type = "POPUP",
        },
    })

    -- POPUPs are drawn after Cards and the first-run tutorial overlay. This
    -- keeps those later full-screen/card-area nodes from stealing the launcher's
    -- touch target while preserving Balatro's native Controller input path.
    box.role.role_type = "Major"
    box.role.major = nil
    box.alignment.type = "a"
    box.alignment.prev_type = "a"
    box.states.drag.can = false

    local saved = G.SETTINGS and G.SETTINGS.BALALAIO_BUTTON
    local max_x = math.max(0, G.ROOM.T.w - box.T.w)
    local max_y = math.max(0, G.ROOM.T.h - box.T.h)
    local x = saved and tonumber(saved.x) and saved.x * max_x
        or math.max(0, max_x - 0.25)
    local y = saved and tonumber(saved.y) and saved.y * max_y or 0.25
    set_float_box_position(box, x, y)

    local button = box:get_UIE_by_ID("balalaio_float_button")
    if button then
        -- The launcher belongs to live gameplay even if it was recreated on the
        -- frame where the platform changed the pause/lifecycle state.
        box.created_on_pause = nil
        box.UIRoot.created_on_pause = nil
        button.created_on_pause = nil
        button.states.drag.can = true
        button.drag = function(node)
            if not G
                or not G.CONTROLLER
                or not G.CONTROLLER.cursor_position
            then
                return
            end

            local cursor_x =
                G.CONTROLLER.cursor_position.x / (G.TILESCALE * G.TILESIZE)
            local cursor_y =
                G.CONTROLLER.cursor_position.y / (G.TILESCALE * G.TILESIZE)

            if not Balalaio.float_drag_offset then
                Balalaio.float_drag_offset = {
                    x = cursor_x - box.T.x,
                    y = cursor_y - box.T.y,
                }
            end

            set_float_box_position(
                box,
                cursor_x - Balalaio.float_drag_offset.x,
                cursor_y - Balalaio.float_drag_offset.y
            )
        end
        button.stop_drag = function(node)
            if Node and Node.stop_drag then Node.stop_drag(node) end
            Balalaio.float_drag_offset = nil
            clamp_float_box(box)
            save_float_position()
        end
    end

    Balalaio.float_box = box
end

function Balalaio.remove_float_button()
    local box = Balalaio.float_box
    Balalaio.float_box = nil
    Balalaio.float_drag_offset = nil
    if box and not box.REMOVED and box.remove then
        pcall(function() box:remove() end)
    end
end

function Balalaio.update()
    Balalaio.update_hold_repeat()
    if Balalaio.run_ready() then
        Balalaio.refresh_values()
        local input_blocked = G.SETTINGS.paused
            or G.OVERLAY_MENU
            or (
                G.CONTROLLER
                and G.CONTROLLER.interrupt
                and G.CONTROLLER.interrupt.focus
            )
        if input_blocked then
            if Balalaio.float_box then Balalaio.remove_float_button() end
        elseif not Balalaio.float_box or Balalaio.float_box.REMOVED then
            Balalaio.float_box = nil
            Balalaio.create_float_button()
        end
    elseif Balalaio.float_box then
        Balalaio.remove_float_button()
    end
end

G.FUNCS.balalaio_open_menu = function()
    set_status("")
    Balalaio.open("general")
end

G.FUNCS.balalaio_adjust = function(element)
    local action = element and element.config and element.config.ref_table
    if action then Balalaio.adjust_general(action.key, action.delta) end
end

G.FUNCS.balalaio_change_view = function(element)
    local action = element and element.config and element.config.ref_table
    if action and action.view then Balalaio.open(action.view) end
end

G.FUNCS.balalaio_change_page = function(element)
    local action = element and element.config and element.config.ref_table
    if not action then return end

    if action.kind == "jokers" then
        Balalaio.state.joker_page = Balalaio.state.joker_page + action.delta
        Balalaio.open("jokers")
    elseif action.kind == "consumables" then
        Balalaio.state.consumable_page =
            Balalaio.state.consumable_page + action.delta
        Balalaio.open("consumables")
    elseif action.kind == "deck" then
        Balalaio.state.deck_page = Balalaio.state.deck_page + action.delta
        Balalaio.open("deck")
    elseif action.kind == "picker" then
        Balalaio.state.picker_page = Balalaio.state.picker_page + action.delta
        Balalaio.open_picker(Balalaio.state.picker_kind)
    elseif action.kind == "modifiers" then
        Balalaio.state.modifier_page =
            Balalaio.state.modifier_page + action.delta
        Balalaio.open_editor(
            Balalaio.state.selected_card or Balalaio.state.selected_joker,
            Balalaio.state.editor_kind
        )
    end
end

G.FUNCS.balalaio_open_picker = function(element)
    local action = element and element.config and element.config.ref_table
    local kind = action and action.kind or "joker"
    if kind ~= "joker" and kind ~= "consumable" and kind ~= "playing" then
        kind = "joker"
    end
    Balalaio.state.picker_return =
        (action and action.return_view)
        or Balalaio.state.view
        or (kind == "playing" and "deck")
        or (kind == "consumable" and "consumables")
        or "jokers"
    Balalaio.state.picker_kind = kind
    Balalaio.state.picker_page = 1
    set_status(
        kind == "playing" and "Choose a playing card to add."
        or (kind == "consumable" and "Choose a consumable to add.")
        or "Choose a Joker to add."
    )
    Balalaio.open_picker(kind)
end

G.FUNCS.balalaio_picker_back = function()
    Balalaio.open(Balalaio.state.picker_return or "jokers")
end

G.FUNCS.balalaio_picker_filter = function(element)
    local action = element and element.config and element.config.ref_table
    if not action then return end
    local kind = action.kind or Balalaio.state.picker_kind
    if kind == "consumable" then
        Balalaio.state.picker_consumable_set = action.value or "All"
    elseif kind == "playing" then
        Balalaio.state.picker_suit = action.value or "All"
    else
        Balalaio.state.picker_rarity = action.value or 0
    end
    Balalaio.state.picker_page = 1
    Balalaio.open_picker(kind)
end

G.FUNCS.balalaio_add_picker_card = function(element)
    local action = element and element.config and element.config.ref_table
    if not action then return end
    local kind = action.kind or Balalaio.state.picker_kind or "joker"
    local center = action.center_key
        and G.P_CENTERS
        and G.P_CENTERS[action.center_key]
    local front = action.front_key
        and G.P_CARDS
        and G.P_CARDS[action.front_key]
    queue_change(function()
        local changed = false
        if kind == "consumable" then
            changed = add_consumable_now(action.center_key)
        elseif kind == "playing" then
            changed = add_playing_card_now(action.front_key)
        else
            changed = add_joker_now(action.center_key)
        end

        if changed then
            local name = kind == "playing"
                and (
                    tostring(front and front.value or "Card")
                    .. " of "
                    .. tostring(front and front.suit or "Unknown")
                )
                or (center and center.name)
                or (kind == "consumable" and "consumable" or "Joker")
            set_status("Added " .. name .. ".")
        else
            set_status("Could not add that card.")
        end
        return changed
    end, function(changed)
        if changed then
            Balalaio.open(Balalaio.state.picker_return or "jokers")
        else
            Balalaio.open_picker(kind)
        end
    end)
end

G.FUNCS.balalaio_add_joker = function(element)
    local action = element and element.config and element.config.ref_table
    if not action then return end
    action.kind = "joker"
    G.FUNCS.balalaio_add_picker_card(element)
end

G.FUNCS.balalaio_remove_joker = function(element)
    local action = element and element.config and element.config.ref_table
    if not action or not action.card then return end
    local name = joker_name(action.card)
    queue_change(function()
        local changed = editor_card_available(action.card, "joker")
            and remove_card_now(action.card)
        if changed then
            set_status("Removed " .. name .. ".")
        else
            set_status("Could not remove " .. name .. ".")
        end
        return changed
    end, function()
        Balalaio.open("jokers")
    end)
end

G.FUNCS.balalaio_edit_joker = function(element)
    local action = element and element.config and element.config.ref_table
    if not action or not action.card then return end
    Balalaio.state.modifier_page = 1
    set_status("")
    Balalaio.open_editor(action.card, "joker")
end

G.FUNCS.balalaio_edit_consumable = function(element)
    local action = element and element.config and element.config.ref_table
    if not action or not action.card then return end
    Balalaio.state.modifier_page = 1
    set_status("")
    Balalaio.open_editor(action.card, "consumable")
end

G.FUNCS.balalaio_edit_playing_card = function(element)
    local action = element and element.config and element.config.ref_table
    if not action or not action.card then return end
    set_status("")
    Balalaio.open_editor(action.card, "playing")
end

G.FUNCS.balalaio_back_to_jokers = function()
    Balalaio.open("jokers")
end

G.FUNCS.balalaio_back_to_consumables = function()
    Balalaio.open("consumables")
end

G.FUNCS.balalaio_back_to_deck = function()
    Balalaio.open("deck")
end

G.FUNCS.balalaio_remove_playing_card = function(element)
    local action = element and element.config and element.config.ref_table
    if not action or not action.card then return end
    local card = action.card
    local name = playing_card_name(card)
    queue_change(function()
        local changed = remove_playing_card_now(card)
        set_status(
            changed
                and ("Removed " .. name .. ".")
                or ("Could not remove " .. name .. " right now.")
        )
        return changed
    end, function()
        Balalaio.open("deck")
    end)
end

G.FUNCS.balalaio_cycle_edition = function(element)
    local action = element and element.config and element.config.ref_table
    if not action or not action.card then return end
    local card = action.card
    local kind = action.kind or Balalaio.state.editor_kind or "joker"
    if not editor_card_available(card, kind) then
        set_status("That card is no longer safe to edit.")
        return
    end
    local choices = edition_choices(kind)
    local new_index = (
        (current_edition_choice_index(card, choices) - 1 + action.delta)
        % #choices
    ) + 1
    local edition = choices[new_index]
    queue_change(function()
        if not editor_card_available(card, kind) then
            set_status("That card is no longer safe to edit.")
            return false
        end
        set_edition_now(card, edition)
        set_status("Edition changed to " .. edition.label .. ".")
        return true
    end, function()
        Balalaio.open_editor(card, kind)
    end)
end

G.FUNCS.balalaio_cycle_deck_property = function(element)
    local action = element and element.config and element.config.ref_table
    if not action
        or not action.card
        or not action.property
        or not action.delta
    then
        return
    end
    local card = action.card
    queue_change(function()
        local changed =
            cycle_playing_property_now(card, action.property, action.delta)
        if changed then
            local options = playing_property_options(card, action.property)
            local current = current_playing_property(card, action.property)
            local selected = options[option_index(options, current)]
            set_status(
                "Updated "
                    .. tostring(action.property)
                    .. " to "
                    .. tostring(selected and selected.label or current)
                    .. "."
            )
        else
            set_status("That playing card cannot be changed right now.")
        end
        return changed
    end, function()
        Balalaio.open_editor(card, "playing")
    end)
end

G.FUNCS.balalaio_toggle_flag = function(element)
    local action = element and element.config and element.config.ref_table
    if not action
        or not action.card
        or not editor_card_available(action.card, "joker")
    then
        return
    end
    local card = action.card
    queue_change(function()
        if not editor_card_available(card, "joker") then
            set_status("That Joker is no longer safe to edit.")
            return false
        end
        toggle_flag_now(card, action.key)
        set_status("Updated " .. tostring(action.key) .. " modifier.")
        return true
    end, function()
        Balalaio.open_editor(card, "joker")
    end)
end

G.FUNCS.balalaio_adjust_modifier = function(element)
    local action = element and element.config and element.config.ref_table
    if not action or not action.entry then return end
    queue_change(function()
        local kind = Balalaio.state.editor_kind or "joker"
        if editor_card_available(action.entry.card, kind)
            and adjust_modifier_now(action.entry, action.delta)
        then
            set_status("Updated " .. action.entry.label .. ".")
            return true
        else
            set_status("That modifier is no longer available.")
            return false
        end
    end)
end

if Game and Game.update and not Game._balalaio_update_wrapped then
    Game._balalaio_update_wrapped = true
    local original_game_update = Game.update
    Game.update = function(self, dt)
        original_game_update(self, dt)
        local active = rawget(_G, "Balalaio")
        if active and type(active.update) == "function" then
            active.update()
        end
    end
end

return Balalaio
