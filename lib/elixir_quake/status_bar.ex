defmodule ElixirQuake.StatusBar do
  @moduledoc """
  Quake's status bar, 320 by 48: the inventory bar (weapons held, ammunition counts,
  keys, power-ups and runes) over the main bar (armour, face, health, ammunition).
  Colour 255 is see-through.

      ElixirQuake.StatusBar.draw(stats, time)

  `stats` is `%{health:, armor:, ammo:, items:, weapon:, shells:, nails:, rockets:,
  cells:, pain_until:}`; `items` carries the runes in its top four bits.
  """

  import Bitwise

  alias Cauldron3D.Frame
  alias ElixirQuake.{Assets, Text}

  @weapons ~w(shotgun sshotgun nailgun snailgun rlaunch srlaunch lightng)

  @doc "The status bar for `stats` at `time` seconds."
  @spec draw(map(), number()) :: Frame.t()
  def draw(stats, time) do
    pictures = Assets.pictures()

    Frame.new(320, 48, 255)
    |> inventory(stats, pictures)
    |> main(stats, pictures, time)
  end

  defp inventory(frame, stats, pictures) do
    frame
    |> pic(pictures["ibar"], {0, 0})
    |> weapons(stats, pictures)
    |> ammo_counts(stats)
    |> items(stats, pictures)
  end

  defp weapons(frame, stats, pictures) do
    @weapons
    |> Enum.with_index()
    |> Enum.reduce(frame, fn {name, i}, acc ->
      bit = 1 <<< i

      cond do
        (stats.items &&& bit) == 0 -> acc
        stats.weapon == bit -> pic(acc, pictures["inv2_" <> name], {i * 24, 8})
        true -> pic(acc, pictures["inv_" <> name], {i * 24, 8})
      end
    end)
  end

  defp ammo_counts(frame, stats) do
    [stats.shells, stats.nails, stats.rockets, stats.cells]
    |> Enum.with_index()
    |> Enum.reduce(frame, fn {count, i}, acc ->
      count
      |> trunc()
      |> Integer.to_string()
      |> String.pad_leading(3)
      |> String.slice(-3, 3)
      |> String.to_charlist()
      |> Enum.with_index(1)
      |> Enum.reduce(acc, fn
        {?\s, _}, inner ->
          inner

        {digit, j}, inner ->
          Frame.blit(
            inner,
            Text.glyph(Assets.pictures()["conchars"], 18 + digit - ?0),
            {(6 * i + j) * 8 - 2 + 4, 0},
            0
          )
      end)
    end)
  end

  defp items(frame, stats, pictures) do
    held = ~w(sb_key1 sb_key2 sb_invis sb_invuln sb_suit sb_quad)

    frame =
      held
      |> Enum.with_index()
      |> Enum.reduce(frame, fn {name, i}, acc ->
        if (stats.items &&& 1 <<< (17 + i)) != 0,
          do: pic(acc, pictures[name], {192 + i * 16, 8}),
          else: acc
      end)

    Enum.reduce(0..3, frame, fn i, acc ->
      if (stats.items &&& 1 <<< (28 + i)) != 0,
        do: pic(acc, pictures["sb_sigil#{i + 1}"], {320 - 32 + i * 8, 8}),
        else: acc
    end)
  end

  defp main(frame, stats, pictures, time) do
    frame
    |> pic(pictures["sbar"], {0, 24})
    |> armor(stats, pictures)
    |> face(stats, pictures, time)
    |> number(pictures, {136, 24}, stats.health, stats.health <= 25)
    |> ammo(stats, pictures)
    |> number(pictures, {248, 24}, stats.ammo, stats.ammo <= 10)
  end

  defp armor(frame, stats, pictures) do
    if (stats.items &&& 1_048_576) != 0 do
      frame |> number(pictures, {24, 24}, 666, true) |> pic(pictures["disc"], {0, 24})
    else
      frame = number(frame, pictures, {24, 24}, stats.armor, stats.armor <= 25)

      cond do
        (stats.items &&& 32_768) != 0 -> pic(frame, pictures["sb_armor3"], {0, 24})
        (stats.items &&& 16_384) != 0 -> pic(frame, pictures["sb_armor2"], {0, 24})
        (stats.items &&& 8_192) != 0 -> pic(frame, pictures["sb_armor1"], {0, 24})
        true -> frame
      end
    end
  end

  defp face(frame, stats, pictures, time) do
    name =
      cond do
        (stats.items &&& (524_288 ||| 1_048_576)) == (524_288 ||| 1_048_576) -> "face_inv2"
        (stats.items &&& 4_194_304) != 0 -> "face_quad"
        (stats.items &&& 524_288) != 0 -> "face_invis"
        (stats.items &&& 1_048_576) != 0 -> "face_invul2"
        true -> health_face(stats, time)
      end

    pic(frame, pictures[name], {112, 24})
  end

  defp health_face(stats, time) do
    level = if stats.health >= 100, do: 4, else: max(div(trunc(stats.health), 20), 0)
    face = 5 - level
    if time <= Map.get(stats, :pain_until, 0), do: "face_p#{face}", else: "face#{face}"
  end

  defp ammo(frame, stats, pictures) do
    cond do
      (stats.items &&& 256) != 0 -> pic(frame, pictures["sb_shells"], {224, 24})
      (stats.items &&& 512) != 0 -> pic(frame, pictures["sb_nails"], {224, 24})
      (stats.items &&& 1024) != 0 -> pic(frame, pictures["sb_rocket"], {224, 24})
      (stats.items &&& 2048) != 0 -> pic(frame, pictures["sb_cells"], {224, 24})
      true -> frame
    end
  end

  defp number(frame, pictures, {x, y}, value, alert?) do
    text = value |> trunc() |> Integer.to_string() |> String.slice(-3, 3)
    x = x + (3 - byte_size(text)) * 24
    prefix = if alert?, do: "anum_", else: "num_"

    text
    |> String.to_charlist()
    |> Enum.with_index()
    |> Enum.reduce(frame, fn {char, i}, acc ->
      name = if char == ?-, do: prefix <> "minus", else: prefix <> <<char>>
      pic(acc, pictures[name], {x + i * 24, y})
    end)
  end

  defp pic(frame, nil, _at), do: frame
  defp pic(frame, picture, at), do: Frame.blit(frame, picture, at, 255)
end
