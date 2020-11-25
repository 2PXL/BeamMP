local M = {state={}}

local logTag = 'multiplayer'
log("I", "Multiplayer Gamemode", "Gamemode Loaded")

local inputActionFilter = extensions.core_input_actionFilter

local function startMultiplayerHelper (level, startPointName)
  core_gamestate.requestEnterLoadingScreen(logTag .. '.startMultiplayerHelper')
  loadGameModeModules()
  M.state = {}
  M.state.multiplayerActive = true

  local levelPath = level
  if type(level) == 'table' then
    setSpawnpoint.setDefaultSP(startPointName, level.levelName)
    levelPath = level.misFilePath
  end

  inputActionFilter.clear(0)

  core_levels.startLevel(levelPath)
  core_gamestate.requestExitLoadingScreen(logTag .. '.startMultiplayerHelper')
end

local function startAssociatedFlowgraph(level)
-- load flowgaphs associated with this level.
  if level.flowgraphs then
    for _, absolutePath in ipairs(level.flowgraphs or {}) do
      local relativePath = level.misFilePath..absolutePath
      local path = FS:fileExists(absolutePath) and absolutePath or (FS:fileExists(relativePath) and (relativePath) or nil)
      if path then
        local mgr = core_flowgraphManager.loadManager(path)
        core_flowgraphManager.startOnLoadingScreenFadeout(mgr)
        mgr.stopRunningOnClientEndMission = true -- make mgr self-destruct when level is ended.
        mgr.removeOnStopping = true -- make mgr self-destruct when level is ended.
        log("I", "Flowgraph loading", "Loaded level-associated flowgraph from file "..dumps(path))
       else
         log("E", "Flowgraph loading", "Could not find file in either '" .. absolutePath.."' or '" .. relativePath.."'!")
       end
    end
  end
end

local function startMultiplayer(level, startPointName, wasDelayed)
  core_gamestate.requestEnterLoadingScreen(logTag)
  -- if this was a delayed start, load the FGs now.
  if wasDelayed then
    startAssociatedFlowgraph(level)
  end

  -- this is to prevent bug where multiplayer is started while a different level is still loaded.
  -- Loading the new multiplayer causes the current loaded multiplayer to unload which breaks the new multiplayer
  local delaying = false
  if scenetree.MissionGroup then
    log('D', logTag, 'Delaying start of multiplayer until current level is unloaded...')
    M.triggerDelayedStart = function()
      log('D', logTag, 'Triggering a delayed start of multiplayer...')
      M.triggerDelayedStart = nil
      startMultiplayer(level, startPointName, true)
    end
    endActiveGameMode(M.triggerDelayedStart)
    delaying = true
  elseif not core_gamestate.getLoadingStatus(logTag .. '.startMultiplayerHelper') then -- remove again at some point
    startMultiplayerHelper(level, startPointName)
    core_gamestate.requestExitLoadingScreen(logTag)
  end
  -- if there was no delaying and the function call itself didnt
  -- come from a delayed start, load the FGs (starting from main menu)
  if not wasDelayed and not delaying then
    startAssociatedFlowgraph(level)
  end
end

local function startMultiplayerByName(levelName)
  for i, v in ipairs(core_levels.getList()) do
    if v.levelName == levelName then
      startMultiplayer(v)
      return true
    end
  end
  return false
end

local function onClientPreStartMission(mission)
  local path, file, ext = path.splitWithoutExt(mission)
  file = path .. 'mainLevel'
  if not FS:fileExists(file..'.lua') then return end
  extensions.loadAtRoot(file,"")
  if mainLevel and mainLevel.onClientPreStartMission then
    mainLevel.onClientPreStartMission(mission)
  end
end

local function onClientStartMission(mission)
  local path, file, ext = path.splitWithoutExt(mission)
  file = path .. 'mainLevel'

  if M.state.multiplayerActive then
    extensions.hook('onMultiplayerLoaded', mission)

    local ExplorationCheckpoints = scenetree.findObject("ExplorationCheckpointsActionMap")
    if ExplorationCheckpoints then
      ExplorationCheckpoints:push()
    end
  end
end

local function onClientEndMission(mission)
  if M.state.multiplayerActive then
    M.state.multiplayerActive = false
    local ExplorationCheckpoints = scenetree.findObject("ExplorationCheckpointsActionMap")
    if ExplorationCheckpoints then
      ExplorationCheckpoints:pop()
    end
  end

  if not mainLevel then return end
  local path, file, ext = path.splitWithoutExt(mission)
  extensions.unload(path .. 'mainLevel')
end



-- Resets previous vehicle alpha when switching between different vehicles
-- Used to fix multipart highlighting when switching vehicles
local function onVehicleSwitched(oldId, newId, player)
  if oldId then
    local veh = be:getObjectByID(oldId)
    if veh then
      extensions.core_vehicle_partmgmt.selectReset()
    end
  end
end

local function onResetGameplay(playerID)
  local scenario = scenario_scenarios and scenario_scenarios.getScenario()
  local campaign = campaign_campaigns and campaign_campaigns.getCampaign()
  -- check if a flowgraph can consume this action.
  local fg = nil
  for _, mgr in ipairs(core_flowgraphManager.getAllManagers()) do
    fg = fg or mgr:hasNodeForHook('onResetGameplay')
  end
  if not scenario and not campaign and not fg then
    be:resetVehicle(playerID)
  end
end

-- public interface
M.startMultiplayer           = startMultiplayer
M.startMultiplayerByName     = startMultiplayerByName
M.onClientPreStartMission    = onClientPreStartMission
M.onClientStartMission       = onClientStartMission
M.onClientEndMission         = onClientEndMission
M.onVehicleSwitched          = onVehicleSwitched
M.onResetGameplay            = onResetGameplay

return M
