script.on_init(function()
  storage = {
    thermometers = {},
    num = 0,
    batch_size = 0
  }
end)

script.on_configuration_changed(function()
  storage = {
    thermometers = storage.thermometers or {},
    next_index = storage.next_index,
    num = storage.num or 0,
    batch_size = storage.batch_size or 0
  }
end)

script.on_event({
  defines.events.on_built_entity,
  defines.events.on_robot_built_entity,
  defines.events.on_space_platform_built_entity,
  defines.events.script_raised_built,
  defines.events.script_raised_revive
},
--- @param event EventData.on_built_entity|EventData.on_robot_built_entity|EventData.on_space_platform_built_entity|EventData.script_raised_built|EventData.script_raised_revive
function (event)
  if not event.entity.type == "storage-tank" or not event.tags or not event.tags["fluid-temperature-signal"] then return end
  
  local tank = event.entity

  local monitor = tank.surface.create_entity{
    position = tank.position,
    name = "fluid-temperature-monitor"
  }

  -- connect to tank
  monitor.get_wire_connector(defines.wire_connector_id.circuit_green, true).connect_to(tank.get_wire_connector(defines.wire_connector_id.circuit_green, true))
  monitor.get_wire_connector(defines.wire_connector_id.circuit_red, true).connect_to(tank.get_wire_connector(defines.wire_connector_id.circuit_red, true))
  
  -- set up data handling, dont preload a value
  local signal_data = event.tags["fluid-temperature-signal"]
  local section = monitor.get_or_create_control_behavior().get_section(1)
  section.multiplier = 0
  section.set_slot(1, {
    value = {type = signal_data.type or "virtual", name = signal_data.name or "signal-T", quality = signal_data.quality or "normal"},
    min = 1
  })

  -- save for later
  storage.num = storage.num + 1
  storage.thermometers[tank.unit_number] = {
    tank = tank,
    monitor = monitor
  }
end)

script.on_event({
  defines.events.on_player_mined_entity,
  defines.events.on_robot_mined_entity,
  defines.events.on_space_platform_mined_entity,
  defines.events.script_raised_destroy,
  defines.events.on_entity_died
},
--- @param event EventData.on_player_mined_entity|EventData.on_robot_mined_entity|EventData.on_space_platform_mined_entity|EventData.script_raised_destroy|EventData.on_entity_died
function (event)
  local tank = event.entity
  if not tank.valid or not storage.thermometers[tank.unit_number] then return end
  storage.num = storage.num - 1
  storage.thermometers[tank.unit_number].monitor.destroy()
  storage.thermometers[tank.unit_number] = nil
end)

local batch_count = settings.global["fluid-temperature-update-rate"].value

script.on_event(defines.events.on_runtime_mod_setting_changed, function()
  batch_count = settings.global["fluid-temperature-update-rate"].value
end)

-- run batches every tick
script.on_event(defines.events.on_tick, function (event)
  -- update the size of each batch at the start of the loop so everything updates at the same rate
  if event.tick % batch_count == 0 then
    storage.batch_size = math.ceil(storage.num / batch_count)
  end

  for _ = 1, storage.batch_size do
    local metadata, next_index = next(storage.thermometers, storage.next_index)
    if metadata.tank.valid and not metadata.tank.to_be_deconstructed() then
      metadata.monitor.get_control_behavior().get_section(1).multiplier = math.floor((metadata.tank.get_fluid(1) or {}).temperature or 0)
    elseif not metadata.tank.valid then
      storage.num = storage.num - 1
      metadata.monitor.destroy()
      storage.thermometers[storage.next_index] = nil
    end
    storage.next_index = next_index
  end
end)

script.on_configuration_changed(function (event)
  if not event.mod_changes.thermometers then return end
  -- when the mod version changes, delete the UI so it's recreated from the ground up (in case anything changes)
  for _, player in pairs(game.players) do
    if player.gui.relative.thermometer then player.gui.relative.thermometer.destroy() end
  end
end)

local function update_gui(player_index)
  if not player_index then return end

  local player = game.get_player(player_index)
  local entity = player.opened.entity

  if not entity then return end

  local window = player.gui.relative.thermometer

  -- if window content does not exist (mod version change or fresh install)
  if not window then
    -- create new window

    window = player.gui.relative.add{
      type = "frame",
      name = "thermometer",
      caption = { "thermometer-window.frame" },
      direction = "vertical",
      anchor = {
        gui = defines.relative_gui_type.storage_tank_gui,
        position = defines.relative_gui_position.right
      }
    }.add{
      type = "frame",
      style = "inside_shallow_frame_with_padding_and_vertical_spacing",
      direction = "vertical"
    }
    subheader = window.add{
      type = "frame",
      style = "subheader_frame"
    }
    subheader.style.left_margin = -12
    subheader.style.right_margin = -12
    subheader.style.top_margin = -12
    subheader.style.bottom_margin = 8
    subheader.style.horizontally_squashable = true
    subheader.style.horizontally_stretchable = true
    subheader = subheader.add{
      type = "flow",
      style = "player_input_horizontal_flow",
      direction = "horizontal"
    }
    subheader.style.left_padding = 12
    subheader.style.right_padding = 12
    -- subheader.add{

    -- }
  else -- update data to reflect current state

  end
end

script.on_event(defines.events.on_gui_opened, function (event)
  if not event.entity or not event.entity.type == "storage-tank" then return end
  update_gui(event.player_index)
end)

-- script.on_event(defines.events.on_gui_click, function (event)

-- end)

-- TODO on_entity_settings_pasted
-- TODO on_copy/paste
-- TODO on blueprint pasted