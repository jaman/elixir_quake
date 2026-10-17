defmodule ElixirQuake.Screen do
  @moduledoc """
  The flat parts of the player's picture, in palette colours: where the world view sits,
  the backdrop around it, the status bar, messages, the intermission tally, the closing
  text and an open menu, and the palette they are shown in.

      layout = ElixirQuake.Screen.layout(view, {320, 200}, aspect, options)

      layout
      |> ElixirQuake.Screen.backdrop()
      |> Cauldron3D.Frame.blit(world, layout.at)
      |> ElixirQuake.Screen.layers(view, layout, menu)

  `aspect` is how wide a pixel is on screen against its height. `options` are the
  player's options (`ElixirQuake.Menu.defaults/0`): `:screen_size` sets the view as
  Quake's does, below 100 a smaller view framed by the background tile, 100 both status
  bars, 110 the main bar only, 120 none; the intermission and the finale always use the
  whole picture. `:gamma` (0.5 to 1.0, lower brighter) curves the palette.
  """

  alias Cauldron3D.{Frame, Texture}
  alias ElixirQuake.{Assets, StatusBar, Text}
  alias ElixirQuake.Menu.Draw

  @type t :: %__MODULE__{
          width: pos_integer(),
          height: pos_integer(),
          aspect: number(),
          size: pos_integer(),
          lines: non_neg_integer(),
          bar: non_neg_integer(),
          view: {pos_integer(), pos_integer()},
          at: {non_neg_integer(), non_neg_integer()}
        }

  @enforce_keys [:width, :height, :aspect, :size, :lines, :bar, :view, :at]
  defstruct [:width, :height, :aspect, :size, :lines, :bar, :view, :at]

  @doc """
  The picture's plan at `{width, height}` pixels: `size` the screen size in force,
  `lines` the status bar lines shown (of 48), `bar` the rows they take, `view` the world
  view's size and `at` its top left.
  """
  @spec layout(map(), {pos_integer(), pos_integer()}, number(), map()) :: t()
  def layout(view, {width, height}, aspect, options) do
    width = max(width, 32)
    height = max(height, 20)
    full_screen? = view.intermission != nil or view.finale != nil
    size = if full_screen?, do: 120, else: Map.get(options, :screen_size, 100)
    lines = bar_lines(size)
    bar = min(round(lines * width / 320 * aspect), div(height, 3))
    {view_width, view_height} = viewport(size, {width, height - bar})

    %__MODULE__{
      width: width,
      height: height,
      aspect: aspect,
      size: size,
      lines: lines,
      bar: bar,
      view: {view_width, view_height},
      at: {div(width - view_width, 2), div(height - bar - view_height, 2)}
    }
  end

  @doc "The whole picture before the world is put in: colour 0, or the background tile around a smaller view."
  @spec backdrop(t()) :: Frame.t()
  def backdrop(%__MODULE__{width: width, height: height, size: size}) when size >= 100,
    do: Frame.new(width, height, 0)

  def backdrop(%__MODULE__{width: width, height: height}) do
    case Assets.pictures()["backtile"] do
      nil -> Frame.new(width, height, 0)
      tile -> tiled(tile, width, height)
    end
  end

  @doc "The status bar, messages, intermission tally or closing text, and `menu` (an `ElixirQuake.Menu` or `nil`) drawn over `frame`."
  @spec layers(Frame.t(), map(), t(), term()) :: Frame.t()
  def layers(frame, view, %__MODULE__{} = layout, menu) do
    frame
    |> status(view, layout.bar, layout.lines)
    |> messages(view, layout.aspect)
    |> overlay(view, layout.aspect)
    |> menu(menu)
  end

  @doc "The palette `view` is shown in: washed by its colour washes, then curved by `gamma`."
  @spec palette(map(), number()) :: binary()
  def palette(view, gamma) do
    base = Assets.get().palette
    {r, g, b, a} = blend(view.washes)

    for <<cr, cg, cb <- base>>, into: <<>> do
      <<lift(cr + (r - cr) * a, gamma), lift(cg + (g - cg) * a, gamma),
        lift(cb + (b - cb) * a, gamma)>>
    end
  end

  @doc "Colour washes (`ElixirQuake.Effects.washes/3`) as one: `{r, g, b, share}`, colours 0 to 255 and `share` 0 to 1."
  @spec blend([{{number(), number(), number()}, number()}]) ::
          {float(), float(), float(), float()}
  def blend(washes) do
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

  defp bar_lines(size) when size >= 120, do: 0
  defp bar_lines(size) when size >= 110, do: 24
  defp bar_lines(_size), do: 48

  defp viewport(size, {width, height}) when size >= 100, do: {width, height}

  defp viewport(size, {width, height}),
    do: {max(div(width * size, 100), 8), max(div(height * size, 100), 8)}

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
    canvas = Draw.canvas(menu, System.monotonic_time(:millisecond) / 1000)

    frame
    |> Draw.fade()
    |> Frame.blit(Frame.scale(canvas, frame.width, frame.height), {0, 0}, 255)
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

  defp lift(value, gamma) when gamma == 1.0, do: value |> round() |> max(0) |> min(255)

  defp lift(value, gamma),
    do:
      (255 * :math.pow((max(value, 0) + 0.5) / 255.5, gamma) + 0.5)
      |> trunc()
      |> max(0)
      |> min(255)
end
