-- OBS renders the scene at the configured FPS even when no output consumes
-- frames. Keep FPS low while streaming, recording, replay buffer and virtual
-- camera are all off.

local obs = obslua

local ACTIVE_FPS = 60
local IDLE_FPS = 1
-- Outputs report stop before their end-capture thread detaches from video,
-- and video can't be reset while anything is attached.
local VIDEO_RELEASE_TIMEOUT_MS = 1000
-- Same delay OBS uses for its own virtual camera restart.
local VCAM_RESTART_DELAY_MS = 100

local vcam_restart_pending = false
local keep_video_on_unload = false

local function video_fps()
  local ovi = obs.obs_video_info()
  if not obs.obs_get_video_info(ovi) then
    return nil
  end
  return ovi.fps_num / ovi.fps_den
end

local function write_fps_config(fps)
  local config = obs.obs_frontend_get_profile_config()
  obs.config_set_uint(config, "Video", "FPSType", 1)
  obs.config_set_uint(config, "Video", "FPSInt", fps)
end

local function outputs_active()
  return obs.obs_frontend_streaming_active()
    or obs.obs_frontend_recording_active()
    or obs.obs_frontend_replay_buffer_active()
    or obs.obs_frontend_virtualcam_active()
end

-- Must run on the UI thread: Lua timers run on the graphics thread, and
-- resetting video from there would join the thread from itself.
local function set_fps(fps)
  local old_fps = video_fps()
  if old_fps == fps then
    return true
  end

  local waited_ms = 0
  while obs.obs_video_active() and waited_ms < VIDEO_RELEASE_TIMEOUT_MS do
    obs.os_sleep_ms(10)
    waited_ms = waited_ms + 10
  end

  write_fps_config(fps)
  obs.obs_frontend_reset_video()
  if video_fps() == fps then
    obs.script_log(obs.LOG_INFO, "FPS set to " .. fps)
    return true
  end

  -- Keep Settings in sync with what is actually running.
  if old_fps then
    write_fps_config(math.floor(old_fps + 0.5))
  end
  obs.script_log(obs.LOG_WARNING, "Failed to set FPS to " .. fps)
  return false
end

local function set_idle_fps_if_unused()
  if not outputs_active() then
    set_fps(IDLE_FPS)
  end
end

local function start_vcam()
  obs.remove_current_callback()
  vcam_restart_pending = false
  obs.obs_frontend_start_virtualcam()
end

local function stop_vcam()
  obs.remove_current_callback()
  obs.obs_frontend_stop_virtualcam()
end

local function on_event(event)
  if event == obs.OBS_FRONTEND_EVENT_STREAMING_STARTING
    or event == obs.OBS_FRONTEND_EVENT_RECORDING_STARTING
    or event == obs.OBS_FRONTEND_EVENT_REPLAY_BUFFER_STARTING
  then
    set_fps(ACTIVE_FPS)

  elseif event == obs.OBS_FRONTEND_EVENT_VIRTUALCAM_STARTED then
    -- There is no "starting" event for the virtual camera and video can't be
    -- reset while it runs, so restart it. Stopping right from this callback
    -- would re-enter OBS's own start handler.
    if video_fps() ~= ACTIVE_FPS and not vcam_restart_pending then
      vcam_restart_pending = true
      obs.timer_add(stop_vcam, 1)
    end

  elseif event == obs.OBS_FRONTEND_EVENT_VIRTUALCAM_STOPPED
    and vcam_restart_pending
  then
    if set_fps(ACTIVE_FPS) then
      obs.timer_add(start_vcam, VCAM_RESTART_DELAY_MS)
    else
      vcam_restart_pending = false
    end

  elseif event == obs.OBS_FRONTEND_EVENT_STREAMING_STOPPED
    or event == obs.OBS_FRONTEND_EVENT_RECORDING_STOPPED
    or event == obs.OBS_FRONTEND_EVENT_REPLAY_BUFFER_STOPPED
    or event == obs.OBS_FRONTEND_EVENT_VIRTUALCAM_STOPPED
    or event == obs.OBS_FRONTEND_EVENT_FINISHED_LOADING
    or event == obs.OBS_FRONTEND_EVENT_SCENE_COLLECTION_CHANGED
    or event == obs.OBS_FRONTEND_EVENT_PROFILE_CHANGED
  then
    set_idle_fps_if_unused()

  elseif event == obs.OBS_FRONTEND_EVENT_PROFILE_CHANGING then
    -- The old profile is saved during the switch.
    write_fps_config(ACTIVE_FPS)

  elseif event == obs.OBS_FRONTEND_EVENT_SCENE_COLLECTION_CHANGING then
    -- Scripts belong to a scene collection and get reloaded during the
    -- switch; resetting video mid-switch is unsafe.
    keep_video_on_unload = true

  elseif event == obs.OBS_FRONTEND_EVENT_SCRIPTING_SHUTDOWN then
    keep_video_on_unload = true
    write_fps_config(ACTIVE_FPS)
    obs.config_save_safe(obs.obs_frontend_get_profile_config(), "tmp", nil)
  end
end

function script_description()
  return "Sets FPS to " .. IDLE_FPS .. " while no output is active and to "
    .. ACTIVE_FPS .. " for streaming, recording, replay buffer and virtual "
    .. "camera. The virtual camera is restarted once after its start since "
    .. "video can't be reset while it runs."
end

function script_load(_)
  obs.obs_frontend_add_event_callback(on_event)

  -- On OBS startup and scene collection switch scripts are loaded before
  -- scenes, and FINISHED_LOADING / SCENE_COLLECTION_CHANGED follows.
  -- A current scene means the script was added at runtime.
  local scene = obs.obs_frontend_get_current_scene()
  if scene then
    obs.obs_source_release(scene)
    set_idle_fps_if_unused()
  end
end

function script_unload()
  write_fps_config(ACTIVE_FPS)
  -- A pending restart timer would make the graphics thread wait for this
  -- script's lock while the reset joins that thread.
  if not keep_video_on_unload and not vcam_restart_pending then
    set_fps(ACTIVE_FPS)
  end
end
