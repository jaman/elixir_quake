defmodule ElixirQuake.Game do
  @moduledoc """
  Quake as a `Cauldron2D.Game`, single player: the held actions become Quake commands,
  the server runs a frame each tick, and what it reports (its events; the player's packet
  is taken and left unread each frame) becomes the screen's effects
  and sounds.

      Cauldron2D.World.start_link(game: ElixirQuake.Game, game_opts: [map: "start", skill: 1], hz: 60)

  Options: `:map` (default `"start"`, the episode and skill hub) and `:skill` (0 to 3,
  default 1). Game files must have been loaded with `ElixirQuake.Assets.load/1`.

  The actions read are `:forward`, `:back`, `:strafe_left`, `:strafe_right`,
  `:turn_left`, `:turn_right`, `:look_up`, `:look_down`, `:center_view`, `:run`,
  `:fire`, `:jump`, `:next_weapon`, `:prev_weapon` and `:weapon_1` to `:weapon_8`; a
  stick's `strength` scales moving, turning and looking. The input's `:options` with
  `always_run: true` runs without the run key; a `:request` of `{n, :new_game}` starts a
  new game on `start`, once for each `n`. The program's level changes, restarts after
  death and the end of an episode are followed.
  """

  @behaviour Cauldron2D.Game

  alias Cauldron3D.Vec
  alias ElixirQuake.{Effects, View}
  alias QuakeServer.{Edicts, Outbox, Server}

  @turn 140.0
  @look 150.0

  @impl true
  def init(opts) do
    skill = Keyword.get(opts, :skill, 1)

    %{
      server:
        Server.start(Keyword.get(opts, :map, "start"), source: ElixirQuake.Source, skill: skill),
      skill: skill,
      parms: nil,
      angles: {0.0, 0.0, 0.0},
      input: %{held: MapSet.new()},
      previous: MapSet.new(),
      fx: %Effects{},
      time: 0.0,
      events: [],
      joined: nil,
      over: false,
      request: 0
    }
  end

  @impl true
  def join(state, id, _props) do
    server = Server.connect(state.server, state.parms)
    {:ok, %{state | joined: id, server: server, parms: server.parms} |> fix_angles(true)}
  end

  @impl true
  def leave(state, _id), do: %{state | joined: nil}

  @impl true
  def handle_input(state, _id, input) do
    case Map.get(input, :request) do
      {n, :new_game} when n > state.request -> new_game(%{state | input: input, request: n})
      _ -> %{state | input: input}
    end
  end

  @impl true
  def step(%{over: true} = state, _dt), do: state

  def step(state, dt) do
    angles = turn(state, dt)
    command = command(state, angles)
    server = Server.frame(state.server, dt, command)
    {events, server} = Server.drain(server)
    {_packet, server} = Outbox.take(server, 1)
    time = state.time + dt

    %{state | server: server, angles: angles, time: time}
    |> take_in(events)
    |> hurt()
    |> trail()
    |> then(&%{&1 | fx: Effects.run(&1.fx, dt, time)})
    |> sound_out()
    |> fix_angles(false)
    |> follow(events)
    |> Map.put(:previous, held(state))
  end

  @impl true
  def view(state, _id), do: View.build(state)

  @impl true
  def drain_events(state), do: {Enum.reverse(state.events), %{state | events: []}}

  defp held(state), do: Map.get(state.input, :held, MapSet.new())

  defp running?(state),
    do:
      MapSet.member?(held(state), :run) or
        Map.get(Map.get(state.input, :options, %{}), :always_run, false)

  defp new_game(state) do
    server =
      "start" |> Server.start(source: ElixirQuake.Source, skill: state.skill) |> Server.connect()

    %{state | server: server, parms: server.parms, fx: %Effects{}, over: false}
    |> fix_angles(true)
  end

  defp strength(state, action) do
    if MapSet.member?(held(state), action),
      do: Map.get(Map.get(state.input, :strength, %{}), action, 1.0),
      else: 0.0
  end

  defp pressed?(state, action),
    do: MapSet.member?(held(state), action) and not MapSet.member?(state.previous, action)

  defp turn(state, dt) do
    {pitch, yaw, roll} = state.angles
    speed = if running?(state), do: 1.5, else: 1.0
    yaw = yaw + (strength(state, :turn_left) - strength(state, :turn_right)) * @turn * speed * dt
    pitch = pitch + (strength(state, :look_down) - strength(state, :look_up)) * @look * speed * dt
    pitch = if pressed?(state, :center_view), do: 0.0, else: pitch |> max(-70.0) |> min(80.0)
    {pitch, :math.fmod(yaw + 360.0, 360.0), roll}
  end

  defp command(state, angles) do
    run = if running?(state), do: 2.0, else: 1.0

    %{
      forward: 200 * run * (strength(state, :forward) - strength(state, :back)),
      side: 350 * run * (strength(state, :strafe_right) - strength(state, :strafe_left)),
      up: 0.0,
      angles: angles,
      attack: MapSet.member?(held(state), :fire),
      jump: MapSet.member?(held(state), :jump),
      impulse: impulse(state)
    }
  end

  defp impulse(state) do
    picks = for n <- 1..8, do: {:"weapon_#{n}", n}

    Enum.find_value([{:next_weapon, 10}, {:prev_weapon, 12} | picks], 0, fn {action, number} ->
      if pressed?(state, action), do: number
    end)
  end

  defp context(state) do
    %{time: state.time, origin: Edicts.vector(state.server, 1, "origin"), angles: state.angles}
  end

  defp take_in(state, events) do
    ctx = context(state)
    %{state | fx: Enum.reduce(events, state.fx, &Effects.handle(&2, &1, ctx))}
  end

  defp hurt(%{server: server} = state) do
    take = Edicts.float(server, 1, "dmg_take")
    save = Edicts.float(server, 1, "dmg_save")

    if take > 0 or save > 0 do
      from = Edicts.vector(server, Edicts.int(server, 1, "dmg_inflictor"), "origin")
      fx = Effects.damage(state.fx, save, take, from, context(state))
      server = server |> Edicts.put(1, "dmg_take", 0.0) |> Edicts.put(1, "dmg_save", 0.0)
      %{state | fx: fx, server: server}
    else
      state
    end
  end

  defp trail(%{server: server} = state) do
    things =
      for entity <- Edicts.live(server),
          entity > 1,
          flags = View.model_flags(server, entity),
          flags != 0,
          do: {entity, Edicts.vector(server, entity, "origin"), flags}

    %{state | fx: Effects.trails(state.fx, things, state.time)}
  end

  defp sound_out(state) do
    {sounds, fx} = Effects.take_sounds(state.fx)

    listener =
      Vec.add(
        Edicts.vector(state.server, 1, "origin"),
        Edicts.vector(state.server, 1, "view_ofs")
      )

    events = Enum.reduce(sounds, state.events, &[sound_event(&1, listener) | &2])
    %{state | fx: fx, events: events}
  end

  defp sound_event(
         %{name: name, volume: volume, attenuation: attenuation, origin: origin},
         listener
       ) do
    key = {:sound, name, Float.round(volume, 1)}

    if attenuation == 0 do
      key
    else
      {ox, oy, _} = Vec.add(listener, Vec.scale(Vec.sub(origin, listener), attenuation))
      {key, {ox / View.audio_scale(), oy / View.audio_scale()}}
    end
  end

  defp fix_angles(%{server: server} = state, joining?) do
    if joining? or Edicts.float(server, 1, "fixangle") != 0 do
      {pitch, yaw, _} = Edicts.vector(server, 1, "angles")
      %{state | angles: {pitch, yaw, 0.0}, server: Edicts.put(server, 1, "fixangle", 0.0)}
    else
      state
    end
  end

  defp follow(state, events) do
    command =
      Enum.find_value(events, fn
        {:command, text} -> String.trim(text)
        _ -> nil
      end)

    cond do
      state.server.changelevel != nil ->
        change_level(state, state.server.changelevel)

      command == "restart" ->
        restart(state)

      command in ["disconnect", "killserver"] ->
        %{state | over: true}

      is_binary(command) and String.starts_with?(command, "changelevel ") ->
        change_level(state, String.trim_leading(command, "changelevel "))

      true ->
        state
    end
  end

  defp change_level(state, map) do
    parms = Server.change_parms(state.server)
    flags = QuakeC.float(QuakeC.global(state.server.qc, "serverflags"))

    server =
      Server.start(map, source: ElixirQuake.Source, skill: state.skill, serverflags: trunc(flags))
      |> Server.connect(parms)

    %{state | server: server, parms: parms, fx: %Effects{}} |> fix_angles(true)
  end

  defp restart(state) do
    flags = QuakeC.float(QuakeC.global(state.server.qc, "serverflags"))

    server =
      Server.start(state.server.map,
        source: ElixirQuake.Source,
        skill: state.skill,
        serverflags: trunc(flags)
      )
      |> Server.connect(state.parms)

    %{state | server: server, fx: %Effects{}} |> fix_angles(true)
  end
end
