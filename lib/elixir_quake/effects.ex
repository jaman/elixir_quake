defmodule ElixirQuake.Effects do
  @moduledoc """
  What the player's screen shows besides the world: particles and trails, lightning
  beams, the colour washes of damage, bonuses, power-ups and liquids, the kick of being
  hit, the pain face, printed messages, the intermission and the closing text.

      effects = ElixirQuake.Effects.handle(effects, event, context)
      effects = ElixirQuake.Effects.run(effects, seconds, now)

  `context` is `%{time:, origin:, angles:}`, the player's position and view.
  """

  alias Cauldron3D.Vec
  alias ElixirQuake.Particles
  alias QuakeServer.Angles

  defstruct particles: [],
            beams: [],
            trails: %{},
            damage: {{255, 0, 0}, 0.0},
            bonus: 0.0,
            kick: %{until: 0.0, roll: 0.0, pitch: 0.0},
            notify: [],
            pending: "",
            center: nil,
            pain_until: 0.0,
            intermission: nil,
            finale: nil,
            sounds: []

  @type t :: %__MODULE__{}

  @trails [
    {1, :rocket},
    {2, :smoke},
    {4, :blood},
    {32, :slight_blood},
    {16, :tracer},
    {64, :tracer2},
    {128, :voor}
  ]
  @beams %{
    lightning1: "progs/bolt.mdl",
    lightning2: "progs/bolt2.mdl",
    lightning3: "progs/bolt3.mdl",
    beam: "progs/beam.mdl"
  }

  @doc "Take in one server event."
  @spec handle(t(), term(), map()) :: t()
  def handle(%__MODULE__{} = fx, {:sound, sound}, _context),
    do: %{fx | sounds: [sound | fx.sounds]}

  def handle(fx, {:particles, %{origin: o, direction: d, colour: c, count: n}}, ctx),
    do: %{fx | particles: Particles.effect(fx.particles, o, d, c, n, ctx.time)}

  def handle(fx, {:temp, kind, data}, ctx), do: temp(fx, kind, data, ctx)
  def handle(fx, {:print, :notify, text}, ctx), do: notify(fx, text, ctx.time)

  def handle(fx, {:print, :center, text}, ctx),
    do: %{
      fx
      | center:
          {String.split(text, "\n"), ctx.time + 2.0 + 0.1 * length(String.split(text, "\n"))}
    }

  def handle(fx, {:stuff, "bf" <> _}, _ctx), do: %{fx | bonus: 50.0}
  def handle(fx, :intermission, ctx), do: %{fx | intermission: ctx.time}

  def handle(fx, {:finale, text}, ctx),
    do: %{fx | finale: {text, ctx.time}, intermission: fx.intermission || ctx.time}

  def handle(fx, _event, _ctx), do: fx

  @doc "Being hurt: `armor` and `blood` points taken, from `from`."
  @spec damage(t(), number(), number(), Vec.t(), map()) :: t()
  def damage(%__MODULE__{} = fx, armor, blood, from, ctx) do
    count = max(blood * 0.5 + armor * 0.5, 10)
    {_, percent} = fx.damage

    colour =
      cond do
        armor > blood -> {200, 100, 100}
        armor > 0 -> {220, 50, 50}
        true -> {255, 0, 0}
      end

    direction = Vec.normalize(Vec.sub(from, ctx.origin))
    {forward, right, _} = Angles.vectors(ctx.angles)

    %{
      fx
      | damage: {colour, min(percent + 3 * count, 150.0)},
        pain_until: ctx.time + 0.2,
        kick: %{
          until: ctx.time + 0.5,
          roll: count * Vec.dot(direction, right) * 0.6,
          pitch: count * Vec.dot(direction, forward) * 0.6
        }
    }
  end

  @doc "Lay trails behind the moving things that leave them, as `{entity, origin, model_flags}`."
  @spec trails(t(), [{integer(), Vec.t(), integer()}], float()) :: t()
  def trails(%__MODULE__{} = fx, things, now) do
    {particles, trails} =
      Enum.reduce(things, {fx.particles, %{}}, fn {entity, origin, flags}, acc ->
        lay(acc, fx.trails, {entity, origin, trail_kind(flags)}, now)
      end)

    %{fx | particles: particles, trails: trails}
  end

  defp trail_kind(flags) do
    case Enum.find(@trails, fn {bit, _} -> Bitwise.band(flags, bit) != 0 end) do
      nil -> nil
      {_, kind} -> kind
    end
  end

  defp lay(acc, _last, {_entity, _origin, nil}, _now), do: acc

  defp lay({particles, seen}, last, {entity, origin, kind}, now) do
    from = Map.get(last, entity, origin)
    {Particles.trail(particles, from, origin, kind, now), Map.put(seen, entity, origin)}
  end

  @doc "Move everything on by `seconds` to `now`."
  @spec run(t(), float(), float()) :: t()
  def run(%__MODULE__{} = fx, seconds, now) do
    {colour, percent} = fx.damage

    %{
      fx
      | particles: Particles.run(fx.particles, seconds, now),
        beams: Enum.filter(fx.beams, &(&1.until > now)),
        damage: {colour, max(percent - seconds * 150, 0.0)},
        bonus: max(fx.bonus - seconds * 100, 0.0),
        notify: Enum.filter(fx.notify, fn {_, until} -> until > now end),
        center: if(fx.center && elem(fx.center, 1) > now, do: fx.center)
    }
  end

  @doc "The sounds taken in since the last call, oldest first, and the effects without them."
  @spec take_sounds(t()) :: {[map()], t()}
  def take_sounds(%__MODULE__{} = fx), do: {Enum.reverse(fx.sounds), %{fx | sounds: []}}

  @doc """
  The colour washes in force, as `[{{r, g, b}, percent}]`, given the player's items and
  the contents at the eye.
  """
  @spec washes(t(), integer(), integer()) :: [{{byte(), byte(), byte()}, float()}]
  def washes(%__MODULE__{} = fx, items, contents) do
    liquid =
      case contents do
        -5 -> [{{255, 80, 0}, 150.0}]
        -4 -> [{{0, 25, 5}, 150.0}]
        -3 -> [{{130, 80, 50}, 128.0}]
        _ -> []
      end

    powers =
      [
        {4_194_304, {{0, 0, 255}, 30.0}},
        {2_097_152, {{0, 255, 0}, 20.0}},
        {524_288, {{100, 100, 100}, 100.0}},
        {1_048_576, {{255, 255, 0}, 30.0}}
      ]
      |> Enum.filter(fn {bit, _} -> Bitwise.band(items, bit) != 0 end)
      |> Enum.map(&elem(&1, 1))

    liquid ++ [fx.damage, {{215, 186, 69}, fx.bonus}] ++ powers
  end

  @doc "The view kick of being hit at `now`, as `{pitch, roll}` in degrees."
  @spec kick(t(), float()) :: {float(), float()}
  def kick(%__MODULE__{kick: kick}, now) do
    left = kick.until - now
    if left > 0, do: {kick.pitch * left / 0.5, kick.roll * left / 0.5}, else: {0.0, 0.0}
  end

  defp temp(fx, kind, %{origin: origin}, ctx)
       when kind in [:spike, :superspike, :gunshot, :wizspike, :knightspike] do
    {colour, count} =
      case kind do
        :spike -> {0, 10}
        :wizspike -> {20, 30}
        :knightspike -> {226, 20}
        _ -> {0, 20}
      end

    fx = %{
      fx
      | particles:
          Particles.effect(fx.particles, origin, {0.0, 0.0, 0.0}, colour, count, ctx.time)
    }

    case kind do
      :wizspike ->
        place(fx, "wizard/hit.wav", origin)

      :knightspike ->
        place(fx, "hknight/hit.wav", origin)

      :gunshot ->
        fx

      _ ->
        place(
          fx,
          Enum.random([
            "weapons/tink1.wav",
            "weapons/tink1.wav",
            "weapons/tink1.wav",
            "weapons/tink1.wav",
            "weapons/ric1.wav",
            "weapons/ric2.wav",
            "weapons/ric3.wav"
          ]),
          origin
        )
    end
  end

  defp temp(fx, :explosion, %{origin: origin}, ctx),
    do:
      %{fx | particles: Particles.explosion(fx.particles, origin, ctx.time)}
      |> place("weapons/r_exp3.wav", origin)

  defp temp(fx, :explosion2, %{origin: origin}, ctx),
    do:
      %{fx | particles: Particles.explosion(fx.particles, origin, ctx.time)}
      |> place("weapons/r_exp3.wav", origin)

  defp temp(fx, :tarexplosion, %{origin: origin}, ctx),
    do:
      %{fx | particles: Particles.blob(fx.particles, origin, ctx.time)}
      |> place("weapons/r_exp3.wav", origin)

  defp temp(fx, :lavasplash, %{origin: origin}, ctx),
    do: %{fx | particles: Particles.lava(fx.particles, origin, ctx.time)}

  defp temp(fx, :teleport, %{origin: origin}, ctx),
    do: %{fx | particles: Particles.teleport(fx.particles, origin, ctx.time)}

  defp temp(fx, kind, %{entity: entity, from: from, to: to}, ctx) do
    beam = %{
      model: Map.fetch!(@beams, kind),
      entity: entity,
      from: from,
      to: to,
      until: ctx.time + 0.2
    }

    %{
      fx
      | beams: [beam | Enum.reject(fx.beams, &(&1.entity == entity and &1.model == beam.model))]
    }
  end

  defp temp(fx, _kind, _data, _ctx), do: fx

  defp place(fx, name, origin),
    do: %{
      fx
      | sounds: [
          %{name: name, origin: origin, volume: 1.0, attenuation: 1.0, entity: 0, channel: -1}
          | fx.sounds
        ]
    }

  defp notify(fx, text, now) do
    case String.split(fx.pending <> text, "\n") do
      [partial] ->
        %{fx | pending: partial}

      parts ->
        {complete, [partial]} = Enum.split(parts, -1)
        lines = Enum.map(complete, &{&1, now + 3.0})
        %{fx | pending: partial, notify: Enum.take(fx.notify ++ lines, -4)}
    end
  end
end
