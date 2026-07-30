import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { lua, lauxlib, lualib, to_luastring, to_jsstring } from "fengari";

const currentDirectory = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(currentDirectory, "..");
const candidateAssetDirectories = [
  process.env.BALATRO_ASSETS_DIR,
  path.join(repositoryRoot, ".work", "apktool-v18", "assets"),
  path.join(repositoryRoot, ".work", "original", "assets"),
  path.join(repositoryRoot, ".work", "apktool-output", "assets"),
].filter(Boolean);

const requiredEngineFiles = [
  path.join("engine", "object.lua"),
  path.join("engine", "node.lua"),
  path.join("engine", "moveable.lua"),
  path.join("engine", "ui.lua"),
  path.join("engine", "controller.lua"),
];
const assetDirectory = candidateAssetDirectories.find((candidate) =>
  requiredEngineFiles.every((relativePath) =>
    fs.existsSync(path.join(candidate, relativePath)),
  ),
);

if (!assetDirectory) {
  console.log(
    "Real Balatro input-path test skipped: set BALATRO_ASSETS_DIR to extracted, user-owned Balatro assets.",
  );
  process.exit(0);
}

const moduleSource = fs.readFileSync(
  path.join(repositoryRoot, "Balalaio", "balalaio.lua"),
  "utf8",
);
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

function runEngineFile(relativePath) {
  runLua(
    fs.readFileSync(path.join(assetDirectory, relativePath), "utf8"),
    `@${relativePath.replaceAll("\\", "/")}`,
  );
}

runEngineFile(path.join("engine", "object.lua"));

runLua(
  `
local mouse_x, mouse_y = 0, 0

love = {
    mouse = {
        getPosition = function() return mouse_x, mouse_y end,
        setVisible = function() end,
    },
    graphics = {
        newText = function()
            return {set = function() end}
        end,
    },
}

function set_test_mouse(x, y)
    mouse_x, mouse_y = x, y
end

function EMPTY() return {} end
function remove_all(target)
    for key in pairs(target or {}) do target[key] = nil end
end
function point_translate(point, translation)
    point.x = point.x + translation.x
    point.y = point.y + translation.y
end
function point_rotate(point, rotation)
    if not rotation or math.abs(rotation) < 0.000001 then return end
    local x, y = point.x, point.y
    point.x = x * math.cos(rotation) - y * math.sin(rotation)
    point.y = x * math.sin(rotation) + y * math.cos(rotation)
end
function Vector_Dist(a, b)
    return math.sqrt((a.x - b.x)^2 + (a.y - b.y)^2)
end
function add_to_drawhash(node)
    G.DRAW_HASH[#G.DRAW_HASH + 1] = node
end
function play_sound() end
function create_drag_target_from_card() end
function Event(config) return config end

local transparent = {0, 0, 0, 0}
local white = {1, 1, 1, 1}
local dark = {0.1, 0.1, 0.1, 1}
local font = {
    FONT = {
        getWidth = function(_, text) return #tostring(text) * 10 end,
        getHeight = function() return 18 end,
    },
    squish = 1,
    FONTSCALE = 1,
    TEXT_HEIGHT_SCALE = 1,
    TEXT_OFFSET = {x = 0, y = 0},
}

G = {
    ID = 1,
    STAGE = 1,
    STAGES = {RUN = 1, SPLASH = 2},
    STATES = {SPLASH = 2},
    STATE = 0,
    SETTINGS = {
        paused = false,
        reduced_motion = false,
        GRAPHICS = {shadows = "Off"},
    },
    GAME = {
        current_round = {hands_left = 2, discards_left = 1},
        round_resets = {hands = 4, discards = 3},
        dollars = 10,
        banned_keys = {},
        used_jokers = {},
    },
    jokers = {cards = {}, config = {card_limit = 5}},
    consumeables = {cards = {}, config = {card_limit = 2}},
    FUNCS = {},
    MOVEABLES = {},
    I = {
        NODE = {},
        MOVEABLE = {},
        UIBOX = {},
        POPUP = {},
        CARDAREA = {},
        SPRITE = {},
    },
    STAGE_OBJECTS = {[1] = {}},
    UIT = {
        ROOT = 1,
        R = 2,
        C = 3,
        T = 4,
        B = 5,
        O = 6,
        padding = 0,
    },
    C = {
        CLEAR = transparent,
        WHITE = white,
        ORANGE = {1, 0.5, 0, 1},
        DARK_EDITION = dark,
        JOKER_GREY = {0.3, 0.3, 0.3, 1},
        BLUE = {0, 0.4, 1, 1},
        PURPLE = {0.6, 0.2, 0.8, 1},
        GREEN = {0, 0.7, 0.2, 1},
        RED = {0.8, 0.1, 0.1, 1},
        MONEY = {1, 0.8, 0, 1},
        ETERNAL = {0.5, 0.5, 0.5, 1},
        PERISHABLE = {0.5, 0.5, 0.5, 1},
        RENTAL = {0.5, 0.5, 0.5, 1},
        RARITY = {},
        UI = {
            BACKGROUND_DARK = dark,
            TEXT_LIGHT = white,
            OUTLINE_LIGHT = white,
            HOVER = {1, 1, 1, 0.2},
        },
    },
    LANG = {font = font},
    TIMERS = {REAL = 1, UPTIME = 1},
    FRAMES = {MOVE = 1, DRAW = 1},
    ARGS = {},
    exp_times = {xy = 0, scale = 0, r = 0, max_vel = 1},
    TILESIZE = 20,
    TILESCALE = 1,
    TILE_W = 18,
    TILE_H = 10,
    DRAW_HASH = {},
    DRAW_HASH_BUFF = 2,
    E_MANAGER = {
        add_event = function(_, event)
            if event and event.func then event.func() end
        end,
    },
    MIN_CLICK_DIST = 0.5,
    MIN_HOVER_TIME = 0.1,
    CURSOR = {
        T = {x = 0, y = 0},
        VT = {x = 0, y = 0},
        states = {visible = false},
    },
}

G.ROOM = {
    T = {x = 0, y = 0, w = 18, h = 10, r = 0},
    VT = {x = 0, y = 0, w = 18, h = 10, r = 0},
    states = {
        visible = true,
        collide = {can = false, is = false},
        focus = {can = false, is = false},
        hover = {can = false, is = false},
        click = {can = false, is = false},
        drag = {can = false, is = false},
        release_on = {can = false, is = false},
    },
    jiggle = 0,
}
G.ROOM_ATTACH = {
    T = G.ROOM.T,
    VT = G.ROOM.VT,
    set_role = function() end,
}

function G.ROOM:can_drag() return nil end
function G.ROOM:set_offset() end
function G.ROOM:click() end
function G.ROOM:drag() end
function G.ROOM:stop_drag() end
function G.ROOM:collides_with_point() return false end
function G:save_settings()
    self.saved_settings = (self.saved_settings or 0) + 1
end

Game = {
    update = function() end,
}
`,
  "@input-path-prelude.lua",
);

runEngineFile(path.join("engine", "node.lua"));
runEngineFile(path.join("engine", "moveable.lua"));
runEngineFile(path.join("engine", "ui.lua"));
runEngineFile(path.join("engine", "controller.lua"));
runLua(moduleSource, "@Balalaio/balalaio.lua");

runLua(
  `
local function fresh_controller()
    local controller = Controller()
    controller.update_axis = function() return nil end
    G.CONTROLLER = controller
    controller:set_HID_flags("touch")
    return controller
end

local function add_ui_to_draw_hash(node)
    node:draw_boundingrect()
    if node.config
        and (
            node.config.force_focus
            or node.config.force_collision
            or node.config.button_UIE
            or node.config.button
            or node.states.collide.can
        )
    then
        add_to_drawhash(node)
    end
    for _, child in pairs(node.children or {}) do
        add_ui_to_draw_hash(child)
    end
end

local function prepare_hit_test(under_overlay)
    G.under_overlay = under_overlay or false
    G.DRAW_HASH = {}
    add_to_drawhash(Balalaio.float_box)
    add_ui_to_draw_hash(Balalaio.float_box.UIRoot)
    local button =
        Balalaio.float_box:get_UIE_by_ID("balalaio_float_button")
    local x = (button.T.x + button.T.w / 2 + G.ROOM.T.x)
        * G.TILESCALE
        * G.TILESIZE
    local y = (button.T.y + button.T.h / 2 + G.ROOM.T.y)
        * G.TILESCALE
        * G.TILESIZE
    set_test_mouse(x, y)
    return button, x, y
end

local function press(controller, x, y)
    controller:queue_L_cursor_press(x, y)
    controller:update(0.016)
end

local function release(controller, x, y, elapsed)
    G.TIMERS.UPTIME = G.TIMERS.UPTIME + elapsed
    G.TIMERS.REAL = G.TIMERS.REAL + elapsed
    controller:L_cursor_release(x, y)
    controller:update(0.016)
end

local opened = 0
Balalaio.open = function(view)
    assert(view == "general")
    opened = opened + 1
end

fresh_controller()
Balalaio.create_float_button()
assert(Balalaio.float_box, "floating UIBox should be created")
assert(
    Balalaio.float_box.config.instance_type == "POPUP",
    "the launcher must use Balatro's POPUP draw layer"
)
local launcher_registered_as_popup = false
for _, popup in pairs(G.I.POPUP) do
    if popup == Balalaio.float_box then
        launcher_registered_as_popup = true
        break
    end
end
assert(
    launcher_registered_as_popup,
    "the real UIBox constructor must register the launcher in G.I.POPUP"
)
local button, x, y = prepare_hit_test(false)
assert(
    not button.created_on_pause,
    "the in-run button should be created while the game is unpaused (value: "
        .. tostring(button.created_on_pause)
        .. ")"
)

press(G.CONTROLLER, x, y)
assert(
    G.CONTROLLER.cursor_down.target == button,
    "real Controller hit-testing should select the button row"
)
assert(
    G.CONTROLLER.dragging.target == button,
    "the real press path should start dragging the movable row"
)
release(G.CONTROLLER, x, y, 0.05)
assert(opened == 1, "a normal real touch tap must reach balalaio_open_menu")

G.TIMERS.UPTIME = G.TIMERS.UPTIME + 0.2
G.TIMERS.REAL = G.TIMERS.REAL + 0.2
local drag_controller = fresh_controller()
button, x, y = prepare_hit_test(false)
local start_x, start_y = Balalaio.float_box.T.x, Balalaio.float_box.T.y
local visible_button_x, visible_button_y = button.VT.x, button.VT.y
press(drag_controller, x, y)
set_test_mouse(
    x - 2 * G.TILESIZE * G.TILESCALE,
    y + 1 * G.TILESIZE * G.TILESCALE
)
G.TIMERS.UPTIME = G.TIMERS.UPTIME + 0.15
G.TIMERS.REAL = G.TIMERS.REAL + 0.15
drag_controller:update(0.016)
assert(
    Balalaio.float_box.T.x ~= start_x
        or Balalaio.float_box.T.y ~= start_y,
    "a real Controller drag must move the floating UIBox"
)
assert(
    button.VT.x ~= visible_button_x or button.VT.y ~= visible_button_y,
    "drag must synchronize the launcher's visible child transform immediately"
)
local opened_before_drag_release = opened
release(
    drag_controller,
    drag_controller.cursor_position.x,
    drag_controller.cursor_position.y,
    0.05
)
assert(
    opened == opened_before_drag_release,
    "releasing a moved button must not count as a tap"
)

G.TIMERS.UPTIME = G.TIMERS.UPTIME + 0.2
G.TIMERS.REAL = G.TIMERS.REAL + 0.2
local overlay_controller = fresh_controller()
button, x, y = prepare_hit_test(true)
assert(button.under_overlay, "draw state should mark the button under an overlay")
local opened_before_overlay = opened
press(overlay_controller, x, y)
release(overlay_controller, x, y, 0.05)
assert(
    opened == opened_before_overlay,
    "UIElement:click must reject a button drawn under an overlay"
)

G.TIMERS.UPTIME = G.TIMERS.UPTIME + 0.2
G.TIMERS.REAL = G.TIMERS.REAL + 0.2
local tutorial_controller = fresh_controller()
tutorial_controller.interrupt.focus = false
local tutorial_overlay = UIBox({
    definition = {
        n = G.UIT.ROOT,
        config = {
            align = "cm",
            minw = G.ROOM.T.w,
            minh = G.ROOM.T.h,
            colour = G.C.CLEAR,
        },
        nodes = {},
    },
    config = {
        align = "cm",
        major = G.ROOM_ATTACH,
        bond = "Weak",
    },
})
G.OVERLAY_TUTORIAL = tutorial_overlay

-- Reproduce Game:draw ordering: tutorial first, then G.I.POPUP. A popup
-- launcher is never stamped under_overlay and must be the last matching node
-- in Balatro's reverse draw-hash hit test.
G.DRAW_HASH = {}
G.under_overlay = false
add_to_drawhash(tutorial_overlay)
add_ui_to_draw_hash(tutorial_overlay.UIRoot)
add_to_drawhash(Balalaio.float_box)
add_ui_to_draw_hash(Balalaio.float_box.UIRoot)
button = Balalaio.float_box:get_UIE_by_ID("balalaio_float_button")
x = (button.T.x + button.T.w / 2 + G.ROOM.T.x)
    * G.TILESCALE
    * G.TILESIZE
y = (button.T.y + button.T.h / 2 + G.ROOM.T.y)
    * G.TILESCALE
    * G.TILESIZE
set_test_mouse(x, y)
assert(
    not button.under_overlay,
    "the popup launcher must be drawn after the tutorial overlay"
)
local opened_before_tutorial = opened
press(tutorial_controller, x, y)
assert(
    tutorial_controller.cursor_down.target == button,
    "the popup launcher must win hit-testing above the tutorial UIBox"
)
release(tutorial_controller, x, y, 0.05)
assert(
    opened == opened_before_tutorial + 1,
    "the popup launcher must remain tappable over the tutorial"
)

G.TIMERS.UPTIME = G.TIMERS.UPTIME + 0.2
G.TIMERS.REAL = G.TIMERS.REAL + 0.2
local tutorial_drag_controller = fresh_controller()
tutorial_drag_controller.interrupt.focus = false
G.DRAW_HASH = {}
G.under_overlay = false
add_to_drawhash(tutorial_overlay)
add_ui_to_draw_hash(tutorial_overlay.UIRoot)
add_to_drawhash(Balalaio.float_box)
add_ui_to_draw_hash(Balalaio.float_box.UIRoot)
button = Balalaio.float_box:get_UIE_by_ID("balalaio_float_button")
x = (button.T.x + button.T.w / 2 + G.ROOM.T.x)
    * G.TILESCALE
    * G.TILESIZE
y = (button.T.y + button.T.h / 2 + G.ROOM.T.y)
    * G.TILESCALE
    * G.TILESIZE
set_test_mouse(x, y)
local tutorial_x, tutorial_y =
    Balalaio.float_box.T.x, Balalaio.float_box.T.y
local tutorial_visible_x, tutorial_visible_y = button.VT.x, button.VT.y
press(tutorial_drag_controller, x, y)
set_test_mouse(
    x + 1.25 * G.TILESIZE * G.TILESCALE,
    y + 0.75 * G.TILESIZE * G.TILESCALE
)
G.TIMERS.UPTIME = G.TIMERS.UPTIME + 0.15
G.TIMERS.REAL = G.TIMERS.REAL + 0.15
tutorial_drag_controller:update(0.016)
assert(
    Balalaio.float_box.T.x ~= tutorial_x
        or Balalaio.float_box.T.y ~= tutorial_y,
    "the popup launcher must remain draggable over the tutorial"
)
assert(
    button.VT.x ~= tutorial_visible_x or button.VT.y ~= tutorial_visible_y,
    "tutorial drag must update the launcher's visible child transform"
)
local opened_before_tutorial_drag = opened
release(
    tutorial_drag_controller,
    tutorial_drag_controller.cursor_position.x,
    tutorial_drag_controller.cursor_position.y,
    0.05
)
assert(
    opened == opened_before_tutorial_drag,
    "releasing a moved popup launcher must not count as a tutorial tap"
)

G.OVERLAY_TUTORIAL = nil
G.under_overlay = false
G.SETTINGS.paused = true
G.TIMERS.UPTIME = G.TIMERS.UPTIME + 0.2
G.TIMERS.REAL = G.TIMERS.REAL + 0.2
Balalaio.update()
assert(
    Balalaio.float_box == nil,
    "Balalaio.update must remove the launcher while gameplay input is paused"
)

print(
    "Real Balatro input-path tests passed; popup tap and visible-transform drag work over the tutorial overlay."
)
`,
  "@input-path-tests.lua",
);
