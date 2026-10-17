defmodule ElixirQuake.LightPoint do
  @moduledoc """
  How brightly the world is lit at a point: the lightmap of the first surface straight
  below it, within 2048 units, with each light style at its present scale. Models are
  lit by it.

      ElixirQuake.LightPoint.at(bsp, origin, styles)
      #=> 0..255
  """

  alias Cauldron3D.{Bsp, Vec}
  alias Cauldron3D.Bsp.Face

  @darkest_ambient 5

  @doc "The light (0 to 255) at `point`, styles scaled by `styles` (a tuple of scales by style, 256 normal)."
  @spec at(Bsp.t(), Vec.t(), tuple()) :: number()
  def at(%Bsp{} = bsp, {x, y, z} = point, styles) do
    %{heads: [head | _]} = elem(bsp.models, 0)

    case walk(bsp, head, point, {x, y, z - 2048}, styles) do
      nil -> 0
      light -> min(light, 255)
    end
  end

  @doc """
  How a model standing in light `lit` (as `at/3` gives it) is shaded, as Quake's software
  renderer shades alias models, in the form `Cauldron3D.Mesh.polygons/2` takes `:light`:
  `{ambient, directional, toward}`, each vertex lit
  `ambient + directional * max(normal · toward, 0)`. `ambient` is `lit` held to 5..128,
  `directional` is `lit` held so that the two add to at most 192, and `toward` is the
  map's +x.
  """
  @spec shading(number()) :: {number(), number(), Vec.t()}
  def shading(lit) do
    ambient = min(lit, 128)
    shade = max(min(lit, 192 - ambient), 0)
    {max(ambient, @darkest_ambient), shade, {1.0, 0.0, 0.0}}
  end

  defp walk(_bsp, node, _from, _to, _styles) when node < 0, do: nil

  defp walk(bsp, index, from, to, styles) do
    node = elem(bsp.nodes, index)
    {normal, distance} = elem(bsp.planes, node.plane)
    front = Vec.dot(from, normal) - distance
    back = Vec.dot(to, normal) - distance
    {near, far} = if front < 0, do: {node.back, node.front}, else: {node.front, node.back}

    if back < 0 == front < 0 do
      walk(bsp, near, from, to, styles)
    else
      mid = Vec.lerp(from, to, front / (front - back))

      walk(bsp, near, from, mid, styles) ||
        surface_light(bsp, node, mid, styles) ||
        walk(bsp, far, mid, to, styles)
    end
  end

  defp surface_light(bsp, node, point, styles) do
    count = Map.get(node, :face_count, 0)
    first = Map.get(node, :first_face, 0)

    Enum.find_value(first..(first + count - 1)//1, fn index ->
      face = elem(bsp.faces, index)
      if elem(bsp.textures, face.texture).kind == :solid, do: sample(bsp, face, point, styles)
    end)
  end

  defp sample(bsp, %Face{} = face, point, styles) do
    {s, t} = Face.st(face, point)
    {s_min, t_min} = face.mins
    {s_extent, t_extent} = face.extents
    {ds, dt} = {s - s_min, t - t_min}

    cond do
      ds < 0 or dt < 0 or ds > s_extent or dt > t_extent -> nil
      face.lightmap == nil -> 0
      true -> styled(bsp, face, div(trunc(ds), face.luxel), div(trunc(dt), face.luxel), styles)
    end
  end

  defp styled(bsp, face, column, row, styles) do
    {across, down} = Face.lightmap_size(face)

    face.styles
    |> Enum.with_index()
    |> Enum.reduce(0, fn {style, i}, acc ->
      at = face.lightmap + i * across * down + row * across + column
      scale = if style < tuple_size(styles), do: elem(styles, style), else: 256
      if at < byte_size(bsp.lightmaps), do: acc + :binary.at(bsp.lightmaps, at) * scale, else: acc
    end)
    |> div(256)
  end
end
