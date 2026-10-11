defmodule ElixirQuake.Menu.Draw do
  @moduledoc """
  Quake's menus drawn as Quake draws them, on a 320 by 200 canvas whose colour 255 is
  see-through: the plaque and title pictures, the spinning cursor, options with their
  sliders and switches, the controls with their keys, the help pages and the quit box.

      ElixirQuake.Menu.Draw.canvas(menu, seconds)
  """

  alias Cauldron3D.{Frame, Texture}
  alias ElixirQuake.{Assets, Menu, Text}
  alias ElixirQuake.Menu.Quit

  @labels %{
    customize: "    Customize controls",
    reset: "     Reset to defaults",
    screen_size: "           Screen size",
    gamma: "            Brightness",
    mouse_speed: "           Mouse Speed",
    volume: "          Sound Volume",
    always_run: "            Always Run",
    invert_mouse: "          Invert Mouse",
    use_mouse: "             Use Mouse"
  }

  @doc "The menu, with the settings it holds, on a see-through 320 by 200 canvas, at `time` seconds for its animations."
  @spec canvas(Menu.t(), number()) :: Frame.t()
  def canvas(%Menu{} = menu, time),
    do: draw(menu.page, menu, menu.settings, time, Frame.new(320, 200, 255))

  @doc "Every other pixel of `frame` set to colour 0, as Quake darkens the game behind a menu."
  @spec fade(Frame.t()) :: Frame.t()
  def fade(%Frame{width: width, pixels: pixels} = frame) do
    rows =
      for {row, y} <- Enum.with_index(for <<row::binary-size(^width) <- pixels>>, do: row),
          do: checker(row, rem(y, 2))

    %{frame | pixels: IO.iodata_to_binary(rows)}
  end

  defp checker(row, parity) do
    for {colour, x} <- Enum.with_index(:binary.bin_to_list(row)),
        into: <<>>,
        do: if(rem(x, 2) != parity, do: <<0>>, else: <<colour>>)
  end

  defp draw(:main, menu, _settings, time, canvas) do
    canvas
    |> titled("gfx/ttl_main.lmp")
    |> pic("gfx/mainmenu.lmp", {72, 32})
    |> pic("gfx/menudot#{rem(trunc(time * 10), 6) + 1}.lmp", {54, 32 + menu.cursor.main * 20})
  end

  defp draw(:single, menu, _settings, time, canvas) do
    canvas
    |> titled("gfx/ttl_sgl.lmp")
    |> pic("gfx/sp_menu.lmp", {72, 32})
    |> pic("gfx/menudot#{rem(trunc(time * 10), 6) + 1}.lmp", {54, 32 + menu.cursor.single * 20})
  end

  defp draw(:options, menu, settings, time, canvas) do
    canvas = titled(canvas, "gfx/p_option.lmp")

    Menu.option_items()
    |> Enum.with_index()
    |> Enum.reduce(canvas, fn {item, i}, acc ->
      y = 32 + i * 8
      acc |> print(Map.fetch!(@labels, item), {16, y}) |> value(item, settings, y)
    end)
    |> char(blink(time), {200, 32 + menu.cursor.options * 8})
  end

  defp draw(:keys, menu, settings, time, canvas) do
    canvas = titled(canvas, "gfx/ttl_cstm.lmp")

    canvas =
      if menu.grab?,
        do: print(canvas, "Press a key or button for this action", {12, 32}),
        else: print(canvas, "Enter to change, backspace to clear", {18, 32})

    Menu.commands()
    |> Enum.with_index()
    |> Enum.reduce(canvas, fn {{name, action}, i}, acc ->
      y = 48 + i * 8

      acc
      |> print(name, {16, y})
      |> print(keys_text(Map.get(settings.bindings, action, [])), {140, y})
    end)
    |> char(if(menu.grab?, do: ?=, else: blink(time)), {130, 48 + menu.cursor.keys * 8})
  end

  defp draw(:help, menu, _settings, _time, canvas),
    do: pic(canvas, "gfx/help#{menu.help}.lmp", {0, 0})

  defp draw(:quit, menu, settings, time, canvas) do
    canvas = draw(menu.back, menu, settings, time, canvas) |> box({56, 76}, 24, 4)

    menu.quit
    |> Quit.message()
    |> Enum.with_index()
    |> Enum.reduce(canvas, fn {line, i}, acc -> print(acc, line, {64, 84 + i * 8}) end)
  end

  defp draw(:notice, menu, settings, time, canvas) do
    canvas = draw(menu.back, menu, settings, time, canvas) |> box({56, 76}, 24, 3)
    lines = menu.notice ++ ["", "  press any key"]

    lines
    |> Enum.take(3)
    |> Enum.with_index()
    |> Enum.reduce(canvas, fn {line, i}, acc -> print(acc, line, {64, 84 + i * 8}) end)
  end

  defp value(canvas, :screen_size, s, y), do: slider(canvas, (s.options.screen_size - 30) / 90, y)
  defp value(canvas, :gamma, s, y), do: slider(canvas, (1.0 - s.options.gamma) / 0.5, y)
  defp value(canvas, :mouse_speed, s, y), do: slider(canvas, (s.options.mouse_speed - 1) / 10, y)
  defp value(canvas, :volume, s, y), do: slider(canvas, s.sfx, y)
  defp value(canvas, :always_run, s, y), do: check(canvas, s.options.always_run, y)
  defp value(canvas, :invert_mouse, s, y), do: check(canvas, s.options.invert_mouse, y)
  defp value(canvas, :use_mouse, s, y), do: check(canvas, Menu.mouse?(s), y)
  defp value(canvas, _item, _settings, _y), do: canvas

  defp slider(canvas, range, y) do
    range = range |> max(0.0) |> min(1.0)
    canvas = char(canvas, 128, {212, y})
    canvas = Enum.reduce(0..9, canvas, &char(&2, 129, {220 + &1 * 8, y}))
    canvas |> char(130, {300, y}) |> char(131, {220 + trunc(72 * range), y})
  end

  defp check(canvas, true, y), do: print(canvas, "on", {220, y})
  defp check(canvas, false, y), do: print(canvas, "off", {220, y})

  defp blink(time), do: 12 + rem(trunc(time * 4), 2)

  defp keys_text([]), do: "???"
  defp keys_text([one]), do: key_name(one)
  defp keys_text([one, two | _]), do: key_name(one) <> " or " <> key_name(two)

  @names %{
    up: "UPARROW",
    down: "DOWNARROW",
    left: "LEFTARROW",
    right: "RIGHTARROW",
    " ": "SPACE",
    enter: "ENTER",
    tab: "TAB",
    escape: "ESCAPE",
    backspace: "BACKSPACE",
    page_up: "PGUP",
    page_down: "PGDN",
    home: "HOME",
    end: "END",
    insert: "INS",
    delete: "DEL"
  }

  @mouse %{
    left: "MOUSE1",
    right: "MOUSE2",
    middle: "MOUSE3",
    wheel_up: "MWHEELUP",
    wheel_down: "MWHEELDOWN",
    move_left: "MOUSELEFT",
    move_right: "MOUSERIGHT",
    move_up: "MOUSEUP",
    move_down: "MOUSEDOWN"
  }

  defp key_name({:mouse, button}), do: Map.get(@mouse, button, "MOUSE")

  defp key_name({key, mods}),
    do: Enum.map_join(mods, "+", &String.upcase(Atom.to_string(&1))) <> "+" <> key_name(key)

  defp key_name(key) when is_atom(key),
    do: Map.get(@names, key) || String.upcase(Atom.to_string(key))

  defp titled(canvas, title) do
    canvas = pic(canvas, "gfx/qplaque.lmp", {16, 4})

    case Assets.picture(title) do
      nil ->
        canvas

      %Texture{width: width} = picture ->
        Frame.blit(canvas, picture, {div(320 - width, 2), 4}, 255)
    end
  end

  defp pic(canvas, name, at) do
    case Assets.picture(name) do
      nil -> canvas
      picture -> Frame.blit(canvas, picture, at, 255)
    end
  end

  defp print(canvas, text, at), do: Text.draw(canvas, text, at, alternate: true)

  defp char(canvas, code, at),
    do: Frame.blit(canvas, Text.glyph(Assets.pictures()["conchars"], code), at, 0)

  defp box(canvas, {x, y}, width, lines) do
    columns = div(width + 1, 2)
    canvas = edge(canvas, {"gfx/box_tl.lmp", "gfx/box_ml.lmp", "gfx/box_bl.lmp"}, x, y, lines)

    canvas =
      Enum.reduce(0..(columns - 1), canvas, fn c, acc ->
        cx = x + 8 + c * 16
        acc = pic(acc, "gfx/box_tm.lmp", {cx, y})

        acc =
          Enum.reduce(
            0..(lines - 1),
            acc,
            &pic(
              &2,
              if(&1 >= 1, do: "gfx/box_mm2.lmp", else: "gfx/box_mm.lmp"),
              {cx, y + 8 + &1 * 8}
            )
          )

        pic(acc, "gfx/box_bm.lmp", {cx, y + 8 + lines * 8})
      end)

    edge(
      canvas,
      {"gfx/box_tr.lmp", "gfx/box_mr.lmp", "gfx/box_br.lmp"},
      x + 8 + columns * 16,
      y,
      lines
    )
  end

  defp edge(canvas, {top, middle, bottom}, x, y, lines) do
    canvas = pic(canvas, top, {x, y})
    canvas = Enum.reduce(0..(lines - 1), canvas, &pic(&2, middle, {x, y + 8 + &1 * 8}))
    pic(canvas, bottom, {x, y + 8 + lines * 8})
  end
end
