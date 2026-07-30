-- Balalaio
-- Offline cheat controls for Balatro.

local existing = rawget(_G, "Balalaio")
if existing and existing.VERSION == "0.2.0" then
    return existing
end
if existing and type(existing.remove_float_button) == "function" then
    pcall(existing.remove_float_button)
end

local Balalaio = {
    VERSION = "0.2.0",
    ui = {
        status = "",
    },
    state = {
        view = "general",
        joker_page = 1,
        picker_page = 1,
        picker_rarity = 0,
        picker_return = "jokers",
        modifier_page = 1,
        selected_joker = nil,
    },
    values = {},
    float_box = nil,
    float_drag_offset = nil,
}

_G.Balalaio = Balalaio

local JOKERS_PER_PAGE = 5
local PICKER_PER_PAGE = 10
local MODIFIERS_PER_PAGE = 5

local EDITIONS = {
    {label = "Base", value = nil},
    {label = "Foil", value = {foil = true}},
    {label = "Holographic", value = {holo = true}},
    {label = "Polychrome", value = {polychrome = true}},
    {label = "Negative", value = {negative = true}},
}

local RARITY_LABELS = {
    [0] = "All",
    [1] = "Common",
    [2] = "Uncommon",
    [3] = "Rare",
    [4] = "Legendary",
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
    h_size = 0,
    d_size = 0,
    extra_value = 0,
    perma_bonus = 0,
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
    if value == math.floor(value) then return tostring(value) end
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

local function mark_run_dirty()
    if not G then return end

    if type(save_run) == "function" then
        local ok = pcall(save_run)
        if ok then
            G.FILE_HANDLER = G.FILE_HANDLER or {}
            G.FILE_HANDLER.force = true
            return
        end
    end

    G.FILE_HANDLER = G.FILE_HANDLER or {}
    G.FILE_HANDLER.run = true
    G.FILE_HANDLER.update_queued = true
    G.FILE_HANDLER.force = true
end

local function refresh_hud()
    if G and G.HUD and G.HUD.recalculate then
        pcall(function() G.HUD:recalculate() end)
    end
end

local function queue_change(change, after)
    local function execute()
        local ok, err = pcall(change)
        if not ok then
            set_status("Change failed: " .. tostring(err))
        else
            mark_run_dirty()
            Balalaio.refresh_values()
            refresh_hud()
            if after then after() end
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

local function add_consumable_now()
    expand_area_for_one(G.consumeables)
    local card = create_card(
        "Tarot",
        G.consumeables,
        nil,
        nil,
        true,
        true,
        nil,
        "balalaio"
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

    local was_banned = G.GAME.banned_keys and G.GAME.banned_keys[center_key]
    if G.GAME.banned_keys then G.GAME.banned_keys[center_key] = nil end

    local card = create_card(
        "Joker",
        G.jokers,
        nil,
        nil,
        true,
        false,
        center_key,
        "balalaio"
    )

    if G.GAME.banned_keys and was_banned then
        G.GAME.banned_keys[center_key] = was_banned
    end

    if not card then return false end
    if card.add_to_deck then card:add_to_deck() end
    G.jokers:emplace(card)
    card.created_on_pause = nil
    mark_center_used(card)
    if card.start_materialize then card:start_materialize(nil, true) end
    return true
end

function Balalaio.adjust_general(key, delta)
    if not Balalaio.run_ready() then
        set_status("Start or continue a run first.")
        return
    end

    if key == "current_jokers" and delta > 0 then
        Balalaio.state.picker_return = "general"
        Balalaio.state.picker_page = 1
        set_status("Choose a Joker to add.")
        Balalaio.open_picker()
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
            if not remove_card_now(card) then
                set_status("There is no Joker to remove.")
            else
                set_status("Removed the last Joker.")
            end
        elseif key == "max_jokers" then
            G.jokers.config.card_limit =
                math.max(0, G.jokers.config.card_limit + delta)
            G.jokers.config.real_card_limit = G.jokers.config.card_limit
        elseif key == "money" then
            G.GAME.dollars = G.GAME.dollars + delta
        elseif key == "current_consumables" and delta > 0 then
            if add_consumable_now() then
                set_status("Added a random consumable.")
            else
                set_status("Could not add a consumable.")
            end
        elseif key == "current_consumables" then
            local card = G.consumeables.cards[#G.consumeables.cards]
            if not remove_card_now(card) then
                set_status("There is no consumable to remove.")
            else
                set_status("Removed the last consumable.")
            end
        elseif key == "max_consumables" then
            G.consumeables.config.card_limit =
                math.max(0, G.consumeables.config.card_limit + delta)
            G.consumeables.config.real_card_limit =
                G.consumeables.config.card_limit
        end
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
                button = "balalaio_change_page",
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
                button = "balalaio_change_page",
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

local function joker_row(card, index)
    return {
        n = G.UIT.R,
        config = {
            align = "cm",
            minw = 9.7,
            minh = 0.7,
            padding = 0.035,
            r = 0.09,
            colour = G.C.UI.TRANSPARENT_DARK,
        },
        nodes = {
            {
                n = G.UIT.C,
                config = {align = "cl", minw = 5.8, maxw = 5.8},
                nodes = {
                    text_node(
                        tostring(index) .. ". " .. joker_name(card),
                        0.34,
                        joker_rarity_colour(card),
                        {shadow = true}
                    ),
                },
            },
            compact_button({
                label = "EDIT",
                button = "balalaio_edit_joker",
                ref_table = {card = card},
                colour = G.C.BLUE,
                minw = 1.55,
                scale = 0.27,
            }),
            compact_button({
                label = "REMOVE",
                button = "balalaio_remove_joker",
                ref_table = {card = card},
                colour = G.C.RED,
                minw = 1.85,
                scale = 0.25,
            }),
        },
    }
end

function Balalaio.create_jokers()
    local cards = G.jokers.cards
    local pages = page_count(#cards, JOKERS_PER_PAGE)
    Balalaio.state.joker_page = clamp(Balalaio.state.joker_page, 1, pages)

    local page = Balalaio.state.joker_page
    local first = (page - 1) * JOKERS_PER_PAGE + 1
    local last = math.min(#cards, first + JOKERS_PER_PAGE - 1)
    local rows = {}

    if #cards == 0 then
        rows[#rows + 1] = {
            n = G.UIT.R,
            config = {align = "cm", minw = 9.7, minh = 3.55},
            nodes = {
                text_node(
                    "No Jokers obtained yet. Add one below.",
                    0.38,
                    G.C.JOKER_GREY
                ),
            },
        }
    else
        for index = first, last do
            rows[#rows + 1] = joker_row(cards[index], index)
        end
        while #rows < JOKERS_PER_PAGE do
            rows[#rows + 1] = {
                n = G.UIT.R,
                config = {align = "cm", minw = 9.7, minh = 0.7},
                nodes = {},
            }
        end
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

local function tab_button(label, view, colour)
    local selected = Balalaio.state.view == view
    return compact_button({
        label = label,
        button = "balalaio_change_view",
        ref_table = {view = view},
        colour = selected and colour or G.C.GREY,
        minw = 3.2,
        minh = 0.66,
        scale = 0.34,
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
    local body = Balalaio.state.view == "jokers"
        and Balalaio.create_jokers()
        or Balalaio.create_general()

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

function Balalaio.open_picker()
    if not Balalaio.run_ready() then return end
    G.SETTINGS.paused = true
    G.FUNCS.overlay_menu({
        definition = Balalaio.create_picker_modal(),
        config = {offset = {x = 0, y = 0}},
    })
end

local function picker_filter_button(rarity)
    local selected = Balalaio.state.picker_rarity == rarity
    local colour = rarity == 0
        and G.C.BLUE
        or (G.C.RARITY[rarity] or G.C.BLUE)
    return compact_button({
        label = RARITY_LABELS[rarity],
        button = "balalaio_picker_filter",
        ref_table = {rarity = rarity},
        colour = selected and colour or G.C.GREY,
        minw = rarity == 0 and 1.25 or 1.75,
        minh = 0.52,
        scale = 0.25,
        choice = true,
        chosen = selected,
    })
end

local function filtered_picker_centers()
    local result = {}
    for _, center in ipairs(sorted_joker_centers()) do
        if Balalaio.state.picker_rarity == 0
            or center.rarity == Balalaio.state.picker_rarity
        then
            result[#result + 1] = center
        end
    end
    return result
end

local function picker_card_button(center)
    return compact_button({
        label = center.name or center.key or "Unknown",
        button = "balalaio_add_joker",
        ref_table = {center_key = center.key},
        colour = G.C.RARITY[center.rarity] or G.C.PURPLE,
        minw = 4.75,
        maxw = 4.75,
        minh = 0.58,
        scale = 0.27,
    })
end

function Balalaio.create_picker_modal()
    local centers = filtered_picker_centers()
    local pages = page_count(#centers, PICKER_PER_PAGE)
    Balalaio.state.picker_page =
        clamp(Balalaio.state.picker_page, 1, pages)

    local page = Balalaio.state.picker_page
    local first = (page - 1) * PICKER_PER_PAGE + 1
    local rows = {
        {
            n = G.UIT.R,
            config = {align = "cm", minw = 10.8},
            nodes = {
                text_node("ADD A JOKER", 0.5, G.C.PURPLE, {shadow = true}),
            },
        },
        {
            n = G.UIT.R,
            config = {align = "cm", padding = 0.035},
            nodes = {
                picker_filter_button(0),
                picker_filter_button(1),
                picker_filter_button(2),
                picker_filter_button(3),
                picker_filter_button(4),
            },
        },
    }

    for row_index = 0, 4 do
        local left = centers[first + row_index * 2]
        local right = centers[first + row_index * 2 + 1]
        rows[#rows + 1] = {
            n = G.UIT.R,
            config = {align = "cm", minw = 10.1, minh = 0.65, padding = 0.035},
            nodes = {
                left and picker_card_button(left) or {
                    n = G.UIT.C,
                    config = {minw = 4.75, minh = 0.58},
                    nodes = {},
                },
                right and picker_card_button(right) or {
                    n = G.UIT.C,
                    config = {minw = 4.75, minh = 0.58},
                    nodes = {},
                },
            },
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

local function include_numeric_modifier(card, root_name, path, key, value)
    if key == "order" then return false end
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
end

local function modifier_label(root_name, path)
    local pieces = {}
    if root_name == "edition" then pieces[#pieces + 1] = "edition" end
    for _, part in ipairs(path) do
        pieces[#pieces + 1] = tostring(part):gsub("_", " ")
    end
    return table.concat(pieces, ".")
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
            entries[#entries + 1] = {
                card = card,
                root = root_name,
                parent = current,
                key = key,
                path = next_path,
                label = modifier_label(root_name, next_path),
                display = format_number(value),
            }
        elseif type(value) == "table" then
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
                nodes = {text_node(entry.label, 0.29, G.C.JOKER_GREY)},
            },
            compact_button({
                label = "-",
                button = "balalaio_adjust_modifier",
                ref_table = {entry = entry, delta = -1},
                colour = G.C.RED,
                minw = 0.7,
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
            }),
        },
    }
end

function Balalaio.create_editor_modal(card)
    local entries = Balalaio.collect_modifiers(card)
    local pages = page_count(#entries, MODIFIERS_PER_PAGE)
    Balalaio.state.modifier_page =
        clamp(Balalaio.state.modifier_page, 1, pages)

    local page = Balalaio.state.modifier_page
    local first = (page - 1) * MODIFIERS_PER_PAGE + 1
    local last = math.min(#entries, first + MODIFIERS_PER_PAGE - 1)
    local rarity_colour = joker_rarity_colour(card)
    local rows = {
        {
            n = G.UIT.R,
            config = {align = "cm", minw = 10.7},
            nodes = {
                text_node(joker_name(card), 0.5, rarity_colour, {shadow = true}),
            },
        },
        {
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
                    ref_table = {card = card, delta = -1},
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
                    ref_table = {card = card, delta = 1},
                    colour = G.C.PURPLE,
                    minw = 0.7,
                }),
            },
        },
        {
            n = G.UIT.R,
            config = {align = "cm", padding = 0.035},
            nodes = {
                flag_button(card, "ETERNAL", "eternal", G.C.ETERNAL),
                flag_button(card, "PERISHABLE", "perishable", G.C.PERISHABLE),
                flag_button(card, "RENTAL", "rental", G.C.RENTAL),
            },
        },
        {
            n = G.UIT.R,
            config = {align = "cl", minw = 9.8, minh = 0.35},
            nodes = {
                text_node(
                    "INSTANCE VALUES  (-1 / +1)",
                    0.27,
                    G.C.ORANGE,
                    {shadow = true}
                ),
            },
        },
    }

    if #entries == 0 then
        rows[#rows + 1] = {
            n = G.UIT.R,
            config = {align = "cm", minw = 9.8, minh = 3.2},
            nodes = {
                text_node(
                    "This Joker has no numeric instance values.",
                    0.34,
                    G.C.JOKER_GREY
                ),
            },
        }
    else
        for index = first, last do
            rows[#rows + 1] = modifier_row(entries[index])
        end
        while (#rows - 4) < MODIFIERS_PER_PAGE do
            rows[#rows + 1] = {
                n = G.UIT.R,
                config = {align = "cm", minw = 9.8, minh = 0.64},
                nodes = {},
            }
        end
    end

    rows[#rows + 1] = page_controls("modifiers", page, pages)
    rows[#rows + 1] = status_row()

    return create_UIBox_generic_options({
        minw = 11.2,
        padding = 0.08,
        back_label = "JOKERS",
        back_func = "balalaio_back_to_jokers",
        back_colour = G.C.ORANGE,
        contents = rows,
    })
end

function Balalaio.open_editor(card)
    if not card or card.REMOVED then
        set_status("That Joker is no longer available.")
        Balalaio.open("jokers")
        return
    end
    Balalaio.state.selected_joker = card
    G.SETTINGS.paused = true
    G.FUNCS.overlay_menu({
        definition = Balalaio.create_editor_modal(card),
        config = {offset = {x = 0, y = 0}},
    })
end

local function set_edition_now(card, new_index)
    local was_negative = card.edition and card.edition.negative
    local will_be_negative = new_index == 5

    if was_negative and G.jokers then
        G.jokers.config.card_limit =
            math.max(0, G.jokers.config.card_limit - 1)
        G.jokers.config.real_card_limit = G.jokers.config.card_limit
        if card.ability then card.ability.queue_negative_removal = nil end
    end

    card:set_edition(EDITIONS[new_index].value, true, true)

    if will_be_negative and not card.added_to_deck and G.jokers then
        G.jokers.config.card_limit = G.jokers.config.card_limit + 1
        G.jokers.config.real_card_limit = G.jokers.config.card_limit
        if card.ability then card.ability.queue_negative_removal = true end
    end

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

    entry.parent[entry.key] = entry.parent[entry.key] + delta
    entry.display = format_number(entry.parent[entry.key])

    if was_added and card.add_to_deck then card:add_to_deck(true) end
    if card.set_cost then card:set_cost() end
    return true
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
    elseif action.kind == "picker" then
        Balalaio.state.picker_page = Balalaio.state.picker_page + action.delta
        Balalaio.open_picker()
    elseif action.kind == "modifiers" then
        Balalaio.state.modifier_page =
            Balalaio.state.modifier_page + action.delta
        Balalaio.open_editor(Balalaio.state.selected_joker)
    end
end

G.FUNCS.balalaio_open_picker = function(element)
    local action = element and element.config and element.config.ref_table
    Balalaio.state.picker_return =
        (action and action.return_view) or Balalaio.state.view or "jokers"
    Balalaio.state.picker_page = 1
    set_status("Choose a Joker to add.")
    Balalaio.open_picker()
end

G.FUNCS.balalaio_picker_back = function()
    Balalaio.open(Balalaio.state.picker_return or "jokers")
end

G.FUNCS.balalaio_picker_filter = function(element)
    local action = element and element.config and element.config.ref_table
    if not action then return end
    Balalaio.state.picker_rarity = action.rarity or 0
    Balalaio.state.picker_page = 1
    Balalaio.open_picker()
end

G.FUNCS.balalaio_add_joker = function(element)
    local action = element and element.config and element.config.ref_table
    if not action or not action.center_key then return end
    local center = G.P_CENTERS[action.center_key]
    queue_change(function()
        if add_joker_now(action.center_key) then
            set_status("Added " .. (center and center.name or "Joker") .. ".")
        else
            set_status("Could not add that Joker.")
        end
    end, function()
        Balalaio.open(Balalaio.state.picker_return or "jokers")
    end)
end

G.FUNCS.balalaio_remove_joker = function(element)
    local action = element and element.config and element.config.ref_table
    if not action or not action.card then return end
    local name = joker_name(action.card)
    queue_change(function()
        if remove_card_now(action.card) then
            set_status("Removed " .. name .. ".")
        else
            set_status("Could not remove " .. name .. ".")
        end
    end, function()
        Balalaio.open("jokers")
    end)
end

G.FUNCS.balalaio_edit_joker = function(element)
    local action = element and element.config and element.config.ref_table
    if not action or not action.card then return end
    Balalaio.state.modifier_page = 1
    set_status("")
    Balalaio.open_editor(action.card)
end

G.FUNCS.balalaio_back_to_jokers = function()
    Balalaio.open("jokers")
end

G.FUNCS.balalaio_cycle_edition = function(element)
    local action = element and element.config and element.config.ref_table
    if not action or not action.card or action.card.REMOVED then return end
    local card = action.card
    local new_index =
        ((current_edition_index(card) - 1 + action.delta) % #EDITIONS) + 1
    queue_change(function()
        set_edition_now(card, new_index)
        set_status("Edition changed to " .. EDITIONS[new_index].label .. ".")
    end, function()
        Balalaio.open_editor(card)
    end)
end

G.FUNCS.balalaio_toggle_flag = function(element)
    local action = element and element.config and element.config.ref_table
    if not action or not action.card or action.card.REMOVED then return end
    local card = action.card
    queue_change(function()
        toggle_flag_now(card, action.key)
        set_status("Updated " .. tostring(action.key) .. " modifier.")
    end, function()
        Balalaio.open_editor(card)
    end)
end

G.FUNCS.balalaio_adjust_modifier = function(element)
    local action = element and element.config and element.config.ref_table
    if not action or not action.entry then return end
    queue_change(function()
        if adjust_modifier_now(action.entry, action.delta) then
            set_status("Updated " .. action.entry.label .. ".")
        else
            set_status("That modifier is no longer available.")
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
