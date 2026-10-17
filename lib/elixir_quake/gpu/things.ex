defmodule ElixirQuake.Gpu.Things do
  @moduledoc """
  The solid things of a view as graphics card instances: brush entities (doors, lifts,
  platforms) placing the map's brush model `*N`, alias models posed by their frame,
  item boxes, the held weapon and lightning beams. Sprites and particles are
  `ElixirQuake.Gpu.Boards`'.

      {items, models} = ElixirQuake.Gpu.Things.items(view, world, models, target)

  An item is `{key, place}`: `key` names the thing from tick to tick, and
  `place.(id, fresh?)` answers the changes showing it as instance `id`, `fresh?` when
  the id is new this tick.

  Alias models are shaded by `ElixirQuake.LightPoint.shading/1` of the light where they
  stand, the held weapon by the light at the eye (never below 24), beams at full
  brightness. Quake's `ambient + directional * max(n · toward, 0)` is given to the
  renderer as the straight line nearest it over every facing,
  `ambient + directional / 4 + directional / 2 * (n · toward)`, light units of 255 being
  2.0 as the map's lightmaps are. The held weapon is drawn in front of the world.
  """

  alias Cauldron3D.Vec
  alias CauldronGPU.{AliasModel, Instance, Placement}
  alias ElixirQuake.{Assets, LightPoint}
  alias ElixirQuake.Gpu.Models

  @type item :: {term(), (pos_integer(), boolean() -> [CauldronGPU.Stream.change()])}

  @beam_step 30.0
  @weapon_darkest 24
  @full_light 255
  @light_unit 2 / 255

  @doc "The items of `view`, whose map is uploaded as `world`."
  @spec items(map(), CauldronGPU.Bsp.t(), Models.t(), CauldronGPU.Target.t()) ::
          {[item()], Models.t()}
  def items(view, world, models, target) do
    %{bsp: bsp} = Assets.map(view.map)
    context = %{view: view, world: world, bsp: bsp, target: target}

    things =
      Enum.map(view.entities, &{{:entity, &1.entity, &1.model}, &1}) ++
        Enum.map(view.statics, &{{:static, &1.model, &1.origin}, &1})

    {placed, models} =
      things
      |> Enum.uniq_by(&elem(&1, 0))
      |> Enum.flat_map_reduce(models, fn {key, thing}, acc -> thing(key, thing, context, acc) end)

    {weapon, models} = weapon(view, context, models)
    {beams, models} = beams(view, context, models)
    {placed ++ weapon ++ beams, models}
  end

  defp thing(key, %{model: "*" <> number} = thing, context, models) do
    case CauldronGPU.Bsp.model(context.world, String.to_integer(number)) do
      nil -> {[], models}
      {mesh, materials} -> {[brush(key, mesh, materials, thing, context.world.scale)], models}
    end
  end

  defp thing(key, %{model: name} = thing, context, models) do
    case Assets.model(name) do
      %{kind: :alias} -> alias_thing(key, thing, context, models)
      %{kind: :brush} -> box(key, thing, context, models)
      _ -> {[], models}
    end
  end

  defp alias_thing(key, thing, context, models) do
    %{view: view, bsp: bsp, target: target, world: world} = context
    shading = shading(LightPoint.at(bsp, thing.origin, view.styles))

    case posed(models, target, thing.model, thing.skin) do
      {nil, models} ->
        {[], models}

      {{model, material}, models} ->
        {pitch, yaw, roll} = thing.angles
        yaw = if AliasModel.rotates?(model), do: :math.fmod(100 * view.time, 360.0), else: yaw
        transform = Placement.transform(world.scale, thing.origin, {-pitch, yaw, roll})
        sample = AliasModel.frame(model, thing.frame, view.time)
        {[alias_item(key, model, material, %{shading: shading}, transform, sample)], models}
    end
  end

  defp box(key, thing, context, models) do
    case Models.brush_model(models, context.target, thing.model) do
      {nil, models} ->
        {[], models}

      {item, models} ->
        case CauldronGPU.Bsp.model(item, 0) do
          nil -> {[], models}
          {mesh, materials} -> {[brush(key, mesh, materials, thing, item.scale)], models}
        end
    end
  end

  defp brush(key, mesh, materials, %{origin: origin, angles: {pitch, yaw, roll}}, scale) do
    transform = Placement.transform(scale, origin, {-pitch, yaw, roll})

    {key,
     fn id, fresh? ->
       [
         {:instance, id,
          %Instance{mesh: mesh, materials: materials, transform: transform, snap: fresh?}}
       ]
     end}
  end

  defp weapon(%{weapon: nil}, _context, models), do: {[], models}

  defp weapon(%{weapon: %{model: name, frame: frame}, camera: camera} = view, context, models) do
    lit = max(LightPoint.at(context.bsp, camera.origin, view.styles), @weapon_darkest)

    case posed(models, context.target, name, 0) do
      {nil, models} ->
        {[], models}

      {{model, material}, models} ->
        {pitch, yaw, roll} = camera.angles
        {forward, _right, _up} = QuakeServer.Angles.vectors({pitch, yaw, 0.0})
        bob = Map.get(camera, :bob, 0.0)
        {x, y, z} = Vec.madd(camera.origin, forward, bob * 0.4)
        origin = {x, y, z + bob - 1.0}
        transform = Placement.transform(context.world.scale, origin, {pitch, yaw, roll})
        sample = AliasModel.frame(model, frame, view.time)
        fields = %{shading: shading(lit), in_front: true, shadows: false}
        {[alias_item(:weapon, model, material, fields, transform, sample)], models}
    end
  end

  defp beams(view, context, models) do
    view.beams
    |> Enum.with_index()
    |> Enum.flat_map_reduce(models, fn {beam, index}, acc -> beam(beam, index, context, acc) end)
  end

  defp beam(%{model: name, from: from, to: to}, index, context, models) do
    case posed(models, context.target, name, 0) do
      {nil, models} ->
        {[], models}

      {{model, material}, models} ->
        offset = Vec.sub(to, from)
        {pitch, yaw, _} = QuakeServer.Angles.of(offset)
        direction = Vec.normalize(offset)
        sample = AliasModel.frame(model, 0, context.view.time)
        full = shading(@full_light, 0, {1.0, 0.0, 0.0})

        segments =
          for step <- 0..trunc(Vec.length(offset) / @beam_step)//1 do
            origin = Vec.madd(from, direction, step * @beam_step)
            turn = {-pitch, yaw, :rand.uniform(360) * 1.0}
            transform = Placement.transform(context.world.scale, origin, turn)
            alias_item({:beam, index, step}, model, material, %{shading: full}, transform, sample)
          end

        {segments, models}
    end
  end

  defp posed(models, target, name, skin) do
    case Models.alias_model(models, target, name) do
      {nil, models} ->
        {nil, models}

      {model, models} ->
        {material, models} = Models.alias_material(models, target, name, skin)
        {{model, material}, models}
    end
  end

  defp alias_item(key, model, material, fields, transform, sample) do
    instance = struct!(AliasModel.instance(model, [material], transform), fields)

    {key, fn id, fresh? -> AliasModel.pose(model, id, %{instance | snap: fresh?}, sample) end}
  end

  defp shading(lit) do
    {ambient, directional, toward} = LightPoint.shading(lit)
    shading(ambient + directional / 4, directional / 2, toward)
  end

  defp shading(ambient, directional, {x, y, z}) do
    {grey(ambient * @light_unit), grey(directional * @light_unit), {x, z, -y}}
  end

  defp grey(value), do: {value, value, value}
end
