defmodule ElixirQuake.Particles do
  @moduledoc """
  Quake's particles: blood and puffs, explosions, lava and teleport splashes, and the
  trails behind rockets, grenades, gibs and magic missiles, each moving by its kind and
  dying at its time.

      particles = ElixirQuake.Particles.effect([], origin, direction, colour, count, now)
      particles = ElixirQuake.Particles.run(particles, seconds, now)
  """

  @ramp1 {0x6F, 0x6D, 0x6B, 0x69, 0x67, 0x65, 0x63, 0x61}
  @ramp2 {0x6F, 0x6E, 0x6D, 0x6C, 0x6B, 0x6A, 0x68, 0x66}
  @ramp3 {0x6D, 0x6B, 6, 5, 4, 3}
  @most 2048

  @type particle :: %{
          origin: tuple(),
          velocity: tuple(),
          colour: byte(),
          die: float(),
          kind: atom(),
          ramp: float()
        }

  @doc "`count` particles of palette colour `colour` thrown from `origin` along `direction`; 1024 is an explosion."
  @spec effect([particle()], tuple(), tuple(), integer(), integer(), float()) :: [particle()]
  def effect(particles, origin, _direction, _colour, 1024, now),
    do: explosion(particles, origin, now)

  def effect(particles, origin, {dx, dy, dz}, colour, count, now) do
    new =
      for _ <- 1..max(count, 1)//1 do
        %{
          origin: jitter(origin, 16, 8),
          velocity: {dx * 15, dy * 15, dz * 15},
          colour: Bitwise.band(colour, 0xF8) + :rand.uniform(8) - 1,
          die: now + 0.1 * (:rand.uniform(5) - 1),
          kind: :slowgrav,
          ramp: 0.0
        }
      end

    keep(new ++ particles)
  end

  @doc "A rocket's explosion: 1024 particles flying out and cooling."
  @spec explosion([particle()], tuple(), float()) :: [particle()]
  def explosion(particles, origin, now) do
    new =
      for i <- 1..1024 do
        %{
          origin: jitter(origin, 32, 16),
          velocity: {spread(512), spread(512), spread(512)},
          colour: elem(@ramp1, 0),
          die: now + 5,
          kind: if(rem(i, 2) == 1, do: :explode, else: :explode2),
          ramp: (:rand.uniform(4) - 1) / 1
        }
      end

    keep(new ++ particles)
  end

  @doc "A tarbaby's burst: 1024 particles in two colours."
  @spec blob([particle()], tuple(), float()) :: [particle()]
  def blob(particles, origin, now) do
    new =
      for i <- 1..1024 do
        odd? = rem(i, 2) == 1

        %{
          origin: jitter(origin, 32, 16),
          velocity: {spread(512), spread(512), spread(512)},
          colour: if(odd?, do: 66, else: 150) + :rand.uniform(6) - 1,
          die: now + 1 + (:rand.uniform(2) - 1) * 0.4,
          kind: if(odd?, do: :blob, else: :blob2),
          ramp: 0.0
        }
      end

    keep(new ++ particles)
  end

  @doc "Lava thrown up in a square around `origin`."
  @spec lava([particle()], tuple(), float()) :: [particle()]
  def lava(particles, {x, y, z}, now) do
    new =
      for i <- -16..15, j <- -16..15 do
        dir = {j * 8 + :rand.uniform(8) - 1.0, i * 8 + :rand.uniform(8) - 1.0, 256.0}
        {dx, dy, _} = dir
        speed = 50 + :rand.uniform(64) - 1

        %{
          origin: {x + dx, y + dy, z + :rand.uniform(64) - 1},
          velocity: Cauldron3D.Vec.scale(Cauldron3D.Vec.normalize(dir), speed),
          colour: 224 + :rand.uniform(8) - 1,
          die: now + 2 + (:rand.uniform(32) - 1) * 0.02,
          kind: :slowgrav,
          ramp: 0.0
        }
      end

    keep(new ++ particles)
  end

  @doc "The sparkle of a teleport arriving at `origin`."
  @spec teleport([particle()], tuple(), float()) :: [particle()]
  def teleport(particles, {x, y, z}, now) do
    new =
      for i <- -16..16//4, j <- -16..16//4, k <- -24..32//4 do
        speed = 50 + :rand.uniform(64) - 1

        %{
          origin:
            {x + i + :rand.uniform(4) - 1.0, y + j + :rand.uniform(4) - 1.0,
             z + k + :rand.uniform(4) - 1.0},
          velocity:
            Cauldron3D.Vec.scale(Cauldron3D.Vec.normalize({j * 8.0, i * 8.0, k * 8.0}), speed),
          colour: 7 + :rand.uniform(8) - 1,
          die: now + 0.2 + (:rand.uniform(8) - 1) * 0.02,
          kind: :slowgrav,
          ramp: 0.0
        }
      end

    keep(new ++ particles)
  end

  @doc """
  A trail from `from` to `to`: `:rocket`, `:smoke`, `:blood`, `:tracer`, `:slight_blood`,
  `:tracer2` or `:voor`.
  """
  @spec trail([particle()], tuple(), tuple(), atom(), float()) :: [particle()]
  def trail(particles, from, to, kind, now) do
    offset = Cauldron3D.Vec.sub(to, from)
    length = Cauldron3D.Vec.length(offset)
    direction = Cauldron3D.Vec.normalize(offset)
    step = if kind == :slight_blood, do: 6.0, else: 3.0

    new =
      for {distance, n} <-
            Enum.with_index(Stream.take_while(Stream.iterate(0.0, &(&1 + step)), &(&1 < length))) do
        trail_particle(kind, Cauldron3D.Vec.madd(from, direction, distance), direction, n, now)
      end

    keep(new ++ particles)
  end

  @doc "Move every particle on by `seconds` and drop those whose time is up at `now`."
  @spec run([particle()], float(), float()) :: [particle()]
  def run(particles, seconds, now) do
    grav = seconds * 800 * 0.05

    for p <- particles, p.die > now, moved = move(p, seconds, grav), moved != nil, do: moved
  end

  defp trail_particle(kind, at, {dx, dy, _}, n, now) do
    base = %{origin: at, velocity: {0.0, 0.0, 0.0}, die: now + 2, ramp: 0.0}

    case kind do
      :rocket ->
        ramp = :rand.uniform(4) - 1

        Map.merge(base, %{
          origin: jitter(at, 6, 3),
          colour: elem(@ramp3, ramp),
          kind: :fire,
          ramp: ramp / 1
        })

      :smoke ->
        ramp = :rand.uniform(4) + 1

        Map.merge(base, %{
          origin: jitter(at, 6, 3),
          colour: elem(@ramp3, ramp),
          kind: :fire,
          ramp: ramp / 1
        })

      blood when blood in [:blood, :slight_blood] ->
        Map.merge(base, %{
          origin: jitter(at, 6, 3),
          colour: 67 + :rand.uniform(4) - 1,
          kind: :grav
        })

      tracer when tracer in [:tracer, :tracer2] ->
        colour = if(tracer == :tracer, do: 52, else: 230) + Bitwise.bsl(Bitwise.band(n, 4), 1)
        velocity = if rem(n, 2) == 1, do: {30 * dy, -30 * dx, 0.0}, else: {-30 * dy, 30 * dx, 0.0}
        Map.merge(base, %{colour: colour, kind: :static, die: now + 0.5, velocity: velocity})

      :voor ->
        Map.merge(base, %{
          origin: jitter(at, 16, 8),
          colour: 9 * 16 + 8 + :rand.uniform(4) - 1,
          kind: :static,
          die: now + 0.3
        })
    end
  end

  defp move(p, seconds, grav) do
    p
    |> Map.put(:origin, Cauldron3D.Vec.madd(p.origin, p.velocity, seconds))
    |> step(seconds, grav)
  end

  defp step(%{kind: :static} = p, _seconds, _grav), do: p

  defp step(%{kind: :fire} = p, seconds, grav) do
    ramp = p.ramp + seconds * 5
    {vx, vy, vz} = p.velocity

    if ramp >= 6,
      do: nil,
      else: %{p | ramp: ramp, colour: elem(@ramp3, trunc(ramp)), velocity: {vx, vy, vz + grav}}
  end

  defp step(%{kind: :explode} = p, seconds, grav) do
    ramp = p.ramp + seconds * 10
    {vx, vy, vz} = Cauldron3D.Vec.scale(p.velocity, 1 + 4 * seconds)

    if ramp >= 8,
      do: nil,
      else: %{p | ramp: ramp, colour: elem(@ramp1, trunc(ramp)), velocity: {vx, vy, vz - grav}}
  end

  defp step(%{kind: :explode2} = p, seconds, grav) do
    ramp = p.ramp + seconds * 15
    {vx, vy, vz} = Cauldron3D.Vec.scale(p.velocity, 1 - seconds)

    if ramp >= 8,
      do: nil,
      else: %{p | ramp: ramp, colour: elem(@ramp2, trunc(ramp)), velocity: {vx, vy, vz - grav}}
  end

  defp step(%{kind: :blob} = p, seconds, grav) do
    {vx, vy, vz} = Cauldron3D.Vec.scale(p.velocity, 1 + 4 * seconds)
    %{p | velocity: {vx, vy, vz - grav}}
  end

  defp step(%{kind: :blob2} = p, seconds, grav) do
    {vx, vy, vz} = p.velocity
    slow = 1 - 4 * seconds
    %{p | velocity: {vx * slow, vy * slow, vz - grav}}
  end

  defp step(p, _seconds, grav) do
    {vx, vy, vz} = p.velocity
    %{p | velocity: {vx, vy, vz - grav}}
  end

  defp jitter({x, y, z}, range, half),
    do:
      {x + :rand.uniform(range) - 1 - half, y + :rand.uniform(range) - 1 - half,
       z + :rand.uniform(range) - 1 - half}

  defp spread(range), do: :rand.uniform(range) - 1 - div(range, 2) / 1

  defp keep(particles), do: Enum.take(particles, @most)
end
