defmodule ElixirQuake.Gpu.Overlay do
  @moduledoc """
  The flat parts of the player's picture (`ElixirQuake.Screen`) as an RGBA picture to lay
  over the graphics card's world: see-through where the world view shows, the backdrop,
  status bar, messages, tally, closing text and menu as `ElixirQuake.Render` draws them,
  in the same washed and curved palette.

      texture = ElixirQuake.Gpu.Overlay.texture(view, layout, menu, gamma)
  """

  alias Cauldron3D.Frame
  alias CauldronGPU.Texture
  alias ElixirQuake.Screen

  @see_through 255

  @doc "The overlay of `view` laid out as `layout`, with `menu` open (or `nil`), the palette curved by `gamma`."
  @spec texture(map(), Screen.t(), term(), number()) :: Texture.t()
  def texture(view, %Screen{} = layout, menu, gamma) do
    {view_width, view_height} = layout.view

    frame =
      layout
      |> Screen.backdrop()
      |> Frame.blit(Frame.new(view_width, view_height, @see_through), layout.at)
      |> Screen.layers(view, layout, menu)

    %Texture{
      width: frame.width,
      height: frame.height,
      pixels: rgba(frame, colours(Screen.palette(view, gamma))),
      filter: :nearest,
      wrap: :clamp,
      mipmaps: false
    }
  end

  defp rgba(%Frame{width: width, pixels: pixels}, colours) do
    clear = :binary.copy(<<@see_through>>, width)
    transparent = :binary.copy(<<0, 0, 0, 0>>, width)

    for <<row::binary-size(^width) <- pixels>>,
      into: <<>>,
      do: row(row, clear, transparent, colours)
  end

  defp row(clear, clear, transparent, _colours), do: transparent

  defp row(row, _clear, _transparent, colours),
    do: for(<<index <- row>>, into: <<>>, do: elem(colours, index))

  defp colours(palette) do
    for(<<r, g, b <- palette>>, do: <<r, g, b, 255>>)
    |> List.to_tuple()
    |> put_elem(@see_through, <<0, 0, 0, 0>>)
  end
end
