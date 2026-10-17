defmodule ElixirQuake.Gpu.World do
  @moduledoc """
  A map on a graphics card: its textures, lightmaps and brush models uploaded
  (`CauldronGPU.Bsp`, textures drawn unfiltered as Quake draws them), its sky's two
  layers, and the changes that set the scene up for it.

      {world, sky} = ElixirQuake.Gpu.World.upload(target, "e1m1")
      changes = [ElixirQuake.Gpu.World.environment(sky, 1.0) | ElixirQuake.Gpu.World.opening(world, 1)]
  """

  alias CauldronGPU.{Bsp, Environment, Instance, Target}
  alias ElixirQuake.Assets

  @doc "Map `name` uploaded through `target`, with its sky picture (`nil` when it has no sky)."
  @spec upload(Target.t(), String.t()) :: {Bsp.t(), Environment.sky_picture()}
  def upload(target, name) do
    %{bsp: bsp} = Assets.map(name)
    palette = Assets.get().palette
    {Bsp.upload(target, bsp, palette, filter: :nearest), Bsp.sky_layers(target, bsp, palette)}
  end

  @doc """
  The surroundings of a Quake picture: lit by baked light alone, which scales the
  textures' display colours as Quake's colour table does, with no tone curve, fog,
  reflections or glow; `sky` in the sky; the finished picture curved by `gamma` (0.5 to
  1, lower brighter), as the player's brightness option curves the palette.
  """
  @spec environment(Environment.sky_picture(), number()) :: Environment.t()
  def environment(sky, gamma) do
    %Environment{
      ambient_intensity: 0.0,
      fog_density: 0.0,
      reflections: 0.0,
      bloom_strength: 0.0,
      tone_map: :clamp,
      exposure: 1.0,
      light_space: :display,
      gamma: gamma,
      sky_picture: sky
    }
  end

  @doc "The changes that turn every effect off and place the map's world model as instance `id`."
  @spec opening(Bsp.t(), pos_integer()) :: [CauldronGPU.Stream.change()]
  def opening(%Bsp{} = world, id) do
    {mesh, materials} = Bsp.model(world, 0)

    [
      {:effects, []},
      {:instance, id,
       %Instance{mesh: mesh, materials: materials, transform: Bsp.transform(world), snap: true}}
    ]
  end

  @doc "Lets every handle of `world` and `sky` go."
  @spec release(Bsp.t(), Environment.sky_picture(), Target.t()) :: :ok
  def release(%Bsp{} = world, sky, target) do
    world.models
    |> Enum.flat_map(fn {mesh, materials} -> [mesh | materials] end)
    |> Kernel.++(world.handles ++ sky_handles(sky))
    |> Enum.uniq_by(&{&1.kind, &1.id})
    |> Enum.each(&Target.release(target, &1))
  end

  defp sky_handles(nil), do: []
  defp sky_handles({:layers, back, front}), do: [back, front]
end
