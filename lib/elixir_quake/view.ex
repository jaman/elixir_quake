defmodule ElixirQuake.View do
  @moduledoc """
  What the player sees, gathered from the game each tick for `ElixirQuake.Render`:

    * `:map`, `:time`
    * `:camera` — `%{origin:, angles:}`, the eye with bob, kick and death roll worked in
    * `:entities` — each drawn thing in a leaf the eye can see, as `%{model:, frame:,
      skin:, origin:, angles:, effects:, entity:}`; `:statics`, the scenery made static,
      likewise
    * `:weapon` — the held weapon, `%{model:, frame:}`, or `nil`
    * `:beams`, `:particles`
    * `:styles` — the scale of each of the 64 light styles now, 256 normal
    * `:stats` — as `ElixirQuake.StatusBar.draw/2` takes, with `:pain_until`
    * `:washes`, `:notify`, `:center`, `:intermission`, `:finale`, `:tally`, `:over`
  """

  alias Cauldron3D.Vec
  alias ElixirQuake.{Assets, Effects}
  alias QuakeServer.{Edicts, Models, Server, World}

  @audio_scale 33.0

  @doc "The view of `state`, an `ElixirQuake.Game` state."
  @spec build(map()) :: map()
  def build(%{server: server, fx: fx, time: time} = state) do
    stats = stats(server)
    contents = World.point_contents(server, eye(server))
    seen = Cauldron3D.Bsp.leaf_at(server.bsp, eye(server))

    %{
      map: server.map,
      time: time,
      camera: camera(state, stats),
      entities: server |> entities() |> Enum.filter(&in_sight?(server, seen, &1)),
      statics: Enum.filter(server.statics, &in_sight?(server, seen, &1)),
      weapon: weapon(server, fx, stats),
      beams: beams(server, fx),
      particles: fx.particles,
      styles: styles(server, time),
      stats: Map.put(stats, :pain_until, fx.pain_until),
      washes: Effects.washes(fx, stats.items, contents),
      notify: Enum.map(fx.notify, &elem(&1, 0)),
      center: fx.center && elem(fx.center, 0),
      intermission: fx.intermission,
      finale: fx.finale,
      tally: tally(server, server.time),
      over: Map.get(state, :over, false)
    }
  end

  @doc "World units per sound placement unit."
  @spec audio_scale() :: float()
  def audio_scale, do: @audio_scale

  @doc "The effect flags of `entity`'s model: trails and spinning."
  @spec model_flags(Server.t(), non_neg_integer()) :: integer()
  def model_flags(%Server{} = server, entity) do
    case Models.get(server, Edicts.int(server, entity, "modelindex")) do
      %{kind: :alias, name: name} -> Assets.model(name).data.flags
      _ -> 0
    end
  end

  defp in_sight?(server, seen, %{entity: entity, model: "*" <> _}) do
    server.bsp
    |> Cauldron3D.Bsp.leaves_touching(
      Edicts.vector(server, entity, "absmin"),
      Edicts.vector(server, entity, "absmax")
    )
    |> Enum.any?(&Cauldron3D.Bsp.sees?(server.bsp, seen, &1))
  end

  defp in_sight?(server, seen, %{origin: origin}),
    do: Cauldron3D.Bsp.sees?(server.bsp, seen, Cauldron3D.Bsp.leaf_at(server.bsp, origin))

  defp eye(server),
    do: Vec.add(Edicts.vector(server, 1, "origin"), Edicts.vector(server, 1, "view_ofs"))

  defp camera(%{fx: fx, angles: {pitch, yaw, _}, server: server, time: time}, stats) do
    if fx.intermission do
      %{origin: Edicts.vector(server, 1, "origin"), angles: Edicts.vector(server, 1, "angles")}
    else
      {vx, vy, _} = Edicts.vector(server, 1, "velocity")
      bob = bob(:math.sqrt(vx * vx + vy * vy), time)
      {px, py, pz} = Edicts.vector(server, 1, "punchangle")
      {kick_pitch, kick_roll} = Effects.kick(fx, time)
      roll = if stats.health <= 0, do: 80.0, else: roll(server, yaw) + kick_roll
      {ex, ey, ez} = eye(server)

      %{
        origin: {ex, ey, ez + bob},
        angles: {pitch + px + kick_pitch, yaw + py, roll + pz},
        bob: bob
      }
    end
  end

  defp bob(speed, time) do
    cycle = :math.fmod(time, 0.6) / 0.6

    cycle =
      if cycle < 0.5,
        do: :math.pi() * cycle / 0.5,
        else: :math.pi() + :math.pi() * (cycle - 0.5) / 0.5

    bob = speed * 0.02
    (bob * 0.3 + bob * 0.7 * :math.sin(cycle)) |> max(-7.0) |> min(4.0)
  end

  defp roll(server, yaw) do
    {_, right, _} = QuakeServer.Angles.vectors({0.0, yaw, 0.0})
    side = Vec.dot(Edicts.vector(server, 1, "velocity"), right)
    sign = if side < 0, do: -1, else: 1
    side = abs(side)
    sign * if(side < 200, do: side * 2.0 / 200, else: 2.0)
  end

  defp entities(server) do
    for entity <- Edicts.live(server),
        entity > 1,
        Edicts.int(server, entity, "modelindex") != 0,
        model = Edicts.string(server, entity, "model"),
        model != "" do
      %{
        entity: entity,
        model: model,
        frame: Edicts.int(server, entity, "frame"),
        skin: Edicts.int(server, entity, "skin"),
        origin: Edicts.vector(server, entity, "origin"),
        angles: Edicts.vector(server, entity, "angles"),
        effects: Edicts.int(server, entity, "effects")
      }
    end
  end

  defp weapon(server, fx, stats) do
    model = Edicts.string(server, 1, "weaponmodel")

    cond do
      fx.intermission != nil -> nil
      stats.health <= 0 -> nil
      Bitwise.band(stats.items, 524_288) != 0 -> nil
      model == "" -> nil
      true -> %{model: model, frame: Edicts.int(server, 1, "weaponframe")}
    end
  end

  defp beams(server, fx) do
    Enum.map(fx.beams, fn beam ->
      if beam.entity == 1, do: %{beam | from: Edicts.vector(server, 1, "origin")}, else: beam
    end)
  end

  defp styles(server, time) do
    for style <- 0..63 do
      case Map.get(server.lightstyles, style) do
        nil -> 264
        "" -> 256
        pattern -> (:binary.at(pattern, rem(trunc(time * 10), byte_size(pattern))) - ?a) * 22
      end
    end
    |> List.to_tuple()
  end

  defp stats(server) do
    flags = trunc(QuakeC.float(QuakeC.global(server.qc, "serverflags")))

    %{
      health: Edicts.float(server, 1, "health"),
      armor: Edicts.float(server, 1, "armorvalue"),
      ammo: Edicts.float(server, 1, "currentammo"),
      items: Bitwise.bor(Edicts.int(server, 1, "items"), Bitwise.bsl(flags, 28)),
      weapon: Edicts.int(server, 1, "weapon"),
      shells: Edicts.float(server, 1, "ammo_shells"),
      nails: Edicts.float(server, 1, "ammo_nails"),
      rockets: Edicts.float(server, 1, "ammo_rockets"),
      cells: Edicts.float(server, 1, "ammo_cells")
    }
  end

  defp tally(server, time) do
    g = &trunc(QuakeC.float(QuakeC.global(server.qc, &1)))

    %{
      seconds: trunc(time),
      secrets: g.("found_secrets"),
      total_secrets: g.("total_secrets"),
      monsters: g.("killed_monsters"),
      total_monsters: g.("total_monsters")
    }
  end
end
