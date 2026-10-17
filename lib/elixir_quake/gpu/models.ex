defmodule ElixirQuake.Gpu.Models do
  @moduledoc """
  The models, pictures and materials a map's picture uses on a graphics card, each
  uploaded through a `CauldronGPU.Target` the first time it is asked for and kept until
  `release/2`.

      models = ElixirQuake.Gpu.Models.new(palette)
      {model, models} = ElixirQuake.Gpu.Models.alias_model(models, target, "progs/soldier.mdl")
      {material, models} = ElixirQuake.Gpu.Models.alias_material(models, target, "progs/soldier.mdl", 0)

  Palette colour 255 of a sprite is see-through.
  """

  alias Cauldron3D.Formats.Mdl
  alias CauldronGPU.{AliasModel, Handle, Material, Target, Texture}
  alias ElixirQuake.Assets

  @type t :: %__MODULE__{palette: binary(), colours: tuple(), kept: map()}

  @enforce_keys [:palette, :colours]
  defstruct [:palette, :colours, kept: %{}]

  @doc "Nothing uploaded yet; `palette` is the game's 768-byte palette."
  @spec new(binary()) :: t()
  def new(palette) do
    colours = for(<<r, g, b <- palette>>, do: <<r, g, b, 255>>) |> List.to_tuple()
    %__MODULE__{palette: palette, colours: colours}
  end

  @doc "The alias model file `name` uploaded (`CauldronGPU.AliasModel`), or `nil` when it is not one."
  @spec alias_model(t(), Target.t(), String.t()) :: {AliasModel.t() | nil, t()}
  def alias_model(models, target, name) do
    kept(models, {:alias, name}, fn ->
      case Assets.model(name) do
        %{kind: :alias, data: %Mdl{} = mdl} -> AliasModel.upload(target, mdl, models.palette)
        _ -> nil
      end
    end)
  end

  @doc "A material drawing skin `skin` of the alias model `name`, lit by its instance's `shading`."
  @spec alias_material(t(), Target.t(), String.t(), non_neg_integer()) :: {Handle.t() | nil, t()}
  def alias_material(models, target, name, skin) do
    with {%AliasModel{} = model, models} <- alias_model(models, target, name) do
      kept(models, {:alias_material, name, skin}, fn ->
        AliasModel.material(target, model, skin: skin)
      end)
    end
  end

  @doc "The brush model file `name` (an item box such as `maps/b_bh25.bsp`) uploaded, or `nil`."
  @spec brush_model(t(), Target.t(), String.t()) :: {CauldronGPU.Bsp.t() | nil, t()}
  def brush_model(models, target, name) do
    kept(models, {:brush, name}, fn ->
      case Assets.model(name) do
        %{kind: :brush, data: %{bsp: bsp}} ->
          CauldronGPU.Bsp.upload(target, bsp, models.palette, filter: :nearest)

        _ ->
          nil
      end
    end)
  end

  @doc "An unlit, see-through-where-clear material showing a sprite picture `%{texture:}` of the sprite file `name`."
  @spec sprite_material(t(), Target.t(), String.t(), map()) :: {Handle.t(), t()}
  def sprite_material(models, target, name, %{texture: picture} = shown) do
    kept(models, {:sprite, name, :erlang.phash2(shown)}, fn ->
      pixels = for <<index <- picture.pixels>>, into: <<>>, do: clear(models.colours, index)

      texture =
        Target.texture(target, %Texture{
          width: picture.width,
          height: picture.height,
          pixels: pixels,
          filter: :nearest,
          wrap: :clamp
        })

      Target.material(target, %Material{
        base_texture: texture,
        unlit: true,
        alpha_cutoff: 0.5,
        double_sided: true
      })
    end)
  end

  @doc "An unlit material of palette colour `colour`, for particles."
  @spec colour_material(t(), Target.t(), byte()) :: {Handle.t(), t()}
  def colour_material(models, target, colour) do
    kept(models, {:colour, colour}, fn ->
      texture =
        Target.texture(target, %Texture{
          width: 1,
          height: 1,
          pixels: elem(models.colours, colour),
          filter: :nearest,
          mipmaps: false
        })

      Target.material(target, %Material{base_texture: texture, unlit: true, double_sided: true})
    end)
  end

  @doc "Lets every upload go."
  @spec release(t(), Target.t()) :: :ok
  def release(%__MODULE__{kept: kept}, target) do
    kept
    |> Map.values()
    |> Enum.flat_map(&handles/1)
    |> Enum.uniq_by(&{&1.kind, &1.id})
    |> Enum.each(&Target.release(target, &1))
  end

  defp clear(_colours, 255), do: <<0, 0, 0, 0>>
  defp clear(colours, index), do: elem(colours, index)

  defp kept(%__MODULE__{kept: kept} = models, key, make) do
    case kept do
      %{^key => value} ->
        {value, models}

      _ ->
        value = make.()
        {value, %{models | kept: Map.put(kept, key, value)}}
    end
  end

  defp handles(nil), do: []
  defp handles(%Handle{keeps: keeps} = handle), do: [handle | keeps]
  defp handles(%AliasModel{} = model), do: AliasModel.handles(model)

  defp handles(%CauldronGPU.Bsp{} = world),
    do:
      world.handles ++ Enum.flat_map(world.models, fn {mesh, materials} -> [mesh | materials] end)
end
