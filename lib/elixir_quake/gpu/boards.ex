defmodule ElixirQuake.Gpu.Boards do
  @moduledoc """
  A view's sprites (`.spr` things: explosions, flames, bubbles) and particles as one
  `CauldronGPU.Billboards` mesh facing the camera, put again each tick under the same
  mesh id and shown as one instance.

      {changes, handle, models} = ElixirQuake.Gpu.Boards.changes(view, camera, scale, handle, models, target, id)

  A sprite is its picture at the entity's frame, the picture's own origin pixel on the
  entity, upright sprites turning only about the vertical. A particle is a square one
  map unit across in its palette colour. Both are drawn unlit.
  """

  alias Cauldron3D.Formats.Spr
  alias CauldronGPU.{Billboards, Camera, Handle, Instance, Target}
  alias ElixirQuake.Assets
  alias ElixirQuake.Gpu.Models

  @doc """
  The changes showing `view`'s sprites and particles as instance `id`, seen by `camera`,
  map units `scale` metres each; `handle` is the mesh handle from last time (`nil` at
  first). Answers the changes, the mesh handle to keep and the models.
  """
  @spec changes(
          map(),
          Camera.t(),
          number(),
          Handle.t() | nil,
          Models.t(),
          Target.t(),
          pos_integer()
        ) :: {[CauldronGPU.Stream.change()], Handle.t() | nil, Models.t()}
  def changes(view, camera, scale, handle, models, target, id) do
    {sprites, materials, models} = sprites(view, scale, models, target)
    {particles, materials, models} = particles(view, scale, materials, models, target)
    {mesh, keys} = Billboards.mesh(sprites ++ particles, camera)
    show(mesh, Enum.map(keys, &Map.fetch!(materials, &1)), handle, models, target, id)
  end

  defp show(nil, _materials, nil, models, _target, _id), do: {[], nil, models}

  defp show(nil, _materials, handle, models, _target, id),
    do: {[{:instance, id, %Instance{mesh: handle, hidden: true}}], handle, models}

  defp show(mesh, materials, nil, models, target, id) do
    handle = Target.mesh(target, mesh)
    {[instance(id, handle, materials)], handle, models}
  end

  defp show(mesh, materials, handle, models, _target, id),
    do: {[{:mesh, handle.id, mesh}, instance(id, handle, materials)], handle, models}

  defp instance(id, handle, materials),
    do: {:instance, id, %Instance{mesh: handle, materials: materials, shadows: false}}

  defp sprites(view, scale, models, target) do
    (view.entities ++ view.statics)
    |> Enum.reduce({[], %{}, models}, fn thing, acc -> sprite(thing, view, scale, target, acc) end)
  end

  defp sprite(%{model: name} = thing, view, scale, target, {boards, materials, models} = acc) do
    case Assets.model(name) do
      %{kind: :sprite, data: %Spr{} = sprite} ->
        picture = Spr.picture(sprite, thing.frame, view.time)
        {material, models} = Models.sprite_material(models, target, name, picture)
        key = {:sprite, material.id}
        board = board(thing.origin, picture, sprite.kind, scale, key)
        {[board | boards], Map.put(materials, key, material), models}

      _ ->
        acc
    end
  end

  defp board(origin, %{texture: texture, origin: {pixel_x, pixel_y}}, kind, scale, key) do
    %{
      at: point(origin, scale),
      size: {texture.width * scale, texture.height * scale},
      key: key,
      offset: {(pixel_x - texture.width / 2) * scale, (texture.height / 2 - pixel_y) * scale},
      upright: kind in [:parallel_upright, :facing_upright]
    }
  end

  defp particles(view, scale, materials, models, target) do
    Enum.reduce(view.particles, {[], materials, models}, fn %{origin: origin, colour: colour},
                                                            {boards, materials, models} ->
      {material, models} = Models.colour_material(models, target, colour)
      key = {:colour, colour}
      board = %{at: point(origin, scale), size: {scale, scale}, key: key}
      {[board | boards], Map.put(materials, key, material), models}
    end)
  end

  defp point({x, y, z}, scale), do: {x * scale, z * scale, -y * scale}
end
