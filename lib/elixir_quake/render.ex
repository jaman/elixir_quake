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

  alias Cauldron3D.{Billboard, Camera, Frame, Mesh, Polygon, Texture, Vec}
  alias Cauldron3D.Bsp.{Draw, Surfaces}
  alias Cauldron3D.Formats.{Mdl, Spr}
  alias ElixirQuake.{Assets, LightPoint, StatusBar, Text}
  alias FrenchCurve.Raster

  @liquid [amplitude: 8.0, wavelength: 50.27, speed: 0.159]

  @doc "The picture of `view` at `{width, height}` pixels."
  @spec picture(map(), {pos_integer(), pos_integer()}, number(), keyword()) :: Raster.t()
  def picture(view, {width, height}, aspect, opts \\ []) do
    width = max(width, 32)
    height = max(height, 20)
    options = Keyword.get(opts, :options, %{})
    %{bsp: bsp} = Assets.map(view.map)
    palette = palette(view, Map.get(options, :gamma, 1.0))
    full_screen? = view.intermission != nil or view.finale != nil
    size = if full_screen?, do: 120, else: Map.get(options, :screen_size, 100)
    lines = bar_lines(size)
    bar = min(round(lines * width / 320 * aspect), div(height, 3))
    {view_width, view_height} = viewport(size, {width, height - bar})
    world = world(view, bsp, {view_width, view_height}, aspect)
    at = {div(width - view_width, 2), div(height - bar - view_height, 2)}

    frame =
      width
      |> backdrop(height, size)
      |> Frame.blit(world, at)
      |> status(view, bar, lines)
      |> messages(view, aspect)
      |> overlay(view, aspect)
      |> menu(Keyword.get(opts, :menu))

    Raster.from_rgba(width, height, Frame.rgba(frame, palette))
  end

  defp bar_lines(size) when size >= 120, do: 0
  defp bar_lines(size) when size >= 110, do: 24
  defp bar_lines(_size), do: 48

  defp viewport(size, {width, height}) when size >= 100, do: {width, height}

  defp viewport(size, {width, height}),
    do: {max(div(width * size, 100), 8), max(div(height * size, 100), 8)}

  defp backdrop(width, height, size) when size >= 100, do: Frame.new(width, height, 0)

  defp backdrop(width, height, _size) do
    case Assets.pictures()["backtile"] do
      nil -> Frame.new(width, height, 0)
      tile -> tiled(tile, width, height)
    end
  end

  defp tiled(tile, width, height) do
    rows =
      for y <- 0..(height - 1) do
        row = binary_part(tile.pixels, rem(y, tile.height) * tile.width, tile.width)
        binary_part(:binary.copy(row, div(width, tile.width) + 1), 0, width)
      end

    %Frame{width: width, height: height, pixels: IO.iodata_to_binary(rows)}
  end

  defp menu(frame, nil), do: frame

  defp menu(frame, menu) do
    canvas = ElixirQuake.Menu.Draw.canvas(menu, System.monotonic_time(:millisecond) / 1000)

    frame
    |> ElixirQuake.Menu.Draw.fade()
    |> Frame.blit(Frame.scale(canvas, frame.width, frame.height), {0, 0}, 255)
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
      light: shading(lit),
      cull: :counter_clockwise
    )
  end

  defp shading(lit) do
    ambient = min(lit, 128)
    shade = max(min(lit, 192 - ambient), 0)
    {ambient * 0.85 + 16, shade * 0.6, {0.4, 0.3, 0.86}}
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
          light: shading(lit),
          cull: :counter_clockwise,
          depth: :always
        )

      _ ->
        []
    end
  end

  defp status(frame, _view, 0, _lines), do: frame
  defp status(frame, _view, _rows, 0), do: frame

  defp status(frame, view, rows, lines) do
    whole = StatusBar.draw(view.stats, view.time)

    shown = %Frame{
      width: 320,
      height: lines,
      pixels: binary_part(whole.pixels, (48 - lines) * 320, lines * 320)
    }

    Frame.blit(frame, Frame.scale(shown, frame.width, rows), {0, frame.height - rows}, 255)
  end

  defp messages(frame, view, aspect) do
    scale = frame.width / 320

    frame =
      if view.notify == [] do
        frame
      else
        lines = Text.centred(view.notify, 320, 255)

        Frame.blit(
          frame,
          Frame.scale(lines, frame.width, max(round(lines.height * scale * aspect), 1)),
          {0, 0},
          255
        )
      end

    case view.center do
      nil ->
        frame

      lines ->
        text = Text.centred(lines, 320, 255)
        scaled = Frame.scale(text, frame.width, max(round(text.height * scale * aspect), 1))
        Frame.blit(frame, scaled, {0, div(frame.height, 3)}, 255)
    end
  end

  defp overlay(frame, %{finale: {text, since}} = view, aspect) do
    shown = String.slice(text, 0, max(trunc((view.time - since) * 8), 0))
    lines = String.split(shown, "\n")
    canvas = Text.centred(lines, 320, 255)

    scaled =
      Frame.scale(canvas, frame.width, max(round(canvas.height * frame.width / 320 * aspect), 1))

    Frame.blit(frame, scaled, {0, div(frame.height, 4)}, 255)
  end

  defp overlay(frame, %{intermission: at} = view, _aspect) when at != nil do
    canvas = tally(view.tally)
    Frame.blit(frame, Frame.scale(canvas, frame.width, frame.height), {0, 0}, 255)
  end

  defp overlay(frame, _view, _aspect), do: frame

  defp tally(tally) do
    pictures = Assets.pictures()
    canvas = Frame.new(320, 200, 255)
    canvas = put(canvas, Assets.picture("gfx/complete.lmp"), {64, 24})
    canvas = put(canvas, Assets.picture("gfx/inter.lmp"), {0, 56})
    minutes = div(tally.seconds, 60)
    seconds = rem(tally.seconds, 60)

    canvas
    |> digits(pictures, {160, 64}, minutes)
    |> put(pictures["num_colon"], {234, 64})
    |> put(pictures["num_#{div(seconds, 10)}"], {246, 64})
    |> put(pictures["num_#{rem(seconds, 10)}"], {266, 64})
    |> digits(pictures, {160, 104}, tally.secrets)
    |> put(pictures["num_slash"], {232, 104})
    |> digits(pictures, {240, 104}, tally.total_secrets)
    |> digits(pictures, {160, 144}, tally.monsters)
    |> put(pictures["num_slash"], {232, 144})
    |> digits(pictures, {240, 144}, tally.total_monsters)
  end

  defp digits(canvas, pictures, {x, y}, value) do
    text = value |> Integer.to_string() |> String.slice(-3, 3)
    x = x + (3 - byte_size(text)) * 24

    text
    |> String.to_charlist()
    |> Enum.with_index()
    |> Enum.reduce(canvas, fn {char, i}, acc ->
      put(acc, pictures["num_" <> <<char>>], {x + i * 24, y})
    end)
  end

  defp put(canvas, nil, _at), do: canvas
  defp put(canvas, %Texture{} = picture, at), do: Frame.blit(canvas, picture, at, 255)

  defp palette(view, gamma) do
    base = Assets.get().palette
    {r, g, b, a} = blend(view.washes)

    for <<cr, cg, cb <- base>>, into: <<>> do
      <<lift(cr + (r - cr) * a, gamma), lift(cg + (g - cg) * a, gamma),
        lift(cb + (b - cb) * a, gamma)>>
    end
  end

  defp lift(value, gamma) when gamma == 1.0, do: value |> round() |> max(0) |> min(255)

  defp lift(value, gamma),
    do:
      (255 * :math.pow((max(value, 0) + 0.5) / 255.5, gamma) + 0.5)
      |> trunc()
      |> max(0)
      |> min(255)

  defp blend(washes) do
    Enum.reduce(washes, {0.0, 0.0, 0.0, 0.0}, fn {{sr, sg, sb}, percent}, {r, g, b, a} ->
      share = percent / 255

      if share <= 0 do
        {r, g, b, a}
      else
        a = a + share * (1 - a)
        part = share / a
        {r * (1 - part) + sr * part, g * (1 - part) + sg * part, b * (1 - part) + sb * part, a}
      end
    end)
  end
end
