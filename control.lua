script.on_event(prototypes.custom_input["append-conditions"], function (event)
  local player = game.get_player(event.player_index)
  ---@cast player -?
  local from = player.entity_copy_source
  local to = player.selected
  if (not from) or (not to) then return end
  if from.type ~= "decider-combinator" or to.type ~= "decider-combinator" then return end
  local to_control = to.get_or_create_control_behavior() --[[@as LuaDeciderCombinatorControlBehavior]]
  local to_params = to_control.parameters
  local to_conditions = to_params.conditions
  local from_params = (from.get_or_create_control_behavior() --[[@as LuaDeciderCombinatorControlBehavior]]).parameters

  local i = #to_conditions+1
  for key, condition in pairs(from_params.conditions) do
    if key == 1 then
      condition.compare_type = "or"
    end
    to_conditions[i] = condition
    i = i+1
  end
  to_control.parameters = to_params
  player.play_sound({path="utility/entity_settings_pasted"})
end)

-- a step to the right from current facing
local step_vecs = {
  [defines.direction.north] = { x = 1, y = 0 },
  [defines.direction.east] = { x = 0, y = 1 },
  [defines.direction.south] = { x = -1, y = 0 },
  [defines.direction.west] = { x = 0, y = -1 },
}

local function position(base, direction, steps)
  local step = step_vecs[direction]
  return {
    x = base.x + (step.x * steps),
    y = base.y + (step.y * steps),
  }
end

local function seen_each(has_eaches_global, has_eaches_local, nets)
  if nets.red and nets.green then
    has_eaches_global.sum = true
    has_eaches_local.sum = true
  elseif nets.red then
    has_eaches_global.red = true
    has_eaches_local.red = true
  elseif nets.green then
    has_eaches_global.green = true
    has_eaches_local.green = true
  end
end


---@type {[string]:DeciderCombinatorCondition}
local and_each = {}
do
  ---@type SignalID
  local signal_each = { type="virtual", quality="normal", name="signal-each" }
  local function make_and_each(name, red, green)
    local wires = { green=green, red=red, }
    and_each[name] = {
        compare_type = "and",
        comparator = "=",
        first_signal = signal_each,
        first_signal_networks = wires,
        second_signal = signal_each,
        second_signal_networks = wires,
      }
  end
  make_and_each("red", true, false)
  make_and_each("green", false, true)
  make_and_each("sum", true, true)
end

script.on_event(prototypes.custom_input["split-conditions"], function (event)
  local player = game.get_player(event.player_index)
  ---@cast player -?
  local from = player.selected
  if not from then return end
  if from.type ~= "decider-combinator" then return end
  local from_params = (from.get_or_create_control_behavior() --[[@as LuaDeciderCombinatorControlBehavior]]).parameters
  local stack = player.cursor_stack
  if not stack then return end
  player.clear_cursor()
  stack.set_stack("blueprint")
  player.cursor_stack_temporary = true

  ---@class (exact) has_eaches
  ---@field red boolean
  ---@field green boolean
  ---@field sum boolean

  ---@class (exact) condinfo
  ---@field conditions DeciderCombinatorCondition[]
  ---@field has_eaches has_eaches

  ---@type BlueprintEntity[]
  local entities = {}
  ---@type condinfo[]
  local condinfos = {}
  ---@type BlueprintEntity
  local next_ent
  ---@type condinfo
  local next_condinfo
  ---@type DeciderCombinatorCondition[]
  local next_conditions
  ---@type has_eaches
  local has_eaches = {
    red = false,
    green = false,
    sum = false,
  }

  for _, condition in pairs(from_params.conditions) do
    if condition.compare_type == "or" or not next_ent then
      -- new combinator
      next_conditions = {condition}
      next_condinfo = {
        conditions = next_conditions,
        has_eaches = {
          red = false,
          green = false,
          sum = false,
        }
      }
      local entity_number = #entities+1
      ---@type BlueprintWire[]?
      local wires
      if entity_number == 1 then
        -- loopback wires if the original had them
        local green_in = from.get_circuit_network(defines.wire_connector_id.combinator_input_green)
        local green_out = from.get_circuit_network(defines.wire_connector_id.combinator_output_green)
        if green_in and green_out and green_in.network_id == green_out.network_id then
          wires = wires or {}
          wires[#wires+1] = { entity_number, defines.wire_connector_id.combinator_input_green, entity_number, defines.wire_connector_id.combinator_output_green}
        end

        local red_in = from.get_circuit_network(defines.wire_connector_id.combinator_input_red)
        local red_out = from.get_circuit_network(defines.wire_connector_id.combinator_output_red)
        if red_in and red_out and red_in.network_id == red_out.network_id then
          wires = wires or {}
          wires[#wires+1] = { entity_number, defines.wire_connector_id.combinator_input_red, entity_number, defines.wire_connector_id.combinator_output_red}
        end

      else
        wires = {
          { entity_number-1, defines.wire_connector_id.combinator_input_green, entity_number, defines.wire_connector_id.combinator_input_green },
          { entity_number-1, defines.wire_connector_id.combinator_input_red, entity_number, defines.wire_connector_id.combinator_input_red },
          { entity_number-1, defines.wire_connector_id.combinator_output_green, entity_number, defines.wire_connector_id.combinator_output_green },
          { entity_number-1, defines.wire_connector_id.combinator_output_red, entity_number, defines.wire_connector_id.combinator_output_red },
        }
      end
      next_ent = {
        entity_number = entity_number,
        name = "decider-combinator",
        position = position(from.position, from.direction, entity_number-1),
        direction = from.direction,
        control_behavior = {
          decider_conditions = {
            conditions = next_conditions,
            outputs = from_params.outputs,
          }
        },
        wires = wires,
      }
      entities[entity_number]=next_ent
      condinfos[entity_number]=next_condinfo
    else
      -- just accumulate conditions
      next_conditions[#next_conditions+1] = condition
    end

    local first_signal = condition.first_signal
    if first_signal and first_signal.type=="virtual" and first_signal.name=="signal-each" then
      seen_each(has_eaches, next_condinfo.has_eaches, condition.first_signal_networks)
    end
    local second_signal = condition.second_signal
    if second_signal and second_signal.type=="virtual" and second_signal.name=="signal-each" then
      seen_each(has_eaches, next_condinfo.has_eaches, condition.second_signal_networks)
    end
  end

  -- add any dummy conditions needed to preserve each-ness after the split
  for _, condinfo in pairs(condinfos) do
    if has_eaches.sum and not condinfo.has_eaches.sum then
      condinfo.conditions[#condinfo.conditions+1] = and_each.sum
    end
    if has_eaches.red and not condinfo.has_eaches.red then
      condinfo.conditions[#condinfo.conditions+1] = and_each.red
    end
    if has_eaches.green and not condinfo.has_eaches.green then
      condinfo.conditions[#condinfo.conditions+1] = and_each.green
    end
  end
  stack.set_blueprint_entities(entities)
  player.play_sound({path="or-extractor-blueprint-create"})
end)
