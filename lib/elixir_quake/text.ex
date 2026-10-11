defmodule ElixirQuake.Text do
  @moduledoc """
  Text in Quake's console font (`conchars`, sixteen rows of sixteen 8 by 8 characters),
  drawn onto a `Cauldron3D.Frame`. Colour 0 of the font is see-through.

      frame = ElixirQuake.Text.draw(frame, "You got the shells", {8, 8})
  """

  alias Cauldron3D.{Frame, Texture}
  alias ElixirQuake.Assets

  @doc "`text` with its top left at `{x, y}`; `:alternate` draws it in the font's other colour."
  @spec draw(Frame.t(), String.t(), {integer(), integer()}, keyword()) :: Frame.t()
  def draw(%Frame{} = frame, text, {x, y}, opts \\ []) do
    font = Assets.pictures()["conchars"]
    shift = if Keyword.get(opts, :alternate, false), do: 128, else: 0

    text
    |> :binary.bin_to_list()
    |> Enum.with_index()
    |> Enum.reduce(frame, fn {code, i}, acc ->
      if code == ?\s,
        do: acc,
        else: Frame.blit(acc, glyph(font, rem(code + shift, 256)), {x + i * 8, y}, 0)
    end)
  end

  @doc "Character `code` of the font, as an 8 by 8 texture."
  @spec glyph(Texture.t() | nil, 0..255) :: Texture.t()
  def glyph(nil, _code), do: Texture.new(8, 8, :binary.copy(<<0>>, 64))

  def glyph(%Texture{} = font, code) do
    key = {__MODULE__, :glyph, code}

    case :persistent_term.get(key, nil) do
      nil ->
        {column, row} = {rem(code, 16) * 8, div(code, 16) * 8}

        pixels =
          for line <- 0..7,
              into: <<>>,
              do: binary_part(font.pixels, (row + line) * 128 + column, 8)

        glyph = Texture.new(8, 8, pixels)
        :persistent_term.put(key, glyph)
        glyph

      glyph ->
        glyph
    end
  end

  @doc "Lines of text as one frame `width` wide, each centred, on colour `clear`, for drawing over a picture."
  @spec centred([String.t()], pos_integer(), byte()) :: Frame.t()
  def centred(lines, width, clear \\ 0) do
    height = max(length(lines), 1) * 8
    blank = %Frame{width: width, height: height, pixels: :binary.copy(<<clear>>, width * height)}

    lines
    |> Enum.with_index()
    |> Enum.reduce(blank, fn {line, i}, acc ->
      draw(acc, line, {div(width - byte_size(line) * 8, 2), i * 8})
    end)
  end
end
