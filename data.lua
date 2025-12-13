data:extend{{ -- hidden combinator to mimic negative of network state
  type = "constant-combinator",
  name = "fluid-temperature-monitor",
  icon = util.empty_icon().icon,
  collision_mask = {layers = {}},
  activity_led_light_offsets = {{0, 0}, {0, 0}, {0, 0}, {0, 0}},
  circuit_wire_connection_points = {{wire = {}, shadow = {}}, {wire = {}, shadow = {}}, {wire = {}, shadow = {}}, {wire = {}, shadow = {}}},
  flags = {
    "not-rotatable",
    "placeable-neutral",
    "placeable-off-grid",
    "not-repairable",
    "not-on-map",
    "not-deconstructable",
    "not-blueprintable",
    "hide-alt-info",
    "not-upgradable"
  },
  allow_copy_paste = false,
  selectable_in_game = false,
  hidden = true,
  hidden_in_factoriopedia = true
}}