defmodule ElixirQuake.Gpu do
  @moduledoc """
  The player's picture described for a graphics card (`CauldronGPU`), as a scene's
  `:gpu` takes it (`Cauldron2D.Client.Game`): the map's world and brush models, alias
  models, item boxes, sprites, particles, beams and the held weapon in the world; the
  light styles; the status bar, messages, tally, closing text and menu as an overlay
  (`ElixirQuake.Gpu.Overlay`); damage, bonus, power-up and liquid washes as a screen
  tint.

      gpu = ElixirQuake.Gpu.scene(view, menu: menu, options: options)
      {changes, cache} = gpu.(target, cache, {960, 600}, aspect)

  The cache holds one map's uploads: the map and its sky, and the models, pictures and
  materials seen so far. A view of another map lets them all go and starts again. Options are
  `ElixirQuake.Render.picture/4`'s; the brightness option (`:gamma`) curves the finished
  picture.

  The overlay is drawn at Quake's own 2D width, 320 pixels, and as tall as keeps the
  picture's shape (the renderer stretches it to the frame), and is sent again only when
  it changes. The world is drawn into the part of the frame the overlay leaves for it.

  Instance ids: 1 is the world, 2 the sprites and particles, 16 and up the things
  (`ElixirQuake.Gpu.Slots`).
  """

  alias CauldronGPU.{Handle, Target, Texture}
  alias ElixirQuake.{Assets, Screen}
  alias ElixirQuake.Gpu.{Boards, Eye, Models, Overlay, Slots, Things, World}

  @world_id 1
  @boards_id 2
  @first_thing_id 16
  @snap_distance 64.0
  @overlay_width 320

  @type t :: %__MODULE__{
          map: String.t(),
          world: CauldronGPU.Bsp.t(),
          sky: CauldronGPU.Environment.sky_picture(),
          models: Models.t(),
          slots: Slots.t(),
          boards: Handle.t() | nil,
          overlay: {Handle.t(), Texture.t()} | nil,
          gamma: number() | nil,
          eye: {number(), number(), number()} | nil
        }
  @type gpu :: (Target.t(), t() | nil, {pos_integer(), pos_integer()}, number() ->
                  {[CauldronGPU.Stream.change()], t()})

  @enforce_keys [:map, :world, :sky, :models, :slots]
  defstruct [:map, :world, :sky, :models, :slots, boards: nil, overlay: nil, gamma: nil, eye: nil]

  @doc "The scene's `:gpu` function for `view`."
  @spec scene(map(), keyword()) :: gpu()
  def scene(view, opts \\ []),
    do: fn target, cache, size, aspect -> frame(view, opts, target, cache, size, aspect) end

  @doc "One tick of `view` at `size` pixels: the changes to submit through `target` and the cache to keep."
  @spec frame(map(), keyword(), Target.t(), t() | nil, {pos_integer(), pos_integer()}, number()) ::
          {[CauldronGPU.Stream.change()], t()}
  def frame(view, opts, target, cache, size, aspect) do
    options = Keyword.get(opts, :options, %{})
    gamma = Map.get(options, :gamma, 1.0)
    {cache, opening} = for_map(cache, target, view.map)
    layout = Screen.layout(view, overlay_size(size), aspect, options)
    camera = Eye.camera(view.camera, layout, cache.world.scale, jumped?(cache.eye, view.camera))
    {items, models} = Things.items(view, cache.world, cache.models, target)
    {ids, removals, slots} = Slots.assign(cache.slots, Enum.map(items, &elem(&1, 0)))
    placed = Enum.flat_map(items, fn {key, place} -> apply(place, Tuple.to_list(ids[key])) end)

    {boards, board_mesh, models} =
      Boards.changes(view, camera, cache.world.scale, cache.boards, models, target, @boards_id)

    texture = Overlay.texture(view, layout, Keyword.get(opts, :menu), gamma)
    {overlay, kept_overlay} = overlay(cache.overlay, texture, target)

    changes =
      opening ++
        environment(cache, gamma) ++
        removals ++
        [camera, light_styles(view), tint(view, gamma)] ++ placed ++ boards ++ overlay

    {changes,
     %{
       cache
       | models: models,
         slots: slots,
         boards: board_mesh,
         overlay: kept_overlay,
         gamma: gamma,
         eye: view.camera.origin
     }}
  end

  defp overlay_size({width, height}) when width > @overlay_width,
    do: {@overlay_width, max(round(height * @overlay_width / width), 1)}

  defp overlay_size(size), do: size

  defp for_map(%__MODULE__{map: map} = cache, _target, map), do: {cache, []}

  defp for_map(nil, target, map), do: start(target, map, nil, [])

  defp for_map(%__MODULE__{} = cache, target, map) do
    World.release(cache.world, cache.sky, target)
    Models.release(cache.models, target)
    release(target, cache.boards)
    gone = [@boards_id | Slots.ids(cache.slots)]
    start(target, map, cache.overlay, Enum.map(gone, &{:remove_instance, &1}))
  end

  defp start(target, map, overlay, removals) do
    {world, sky} = World.upload(target, map)

    cache = %__MODULE__{
      map: map,
      world: world,
      sky: sky,
      models: Models.new(Assets.get().palette),
      slots: Slots.new(@first_thing_id),
      overlay: overlay
    }

    {cache, removals ++ World.opening(world, @world_id)}
  end

  defp environment(%__MODULE__{gamma: gamma}, gamma), do: []
  defp environment(%__MODULE__{sky: sky}, gamma), do: [World.environment(sky, gamma)]

  defp release(_target, nil), do: :ok
  defp release(target, %Handle{} = handle), do: Target.release(target, handle)

  defp jumped?(nil, _camera), do: true

  defp jumped?({ax, ay, az}, %{origin: {bx, by, bz}}) do
    {dx, dy, dz} = {bx - ax, by - ay, bz - az}
    dx * dx + dy * dy + dz * dz > @snap_distance * @snap_distance
  end

  defp overlay(nil, %Texture{} = texture, target) do
    handle = Target.texture(target, texture)
    {[{:overlay, handle}], {handle, texture}}
  end

  defp overlay({_handle, texture} = kept, texture, _target), do: {[], kept}

  defp overlay({handle, _shown}, %Texture{} = texture, _target),
    do: {[{:texture, handle.id, texture}], {handle, texture}}

  defp light_styles(%{styles: styles}),
    do: {:light_styles, styles |> Tuple.to_list() |> Enum.map(&(&1 / 256))}

  defp tint(view, gamma) do
    {r, g, b, share} = Screen.blend(view.washes)
    {:screen_tint, {curved(r, gamma), curved(g, gamma), curved(b, gamma), share}}
  end

  defp curved(value, gamma), do: :math.pow(max(min(value / 255, 1.0), 0.0), gamma)
end
