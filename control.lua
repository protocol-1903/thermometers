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

local batch_count = settings.global["fluid-temperature-update-rate"].value

script.on_event(defines.events.on_runtime_mod_setting_changed, function()
  batch_count = settings.global["fluid-temperature-update-rate"].value
end)

-- run batches every tick
script.on_event(defines.events.on_tick, function (event)
  -- game.print(serpent.block(storage), {sound = defines.print_sound.never})
  -- update the size of each batch at the start of the loop so everything updates at the same rate
  if event.tick % batch_count == 0 then
    storage.batch_size = math.ceil(storage.num / batch_count)
  end

  for _ = 1, storage.batch_size do
    local next_index, metadata = next(storage.thermometers, storage.next_index)
    if metadata and metadata.tank.valid then
      local section = metadata.monitor.get_control_behavior().get_section(1)
      if section.get_slot(1) then
        section.set_slot(1, {
          value = section.get_slot(1).value,
          min = math.floor((metadata.tank.get_fluid(1) or {}).temperature or 0)
        })
      end
    elseif metadata and not metadata.tank.valid then
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
  local entity = player.opened

  if not entity then return end

  if entity.type ~= "storage-tank" or entity.type == "entity-ghost" and entity.ghost_type ~= "storage-tank" then return end

  local window = player.gui.relative.thermometer

  local monitor = storage.thermometers[entity.unit_number] and storage.thermometers[entity.unit_number].monitor
  local section = monitor and monitor.get_control_behavior().get_section(1)
  local signal = section and section.get_slot(1).value
  local enabled = section and section.multiplier == 1 or false

  -- if window content does not exist (mod version change or fresh install)
  if not window then
    -- recreate main gui
    window = player.gui.relative.add{
      type = "frame",
      name = "thermometer",
      direction = "vertical",
      anchor = {
        gui = defines.relative_gui_type.storage_tank_gui,
        position = defines.relative_gui_position.right
      }
    }
    -- main_frame.visible = false
    window.add{
      type = "flow",
      name = "titlebar",
      direction = "horizontal"
    }.add{
      type = "sprite-button",
      style = "close_button",
      sprite = "utility/circuit_network_panel",
      auto_toggle = true,
      toggled = false
    }
    local header = window.titlebar.add{
      type = "empty-widget",
      name = "header",
      style = "draggable_space_header"
    }
    header.style.horizontally_stretchable = true
    header.style.natural_height = 24
    header.style.height = 24
    header.style.right_margin = 5
    header.visible = false
    
    local main = window.add{
      type = "frame",
      name = "main",
      style = "inside_shallow_frame_with_padding_and_vertical_spacing",
      direction = "vertical"
    }
    main.visible = false
    -- add circuit network toggles
    main.add{
      type = "checkbox",
      name = "checkbox",
      style = "caption_checkbox",
      caption = {"gui-control-behavior-modes.read-temperature"},
      state = enabled
    }
    local circuit_condition = main.add{
      type = "flow",
      name = "circuit_condition",
      direction = "horizontal",
      style = "player_input_horizontal_flow"
    }
    circuit_condition.add{
      type = "label",
      name = "label",
      caption = {"gui-control-behavior-modes-guis.temperature"}
    }.enabled = enabled
    circuit_condition.add{
      type = "choose-elem-button",
      name = "signal",
      elem_type = "signal",
      style = "slot_button_in_shallow_frame",
      signal = signal or {type = "virtual", name = "signal-T", quality = "normal", comparator = "="}
    }.enabled = enabled
  else -- update data to reflect current state
    window.main.checkbox.state = enabled
    window.main.circuit_condition.label.enabled = enabled
    window.main.circuit_condition.signal.enabled = enabled
    if signal then
      window.main.circuit_condition.signal.elem_value = signal
    end
  end
end

script.on_event(defines.events.on_gui_opened, function (event)
  if not event.entity or not event.entity.type == "storage-tank" then return end
  update_gui(event.player_index)
end)

script.on_event(defines.events.on_gui_click, function (event)
  local button = event.element
  if not button or not button.valid then return end
  if button.get_mod() ~= "thermometers" then return end

  if button.type == "sprite-button" then
    local host = button.parent.parent
    host.main.visible = not host.main.visible
    host.titlebar.header.visible = host.main.visible
  elseif button.type == "checkbox" then
    -- enable/disable temperature reading
    local player = game.get_player(event.player_index)
    local entity = player.opened

    if button.state then
      if storage.thermometers[entity.unit_number] then
        storage.thermometers[entity.unit_number].monitor.get_or_create_control_behavior().get_section(1).multiplier = 1
      else
        local monitor = entity.surface.create_entity{
          position = entity.position,
          name = "fluid-temperature-monitor"
        }
        
        -- connect to tank
        monitor.get_wire_connector(defines.wire_connector_id.circuit_green, true).connect_to(entity.get_wire_connector(defines.wire_connector_id.circuit_green, true), false, defines.wire_origin.script)
        monitor.get_wire_connector(defines.wire_connector_id.circuit_red, true).connect_to(entity.get_wire_connector(defines.wire_connector_id.circuit_red, true), false, defines.wire_origin.script)
        
        -- set up data handling, dont preload a value
        local signal = button.parent.circuit_condition.signal.elem_value
        local section = monitor.get_or_create_control_behavior().get_section(1)
        section.set_slot(1, {value = {type = signal.type or "virtual", name = signal.name or "signal-T", quality = signal.quality or "normal", comparator = signal.comparator or "="}})
    
        storage.num = storage.num + 1
        storage.thermometers[entity.unit_number] = {
          tank = entity,
          monitor = monitor
        }
      end
    else
      storage.thermometers[entity.unit_number].monitor.get_or_create_control_behavior().get_section(1).multiplier = 0
    end
  end

  update_gui(event.player_index)
end)

---@param event EventData.on_gui_elem_changed
script.on_event(defines.events.on_gui_elem_changed, function (event)
  local button = event.element
  if not button or not button.valid then return end
  if button.get_mod() ~= "thermometers" then return end
  
  local player = game.get_player(event.player_index)
  local entity = player.opened
  local monitor = storage.thermometers[entity.unit_number].monitor
  local signal = button.elem_value
  local section = monitor.get_or_create_control_behavior().get_section(1)
  if signal then
    section.set_slot(1, {value = {type = signal.type or "virtual", name = signal.name or "signal-T", quality = signal.quality or "normal", comparator = signal.comparator or "="}})
  else
    section.clear_slot(1)
  end

  update_gui(event.player_index)
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
  monitor.get_wire_connector(defines.wire_connector_id.circuit_green, true).connect_to(tank.get_wire_connector(defines.wire_connector_id.circuit_green, true), false, defines.wire_origin.script)
  monitor.get_wire_connector(defines.wire_connector_id.circuit_red, true).connect_to(tank.get_wire_connector(defines.wire_connector_id.circuit_red, true), false, defines.wire_origin.script)
  
  -- set up data handling, dont preload a value
  local signal_data = event.tags["fluid-temperature-signal"]
  local section = monitor.get_or_create_control_behavior().get_section(1)
  section.multiplier = 0
  section.set_slot(1, {
    value = {type = signal_data.type or "virtual", name = signal_data.name or "signal-T", quality = signal_data.quality or "normal", comparator = signal_data.comparator or "="},
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

-- TODO on_entity_settings_pasted
-- TODO on_copy/paste
-- TODO on blueprint pasted