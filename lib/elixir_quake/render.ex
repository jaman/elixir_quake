defmodule ElixirQuake.Render do
  @moduledoc """
  The player's picture: the world and everything in it through `Cauldron3D`, the held
  weapon, particles and beams, the status bar, messages, the intermission tally and the
  closing text, in the palette washed by damage, bonuses, power-ups and liquid.

      ElixirQuake.Render.picture(view, {320, 200}, aspect)

  `aspect` is how wide a pixel is on screen against its height. The view keeps Quake's
  vertical field of view, that of 90 degrees across a 4:3 picture, whatever the shape of
  the view: a wider view sees further to the sides, a taller one less.

  ## Options

    * `:options` — the player's options (`ElixirQuake.Menu.defaults/0`): `:gamma` (0.5
      to 1.0, lower brighter) curves the palette, and `:screen_size` sets the view as
      Quake's does: below 100 a smaller view framed by the background tile, 100 both
      status bars, 110 the main bar only, 120 none
    * `:menu` — an open `ElixirQuake.Menu`, drawn over the darkened picture
  """

  alias Cauldron3D.{Billboard, Camera, Frame, Mesh, Polygon, Vec}
  alias Cauldron3D.Bsp.{Draw, Surfaces}
  alias Cauldron3D.Formats.{Mdl, Spr}
  alias ElixirQuake.{Assets, LightPoint, Screen}
  alias FrenchCurve.Raster

  @liquid [amplitude: 8.0, wavelength: 50.27, speed: 0.159]

  @doc "The picture of `view` at `{width, height}` pixels."
  @spec picture(map(), {pos_integer(), pos_integer()}, number(), keyword()) :: Raster.t()
  def picture(view, size, aspect, opts \\ []) do
    options = Keyword.get(opts, :options, %{})
    %{bsp: bsp} = Assets.map(view.map)
    layout = Screen.layout(view, size, aspect, options)
    world = world(view, bsp, layout.view, aspect)

    frame =
      layout
      |> Screen.backdrop()
      |> Frame.blit(world, layout.at)
      |> Screen.layers(view, layout, Keyword.get(opts, :menu))

    palette = Screen.palette(view, Map.get(options, :gamma, 1.0))
    Raster.from_rgba(layout.width, layout.height, Frame.rgba(frame, palette))
  end

  defp world(view, bsp, {width, height}, aspect) do
    camera = camera(view.camera, fov(width, height, aspect))
    sight = Cauldron3D.View.new(camera, {width, height}, pixel_aspect: 1 / aspect)
    light = %{table: Assets.get().colormap, rows: 64, styles: view.styles, unlit: 255}

    {brushes, others} = Enum.split_with(view.entities, &String.starts_with?(&1.model, "*"))

    models =
      for e <- brushes, do: {String.to_integer(String.trim_leading(e.model, "*")), e.origin}

    polygons =
      Draw.polygons(bsp, sight,
        surfaces: cache(view.map),
        light: light,
        models: models,
        time: view.time,
        liquid: [time: view.time] ++ @liquid
      ) ++
        Enum.flat_map(
          Enum.filter(others ++ view.statics, &ahead?(sight, &1.origin)),
          &thing(&1, view, bsp, sight)
        ) ++
        Enum.flat_map(view.beams, &beam(&1, view)) ++
        particles(view.particles, sight) ++
        weapon(view, bsp)

    Cauldron3D.Render.draw(sight, polygons, light_table: Assets.get().colormap, background: 0)
  end

  defp camera(%{origin: origin, angles: {pitch, yaw, roll}}, fov) do
    Camera.first_person(origin, radians(yaw), -radians(pitch),
      roll: radians(roll),
      fov: fov,
      near: 1.0
    )
  end

  defp fov(width, height, aspect) do
    shape = width * aspect / height
    2 * :math.atan(:math.tan(:math.pi() / 4) * shape / (4 / 3))
  end

  defp radians(degrees), do: degrees * :math.pi() / 180

  defp ahead?(sight, origin), do: Vec.dot(Vec.sub(origin, sight.origin), sight.forward) > -64

  defp cache(name) do
    key = {__MODULE__, :surfaces, name}

    case :persistent_term.get(key, nil) do
      tid when tid != nil ->
        if :ets.info(tid) != :undefined, do: tid, else: new_cache(key)

      nil ->
        new_cache(key)
    end
  end

  defp new_cache(key) do
    tid = Surfaces.new()
    :persistent_term.put(key, tid)
    tid
  end

  defp thing(%{model: name} = thing, view, bsp, sight) do
    case Assets.model(name) do
      %{kind: :alias, data: model} -> alias_model(model, thing, view, bsp)
      %{kind: :sprite, data: sprite} -> sprite(sprite, thing, view, sight)
      %{kind: :brush, data: %{bsp: item}} -> item_model(item, name, thing, sight)
      _ -> []
    end
  end

  defp alias_model(%Mdl{} = model, thing, view, bsp) do
    {pitch, yaw, roll} = thing.angles
    yaw = if Bitwise.band(model.flags, 8) != 0, do: :math.fmod(100 * view.time, 360.0), else: yaw
    lit = LightPoint.at(bsp, thing.origin, view.styles)

    Mesh.polygons(model.mesh,
      frame: Mdl.pose(model, thing.frame, view.time),
      origin: thing.origin,
      yaw: radians(yaw),
      pitch: radians(pitch),
      roll: radians(roll),
      skin: thing.skin,
      light: LightPoint.shading(lit),
      cull: :counter_clockwise
    )
  end

  defp sprite(%Spr{} = sprite, thing, view, sight) do
    picture = Spr.picture(sprite, thing.frame, view.time)
    upright = sprite.kind in [:parallel_upright, :facing_upright]

    [
      Billboard.polygon(sight, thing.origin, picture.texture,
        origin: picture.origin,
        upright: upright,
        clear: 255
      )
    ]
  end

  defp item_model(item, name, thing, sight) do
    light = %{table: Assets.get().colormap, rows: 64, unlit: 200}

    Draw.polygons(item, sight,
      surfaces: cache(name),
      light: light,
      models: [{0, thing.origin}],
      world?: false
    )
  end

  defp beam(%{model: name, from: from, to: to}, view) do
    case Assets.model(name) do
      %{kind: :alias, data: model} ->
        offset = Vec.sub(to, from)
        {_, yaw, _} = QuakeServer.Angles.of(offset)
        {pitch, _, _} = QuakeServer.Angles.of(offset)
        direction = Vec.normalize(offset)
        steps = trunc(Vec.length(offset) / 30)

        for step <- 0..steps//1,
            polygon <-
              Mesh.polygons(model.mesh,
                frame: Mdl.pose(model, 0, view.time),
                origin: Vec.madd(from, direction, step * 30.0),
                yaw: radians(yaw),
                pitch: radians(pitch),
                roll: radians(:rand.uniform(360)),
                light: 255,
                cull: :counter_clockwise
              ),
            do: polygon

      _ ->
        []
    end
  end

  defp particles(particles, sight) do
    {right, up} = {Vec.scale(sight.right, 1.0), Vec.scale(sight.up, 1.0)}

    for %{origin: origin, colour: colour} <- particles,
        Cauldron3D.View.in_front?(sight, origin) do
      %Polygon{
        points: [
          origin,
          Vec.add(origin, right),
          origin |> Vec.add(right) |> Vec.add(up),
          Vec.add(origin, up)
        ],
        paint: {:flat, colour}
      }
    end
  end

  defp weapon(%{weapon: nil}, _bsp), do: []

  defp weapon(%{weapon: %{model: name, frame: frame}, camera: camera} = view, bsp) do
    case Assets.model(name) do
      %{kind: :alias, data: model} ->
        {pitch, yaw, roll} = camera.angles
        {forward, _right, _up} = QuakeServer.Angles.vectors({pitch, yaw, 0.0})
        bob = Map.get(camera, :bob, 0.0)
        {x, y, z} = Vec.madd(camera.origin, forward, bob * 0.4)
        lit = max(LightPoint.at(bsp, camera.origin, view.styles), 24)

        Mesh.polygons(model.mesh,
          frame: Mdl.pose(model, frame, view.time),
          origin: {x, y, z + bob - 1.0},
          yaw: radians(yaw),
          pitch: -radians(pitch),
          roll: radians(roll),
          light: LightPoint.shading(lit),
          cull: :counter_clockwise,
          depth: :always
        )

      _ ->
        []
    end
  end
end
